#!/usr/bin/env ruby

# Copyright (c) 2009 pablo flouret <quuxbaz@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

begin
   require 'rinotify'
rescue LoadError
   require 'rubygems'
   require 'rinotify'
end

require 'find'
require 'cgi'
require 'logger'
require 'optparse'
require 'xmmsclient'

class Xmms2Inotify
   CONFIG_DIR = File.join(Xmms.userconfdir, "clients", "xmms2-inotify")

   FLAGS = RInotify::MODIFY | RInotify::CREATE | RInotify::DELETE |
           RInotify::MOVED_FROM | RInotify::MOVED_TO

   def initialize(options)
      @options = options

      FileUtils.mkdir_p(CONFIG_DIR) unless File.directory?(CONFIG_DIR)

      init_log

      @xc = Xmms::Client.new("xmms2-inotify")

      begin
         @xc.connect(ENV["XMMS_PATH"])
      rescue Xmms::Client::ClientError
         @log.error "couldn't connect to server!"
         exit 1
      end

      @xc.on_disconnect { stop }

      @notify = RInotify.new
      @watched = {}
      @stop = false
      @dirs = []

      read_watch_dirs

      Thread.abort_on_exception = true
      @t = Thread.new do
         io = IO.new(@xc.io_fd)
         loop do
            r = select([io], [], [])
            @xc.io_in_handle if r[0][0] == io unless r[0].empty?
         end
      end
   end

   def init_log
      msg = "starting xmms2-inotify, log at #{File.join(CONFIG_DIR, "log")}\n"
      if @options[:quiet]
         file = File.open("/dev/null")
         msg = ""
      elsif @options[:stdout]
         file = STDOUT
      else
         file = File.open(File.join(CONFIG_DIR, "log"), File::WRONLY | File::CREAT | File::TRUNC)
         file.sync = true
      end
      @log = Logger.new(file)
      @log.level = (@options[:verbose] and Logger::DEBUG or Logger::INFO)
      @log.datetime_format = "%Y-%m-%d %H:%M:%S"
      print msg
   end

   def read_watch_dirs
      path = (@options[:watch_file] or File.join(CONFIG_DIR, "watch_dirs"))
      begin
         File.open(path) do |f|
            f.each_line do |line|
               Dir.glob(line.strip) { |d| @dirs << File.expand_path(d) if File.directory? d }
            end
         end
         raise "no valid directory to watch in #{path}" if @dirs.empty?
      rescue Errno::ENOENT
         @log.error "put some directories in #{path} to monitor them!"
         File.open(path, 'w') { |f| f.truncate(0) }
         exit 1
      rescue
         @log.error "#{$!}"
         exit 1
      end
   end

   def setup_watch_dirs
      puts @dirs.inspect
      @dirs.each do |dir|
         Find.find(dir) do |subdir|
            next unless FileTest.directory? subdir
            watch_desc = @notify.add_watch(subdir, FLAGS)
            @watched[watch_desc] = File.expand_path(subdir)
            @log.info "watching #{@watched[watch_desc]}"
         end
      end
   end

   def add(path)
      paths = []
      Find.find(path) { |p| paths.insert(0, p) }
      paths.each do |p|
         @log.info "adding #{path}"
         @xc.medialib_add_entry("file://#{p}")
      end
   end

   def rehash(id, path)
      @log.info "rehashing #{id} #{path}"
      @xc.medialib_rehash(id)
   end

   def remove(id, path="")
      @log.info "removed \##{id} #{path}"
      @xc.medialib_entry_remove(id)
   end

   def move(id, path)
      @log.info "moving \##{id} to #{path}"
      @xc.medialib_entry_move(id, "file://#{path}")
   end

   def get_id(path)
      url = "file://#{CGI.escape(path).gsub("%2F", "/")}"
      c = Xmms::Collection.parse(%(url:"#{url}"))

      r = @xc.coll_query_ids(c).wait
      ids = (r.value unless (r.nil? or r.error?)) or []
      (ids[0] unless ids.nil? or ids.empty?) or nil
   end

   def watch
      last_was_moved_from = false
      moved_from = []
      unclaimed_moved_from = []
      ticks = 0

      setup_watch_dirs

      until @stop do
         @xc.io_out_handle if @xc.io_want_out # bah!

         have_events = @notify.wait_for_events(5)

         unless last_was_moved_from or moved_from.empty?
            unclaimed_moved_from.concat(moved_from)
            moved_from = []
         end

         last_was_moved_from = false

         ticks += 1
         if ticks == 5
            # remove songs moved out of the watched folders periodically
            unclaimed_moved_from.each do |e|
               e.kind_of?(Numeric) and remove(e) or remove(e[0])
            end
            unclaimed_moved_from = []
            ticks = 0
         end
         next unless have_events

         @notify.each_event do |event|
            path = File.join(@watched[event.watch_descriptor], event.name || '')
            begin
               if event.check_mask(RInotify::MODIFY)
                  rehash(get_id(path), path)
               elsif event.check_mask RInotify::CREATE
                  add(path)
               elsif event.check_mask RInotify::DELETE
                  remove(get_id(path), path)
               elsif event.check_mask RInotify::MOVED_FROM
                  id = get_id(path)

                  if id
                     moved_from.push(id)
                  else
                     # moving a folder, get all the songs within it from the mlib
                     url = "file://#{CGI.escape(path).gsub("%2F", "/")}"
                     c = Xmms::Collection.parse(%(url:"#{url}/*"))

                     r = @xc.coll_query_info(c, ['id', 'url']).wait
                     infos = (r.value unless (r.nil? or r.error?)) or []
                     infos.each do |d|
                        moved_from.push([d[:id], CGI.unescape(d[:url].sub(url+'/', ''))])
                     end
                  end
               elsif event.check_mask RInotify::MOVED_TO
                  if last_was_moved_from
                     moved_from.reverse_each do |e|
                        if e.kind_of? Numeric
                           move(e, path)
                        else
                           move(e[0], File.join(path, e[1]))
                        end
                     end
                     moved_from = []
                  else
                     add(path) # moved from an unwatched folder
                  end
               end

               # no cookie field in the rinotify lib, so just hope MOVED_TOs
               # come right after MOVED_FROMs, *crosses fingers*
               last_was_moved_from = event.check_mask RInotify::MOVED_FROM
            rescue Xmms::Client::ClientError
               @log.debug $!
            rescue TypeError
               @log.debug $!
            end
         end
      end
   end

   def stop
      @log.info "shutting down"
      @log.close
      @stop = true
      @t.kill if @t.alive?
      @watched.each_key do |d|
         begin
            @notify.rm_watch(d)
         rescue
         end
      end
   end
end

options = {:verbose => false, :stdout => false, :watch_file => nil}
begin
   op = OptionParser.new do |opts|
      opts.banner = "usage: xmms2-inotify.rb [-v] [-q] [-s] [-w PATH]"
      opts.on("-q", "--[no-]quiet", "don't log or print anything") { |q| options[:quiet] = v }
      opts.on("-v", "--[no-]verbose", "show debug information") { |v| options[:verbose] = v }
      opts.on("-s", "--[no-]stdout", "log to stdout instead of log file") { |s| options[:stdout] = s }
      opts.on("-w", "--watch-dirs-file PATH", "path to the file with the directories to watch") do |f|
         options[:watch_file] = f
      end
   end
   op.parse!
rescue OptionParser::MissingArgument
   puts "xmms2-inotify.rb: error: #{$!}\n\n#{op}"
   exit 1
end

$x2i = Xmms2Inotify.new(options)
trap("SIGINT") { $x2i.stop }
$x2i.watch

# vim: ft=ruby et sw=3
