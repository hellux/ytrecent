PREFIX = ""
BINDIR=$(DESTDIR)$(PREFIX)/bin

install:
	mkdir -p $(BINDIR)
	install -m755 ytr.sh $(BINDIR)/ytr
