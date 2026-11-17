SHELL := /usr/bin/env bash

ARCH ?= x86_64
DOCKER ?= docker
export DOCKER
# CI's entry point too: plain progress and the published toolchain image as a
# layer cache.
BUILDX := ./scripts/docker-build.sh
ARCHES := $(shell awk -F '|' '$$0 !~ /^#/ { print $$1 }' architectures.tsv)

.DEFAULT_GOAL := help

.PHONY: help list check build all smoke smoke-all verify package repro sources source-package update-sources clean

help:
	@echo "Static Linux troubleshooting binaries"
	@echo
	@echo "  make list                    List supported architectures"
	@echo "  make check                   Validate manifests and run ShellCheck"
	@echo "  make build ARCH=x86_64       Build one architecture into dist/"
	@echo "  make smoke ARCH=x86_64       Build and QEMU-smoke-test in Docker"
	@echo "  make all                     Build every architecture"
	@echo "  make smoke-all               Smoke-test every architecture"
	@echo "  make verify ARCH=x86_64      Verify an existing local build"
	@echo "  make package ARCH=x86_64     Create a deterministic tar.xz"
	@echo "  make repro                   Rebuild x86_64 with no cache and compare"
	@echo "  make sources                 Export verified upstream archives"
	@echo "  make source-package          Package corresponding source archives"
	@echo "  make update-sources          Repin upstream sources and open the update PR"
	@echo "  make clean                   Remove generated output"

list:
	@awk -F '|' '$$0 !~ /^#/ { printf "%-18s %s\n", $$1, $$5 }' architectures.tsv

# CircleCI's validate job runs exactly this.
check:
	./scripts/validate.sh
	shellcheck scripts/*.sh scripts/builders/*.sh scripts/lib/*.sh scripts/toolchain/*

build:
	$(BUILDX) artifact --build-arg ARCH=$(ARCH) --output type=local,dest=dist

all:
	@set -e; for arch in $(ARCHES); do $(MAKE) build ARCH="$$arch"; done

smoke:
	$(BUILDX) test --build-arg ARCH=$(ARCH) --load --tag statics-test:$(ARCH)

smoke-all:
	@set -e; for arch in $(ARCHES); do $(MAKE) smoke ARCH="$$arch"; done

verify:
	./scripts/verify.sh "dist/$(ARCH)" "$(ARCH)"

package: build
	./scripts/package.sh "$(ARCH)"

# The release gate, locally: a normal x86_64 build against an independent
# rebuild with no cache at all, toolchain included, at twice the make -j.
# The local exporter never deletes, so clear the tree before each build or
# stale files would land in both archives.
# The extra archive, when x86_64 has one, is compared the same way.
repro:
	rm -rf dist/x86_64 dist/x86_64-extra .build/repro
	$(MAKE) package ARCH=x86_64
	mkdir -p .build/repro
	mv dist/statics-x86_64.tar.xz .build/repro/
	if [ -f dist/statics-extra-x86_64.tar.xz ]; then mv dist/statics-extra-x86_64.tar.xz .build/repro/; fi
	rm -rf dist/x86_64 dist/x86_64-extra
	TOOLCHAIN_IMAGE= $(BUILDX) artifact --no-cache --build-arg ARCH=x86_64 \
		--build-arg JOBS=$$(( $$(nproc) * 2 )) --output type=local,dest=dist
	./scripts/package.sh x86_64
	@set -e; for name in statics-x86_64.tar.xz statics-extra-x86_64.tar.xz; do \
		[ -f .build/repro/$$name ] || [ -f dist/$$name ] || continue; \
		./scripts/compare-builds.sh .build/repro/$$name dist/$$name; \
	done

sources:
	$(BUILDX) source-artifact --output type=local,dest=dist/sources

source-package: sources
	./scripts/package-sources.sh

# Needs an authenticated gh. The script resets the update branch to HEAD, so
# HEAD must be GitHub's main. It rewrites sources.lock in place to compute the
# pins, so refuse local edits to it and restore it afterwards.
update-sources:
	@token=$$(gh auth token) || exit 1; \
		main=$$(gh api repos/0typos/statics/commits/main --jq .sha) || exit 1; \
		[[ $$(git rev-parse HEAD) == "$$main" ]] || { echo "HEAD is not GitHub's main ($$main)" >&2; exit 1; }; \
		git diff --quiet HEAD -- sources.lock || { echo "sources.lock has local changes" >&2; exit 1; }; \
		rc=0; GH_TOKEN=$$token GH_REPO=0typos/statics \
		UPDATE_BRANCH=automation/update-sources ./scripts/update-sources-pr.sh || rc=$$?; \
		git checkout HEAD -- sources.lock; exit $$rc

clean:
	rm -rf .build dist
