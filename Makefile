SHELL := /usr/bin/env bash

ARCH ?= x86_64
DOCKER ?= docker
DOCKERFILE := docker/Dockerfile
ARCHES := $(shell awk -F '|' '$$0 !~ /^#/ { print $$1 }' architectures.tsv)

.DEFAULT_GOAL := help

.PHONY: help list build all smoke smoke-all verify package sources source-package clean

help:
	@echo "Static Linux troubleshooting binaries"
	@echo
	@echo "  make list                    List supported architectures"
	@echo "  make build ARCH=x86_64       Build one architecture into dist/"
	@echo "  make smoke ARCH=x86_64       Build and QEMU-smoke-test in Docker"
	@echo "  make all                     Build every architecture"
	@echo "  make smoke-all               Smoke-test every architecture"
	@echo "  make verify ARCH=x86_64      Verify an existing local build"
	@echo "  make package ARCH=x86_64     Create a deterministic tar.xz"
	@echo "  make sources                 Export verified upstream archives"
	@echo "  make source-package         Package corresponding source archives"
	@echo "  make clean                   Remove generated output"

list:
	@awk -F '|' '$$0 !~ /^#/ { printf "%-18s %s\n", $$1, $$5 }' architectures.tsv

build:
	$(DOCKER) buildx build \
		--file $(DOCKERFILE) \
		--target artifact \
		--build-arg ARCH=$(ARCH) \
		--output type=local,dest=dist \
		.

all:
	@set -e; for arch in $(ARCHES); do $(MAKE) build ARCH="$$arch"; done

smoke:
	$(DOCKER) buildx build \
		--file $(DOCKERFILE) \
		--target test \
		--build-arg ARCH=$(ARCH) \
		--load \
		--tag statics-test:$(ARCH) \
		.

smoke-all:
	@set -e; for arch in $(ARCHES); do $(MAKE) smoke ARCH="$$arch"; done

verify:
	./scripts/verify.sh "dist/$(ARCH)" "$(ARCH)"

package: build
	./scripts/package.sh "$(ARCH)"

sources:
	$(DOCKER) buildx build \
		--file $(DOCKERFILE) \
		--target source-artifact \
		--output type=local,dest=dist/sources \
		.

source-package: sources
	./scripts/package-sources.sh

clean:
	rm -rf .build dist
