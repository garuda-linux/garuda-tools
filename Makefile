Version=0.15.9

PREFIX = /usr/local
SYSCONFDIR = /etc

SYSCONF = \
	data/garuda-tools.conf \
	data/branding.desc.d
APP_BASE = \
	applications/garuda-chroot-gui.desktop \

BIN_BASE = \
	bin/mkchroot \
	bin/basestrap \
	bin/garuda-chroot \
	bin/garuda-chroot-gui \
	bin/fstabgen \
	bin/signfile \
	bin/chroot-run

LIBS_BASE = \
	lib/util.sh \
	lib/util-mount.sh \
	lib/util-msg.sh \
	lib/util-fstab.sh

SHARED_BASE = \
	data/pacman-default.conf \
	data/pacman-multilib.conf \
	data/pacman-mirrors.conf

LIST_PKG = \
	$(wildcard data/pkg.list.d/*.list)

ARCH_CONF = \
	$(wildcard data/make.conf.d/*.conf)

BIN_PKG = \
	bin/checkpkg \
	bin/lddd \
	bin/finddeps \
	bin/find-libdeps \
	bin/signpkgs \
	bin/mkchrootpkg \
	bin/buildpkg \
	bin/buildtree

LIBS_PKG = \
	$(wildcard lib/util-pkg*.sh)

SHARED_PKG = \
	data/makepkg.conf

LIST_ISO = \
	$(wildcard data/iso.list.d/*.list)

BIN_ISO = \
	bin/buildiso \
	bin/testiso \
	bin/deployiso \
	bin/buildall \
    bin/checksumiso \
	bin/signiso

LIBS_ISO = \
	$(wildcard lib/util-iso*.sh) \
	lib/util-publish.sh

SHARED_ISO = \
	data/pacman-ght.conf \
	data/mkinitcpio.conf \
	data/profile.conf.example \
	data/dracut/miso.sh \
	data/dracut/parse-miso.sh \
	data/dracut/miso-generator.sh \
	data/dracut/module-setup.sh

CPIOHOOKS = \
	$(wildcard initcpio/hooks/*)

CPIOINST = \
	$(wildcard initcpio/install/*)

CPIO = \
	initcpio/script/miso_shutdown

MAN_XML = \
	buildpkg.xml \
	buildtree.xml \
	buildiso.xml \
	deployiso.xml \
	check-yaml.xml \
	garuda-tools.conf.xml \
	profile.conf.xml

BIN_YAML = \
	bin/check-yaml

LIBS_YAML = \
	lib/util-yaml.sh

SHARED_YAML = \
	data/linux.preset

all: $(BIN_BASE) $(BIN_PKG) $(BIN_ISO) $(BIN_YAML) doc

edit = sed -e "s|@datadir[@]|$(DESTDIR)$(PREFIX)/share/garuda-tools|g" \
	-e "s|@sysconfdir[@]|$(DESTDIR)$(SYSCONFDIR)/garuda-tools|g" \
	-e "s|@libdir[@]|$(DESTDIR)$(PREFIX)/lib/garuda-tools|g" \
	-e "s|@version@|${Version}|"

%: %.in Makefile
	@echo "GEN $@"
	@$(RM) "$@"
	@m4 -P $@.in | $(edit) >$@
	@chmod a-w "$@"
	@chmod +x "$@"

doc:
	mkdir -p man
	$(foreach var,$(MAN_XML),xsltproc --nonet /usr/share/docbook2X/xslt/man/docbook.xsl docbook/$(var) | db2x_manxml --output-dir man ;)

clean:
	rm -f $(BIN_BASE) ${BIN_PKG} ${BIN_ISO}
	rm -rf man

install_base:
	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/garuda-tools
	install -m0644 ${SYSCONF} $(DESTDIR)$(SYSCONFDIR)/garuda-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -m0755 ${BIN_BASE} $(DESTDIR)$(PREFIX)/bin

	install -dm0755 $(DESTDIR)$(PREFIX)/lib/garuda-tools
	install -m0644 ${LIBS_BASE} $(DESTDIR)$(PREFIX)/lib/garuda-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/share/garuda-tools
	install -m0644 ${SHARED_BASE} $(DESTDIR)$(PREFIX)/share/garuda-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/share/applications
	install -m0644 ${APP_BASE} $(DESTDIR)$(PREFIX)/share/applications

install_pkg:
	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/garuda-tools/pkg.list.d
	install -m0644 ${LIST_PKG} $(DESTDIR)$(SYSCONFDIR)/garuda-tools/pkg.list.d

	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/garuda-tools/make.conf.d
	install -m0644 ${ARCH_CONF} $(DESTDIR)$(SYSCONFDIR)/garuda-tools/make.conf.d

	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -m0755 ${BIN_PKG} $(DESTDIR)$(PREFIX)/bin

	ln -sf find-libdeps $(DESTDIR)$(PREFIX)/bin/find-libprovides

	install -dm0755 $(DESTDIR)$(PREFIX)/lib/garuda-tools
	install -m0644 ${LIBS_PKG} $(DESTDIR)$(PREFIX)/lib/garuda-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/share/garuda-tools
	install -m0644 ${SHARED_PKG} $(DESTDIR)$(PREFIX)/share/garuda-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/share/man/man1
	gzip -c man/buildpkg.1 > $(DESTDIR)$(PREFIX)/share/man/man1/buildpkg.1.gz
	gzip -c man/buildtree.1 > $(DESTDIR)$(PREFIX)/share/man/man1/buildtree.1.gz

install_iso:
	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/garuda-tools/iso.list.d
	install -m0644 ${LIST_ISO} $(DESTDIR)$(SYSCONFDIR)/garuda-tools/iso.list.d

	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -m0755 ${BIN_ISO} $(DESTDIR)$(PREFIX)/bin

	install -dm0755 $(DESTDIR)$(PREFIX)/lib/garuda-tools
	install -m0644 ${LIBS_ISO} $(DESTDIR)$(PREFIX)/lib/garuda-tools

	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/initcpio/hooks
	install -m0755 ${CPIOHOOKS} $(DESTDIR)$(SYSCONFDIR)/initcpio/hooks

	install -dm0755 $(DESTDIR)$(SYSCONFDIR)/initcpio/install
	install -m0755 ${CPIOINST} $(DESTDIR)$(SYSCONFDIR)/initcpio/install

	install -m0755 ${CPIO} $(DESTDIR)$(SYSCONFDIR)/initcpio


	install -dm0755 $(DESTDIR)$(PREFIX)/share/garuda-tools
	install -m0644 ${SHARED_ISO} $(DESTDIR)$(PREFIX)/share/garuda-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/share/man/man1
	gzip -c man/buildiso.1 > $(DESTDIR)$(PREFIX)/share/man/man1/buildiso.1.gz
	gzip -c man/deployiso.1 > $(DESTDIR)$(PREFIX)/share/man/man1/deployiso.1.gz

	install -dm0755 $(DESTDIR)$(PREFIX)/share/man/man5
	gzip -c man/garuda-tools.conf.5 > $(DESTDIR)$(PREFIX)/share/man/man5/garuda-tools.conf.5.gz
	gzip -c man/profile.conf.5 > $(DESTDIR)$(PREFIX)/share/man/man5/profile.conf.5.gz

install_yaml:
	install -dm0755 $(DESTDIR)$(PREFIX)/bin
	install -m0755 ${BIN_YAML} $(DESTDIR)$(PREFIX)/bin

	install -dm0755 $(DESTDIR)$(PREFIX)/lib/garuda-tools
	install -m0644 ${LIBS_YAML} $(DESTDIR)$(PREFIX)/lib/garuda-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/share/garuda-tools
	install -m0644 ${SHARED_YAML} $(DESTDIR)$(PREFIX)/share/garuda-tools

	install -dm0755 $(DESTDIR)$(PREFIX)/share/man/man1
	gzip -c man/check-yaml.1 > $(DESTDIR)$(PREFIX)/share/man/man1/check-yaml.1.gz

uninstall_base:
	for f in ${SYSCONF}; do rm -f $(DESTDIR)$(SYSCONFDIR)/garuda-tools/$$f; done
	for f in ${BIN_BASE}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in ${SHARED_BASE}; do rm -f $(DESTDIR)$(PREFIX)/share/garuda-tools/$$f; done
	for f in ${LIBS_BASE}; do rm -f $(DESTDIR)$(PREFIX)/lib/garuda-tools/$$f; done

uninstall_pkg:
	for f in ${LIST_PKG}; do rm -f $(DESTDIR)$(SYSCONFDIR)/garuda-tools/pkg.list.d/$$f; done
	for f in ${ARCH_CONF}; do rm -f $(DESTDIR)$(SYSCONFDIR)/garuda-tools/make.conf.d/$$f; done
	for f in ${BIN_PKG}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	rm -f $(DESTDIR)$(PREFIX)/bin/find-libprovides
	for f in ${SHARED_PKG}; do rm -f $(DESTDIR)$(PREFIX)/share/garuda-tools/$$f; done
	for f in ${LIBS_PKG}; do rm -f $(DESTDIR)$(PREFIX)/lib/garuda-tools/$$f; done
	rm -f $(DESTDIR)$(PREFIX)/share/man/man1/buildpkg.1.gz
	rm -f $(DESTDIR)$(PREFIX)/share/man/man1/buildtree.1.gz

uninstall_iso:
	for f in ${LIST_ISO}; do rm -f $(DESTDIR)$(SYSCONFDIR)/garuda-tools/iso.list.d/$$f; done
	for f in ${BIN_ISO}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in ${SHARED_ISO}; do rm -f $(DESTDIR)$(PREFIX)/share/garuda-tools/$$f; done

	for f in ${LIBS_ISO}; do rm -f $(DESTDIR)$(PREFIX)/lib/garuda-tools/$$f; done
	for f in ${CPIOHOOKS}; do rm -f $(DESTDIR)$(SYSCONFDIR)/initcpio/hooks/$$f; done
	for f in ${CPIOINST}; do rm -f $(DESTDIR)$(SYSCONFDIR)/initcpio/install/$$f; done
	for f in ${CPIO}; do rm -f $(DESTDIR)$(SYSCONFDIR)/initcpio/$$f; done
	rm -f $(DESTDIR)$(PREFIX)/share/man/man1/buildiso.1.gz
	rm -f $(DESTDIR)$(PREFIX)/share/man/man1/deployiso.1.gz
	rm -f $(DESTDIR)$(PREFIX)/share/man/man5/garuda-tools.conf.5.gz
	rm -f $(DESTDIR)$(PREFIX)/share/man/man5/profile.conf.5.gz

uninstall_yaml:
	for f in ${BIN_YAML}; do rm -f $(DESTDIR)$(PREFIX)/bin/$$f; done
	for f in ${LIBS_YAML}; do rm -f $(DESTDIR)$(PREFIX)/lib/garuda-tools/$$f; done
	for f in ${SHARED_YAML}; do rm -f $(DESTDIR)$(PREFIX)/share/garuda-tools/$$f; done
	rm -f $(DESTDIR)$(PREFIX)/share/man/man1/check-yaml.1.gz

install: install_base install_pkg install_iso install_yaml

uninstall: uninstall_base uninstall_pkg uninstall_iso uninstall_yaml

dist:
	git archive --format=tar --prefix=garuda-tools-$(Version)/ $(Version) | gzip -9 > garuda-tools-$(Version).tar.gz
	gpg --detach-sign --use-agent garuda-tools-$(Version).tar.gz

.PHONY: all clean install uninstall dist
