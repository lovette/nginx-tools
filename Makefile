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

	# Install man page
	gzip -c nginx-sites/man/nginx-sites.1 > $(DESTDIR)/$(MANDIR)/nginx-sites.1.gz

	# Install bash completion
	install -m 644 nginx-sites/bash_completion.sh $(DESTDIR)/$(BASHCOMPDIR)/nginx-sites

uninstall:
	# Remove user scripts
	-rm -f  $(DESTDIR)/$(LBINDIR)/nginx-sites

	# Remove man page
	-rm -f $(DESTDIR)/$(MANDIR)/nginx-sites.1.gz

	# Remove bash completion
	-rm -f $(DESTDIR)/$(BASHCOMPDIR)/nginx-sites

help2man:
	help2man -n "manage nginx sites" -s 1 -N -i nginx-sites/man/nginx-sites.1.inc -o nginx-sites/man/nginx-sites.1 "bash nginx-sites/nginx-sites.sh"
