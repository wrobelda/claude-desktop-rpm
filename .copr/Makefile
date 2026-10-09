# Copr "make srpm" entry point. Copr runs it as root in a mock chroot with
# network access:
#   make -f .copr/Makefile srpm outdir=<dir> spec=<spec>
#
# Downloads the upstream .debs listed in packaging/_service (the files OBS
# fetches with download_url) and builds the source RPM from the spec.

top     := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/..)
service := $(top)/packaging/_service
override spec   := $(or $(spec),$(top)/packaging/claude-desktop.spec)
override outdir := $(or $(outdir),$(CURDIR))

srpm:
	dnf -y install curl rpm-build
	sources=$$(mktemp -d) && \
	sed -n 's#.*<param name="url">\(.*\)</param>.*#\1#p' $(service) \
	    | (cd "$$sources" && xargs -n1 curl -fsSLO) && \
	rpmbuild -bs --define "_sourcedir $$sources" \
	    --define "_srcrpmdir $(outdir)" $(spec) && \
	rm -rf "$$sources"

.PHONY: srpm
