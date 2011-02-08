# nginx-tools

A collection of tools for the [nginx Web server](http://www.nginx.org/)


Requirements
---

* [nginx](http://www.nginx.org/)
* [BASH 3.0 or later](http://www.gnu.org/software/bash/)
* [Awk 3.0 or later](http://www.gnu.org/software/gawk/)


Installation
---
Download the archive and extract into a folder. Then, to install the package:

	make install

This installs admin scripts to `/usr/sbin`, user scripts to `/usr/local/bin` and
man pages to `/usr/share/man`. You can also stage the installation with:

	make DESTDIR=/stage/path install

You can undo the install with:

	make uninstall
