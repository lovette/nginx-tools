#!/usr/bin/make -f

LBINDIR = usr/local/bin
MANDIR = usr/share/man/man1
BASHCOMPDIR = etc/bash_completion.d

all:

install:
	# Create directories
	install -d $(DESTDIR)/$(LBINDIR)
	install -d $(DESTDIR)/$(MANDIR)

	# Install user scripts
	install -m 755 nginx-sites/nginx-sites.sh $(DESTDIR)/$(LBINDIR)/nginx-sites
	install -m 755 nginx-minify-conf/nginx-minify-conf.sh $(DESTDIR)/$(LBINDIR)/nginx-minify-conf

	# Install man page
	gzip -c nginx-sites/man/nginx-sites.1 > $(DESTDIR)/$(MANDIR)/nginx-sites.1.gz
	gzip -c nginx-minify-conf/man/nginx-minify-conf.1 > $(DESTDIR)/$(MANDIR)/nginx-minify-conf.1.gz

	# Install bash completion
	install -m 644 nginx-sites/bash_completion.sh $(DESTDIR)/$(BASHCOMPDIR)/nginx-sites

uninstall:
	# Remove user scripts
	-rm -f  $(DESTDIR)/$(LBINDIR)/nginx-sites
	-rm -f  $(DESTDIR)/$(LBINDIR)/nginx-minify-conf

	# Remove man page
	-rm -f $(DESTDIR)/$(MANDIR)/nginx-sites.1.gz
	-rm -f $(DESTDIR)/$(MANDIR)/nginx-minify-conf.1.gz

	# Remove bash completion
	-rm -f $(DESTDIR)/$(BASHCOMPDIR)/nginx-sites

help2man:
	help2man -n "manage nginx sites" -s 1 -N -i nginx-sites/man/nginx-sites.1.inc -o nginx-sites/man/nginx-sites.1 "bash nginx-sites/nginx-sites.sh"
	help2man -n "minify a nginx configuration file" -s 1 -N -o nginx-minify-conf/man/nginx-minify-conf.1 "bash nginx-minify-conf/nginx-minify-conf.sh"
