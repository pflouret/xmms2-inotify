xmms2-inotify.rb
================

Like `xmms2-mlib-updater`, but a little less crappy, e.g. preserves the id when
moving a file, can monitor more than one base path, more hackable, bleh.

No guarantees that it won't kill your medialib or kidnap your kids. You've been
warned.


Install
-------

    sudo gem install RInotify &&
    wget http://github.com/palbo/xmms2-inotify/raw/master/xmms2-inotify.rb &&
    chmod 755 xmms2-inotify.rb &&
    sudo mv xmms2-inotify.rb /usr/local/bin/xmms2-inotify.rb &&
    ln -s /usr/local/bin/xmms2-inotify.rb ~/.config/xmms2/startup.d/xmms2-inotify.rb


Configure
---------
Add directories to watch in `~/.config/xmms2/clients/xmms2-inotify/watch_dirs`

One per line, globbing allowed.


License
-------

    Copyright (c) 2009 pablo flouret <quuxbaz@gmail.com>

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

