# syntax=docker/dockerfile:1.25.0@sha256:0adf442eae370b6087e08edc7c50b552d80ddf261576f4ebd6421006b2461f12

FROM docker.io/library/debian:bookworm-slim@sha256:734a72b3d6142a71993b4bc580ca01d8ca687f77a2c422d96a961d3376b179bc AS base

# Only the Zig, Go, and Python records reach the toolchain stage, so
# repinning any other upstream source leaves the toolchain layers cached.
# Each toolchain gets its own file, so repinning Go keeps Zig's layer.
FROM base AS toolchain-pin
COPY sources.lock /tmp/sources.lock
RUN grep '^zig-' /tmp/sources.lock >/zig.lock \
    && grep '^go-' /tmp/sources.lock >/go.lock \
    && grep '^python|' /tmp/sources.lock >/python.lock

FROM base AS toolchain

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive
# Install from the snapshot.debian.org date the base image was built from,
# which it records beside each archive URI. The package set is then fixed by
# the base digest alone: a cached layer and a fresh rebuild get identical
# packages, and bumping the digest moves the snapshot with it. Snapshot
# Release files are past their Valid-Until by design.
RUN sed -i -E \
        -e 's|^# (http://snapshot\.debian\.org/archive/[a-z-]+/[0-9]{8}T[0-9]{6}Z)$|URIs: \1|' \
        -e '/^URIs: http:\/\/deb\.debian\.org\//d' \
        /etc/apt/sources.list.d/debian.sources \
    && [ "$(grep -c '^URIs: http://snapshot\.debian\.org/' /etc/apt/sources.list.d/debian.sources)" -eq 2 ] \
    && ! grep -q 'deb\.debian\.org' /etc/apt/sources.list.d/debian.sources \
    || { echo "base image no longer records exactly one snapshot.debian.org URI per archive; review the apt pin" >&2; exit 1; }; \
    echo 'Acquire::Check-Valid-Until "false";' >/etc/apt/apt.conf.d/99snapshot
# Acquire::Retries rides out transient mirror failures. It changes how a
# package is fetched, never which package, so the build stays reproducible.
RUN apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        bash \
        autoconf \
        automake \
        build-essential \
        ca-certificates \
        cmake \
        curl \
        file \
        flex \
        bison \
        jq \
        libtool \
        ninja-build \
        patch \
        perl \
        pkg-config \
        python3 \
        python3-pip \
        xz-utils \
        bzip2 \
    && rm -rf /var/lib/apt/lists/*

# Bookworm's meson 1.0 cannot identify Zig's linker banner ("zig ld") and
# aborts cross setup; meson 1.12 recognizes it natively (ld.zigcc). Installed
# from PyPI pinned by wheel hash, dependency-free.
RUN printf 'meson==1.12.0 --hash=sha256:71f133147fa0fcfe8f4df49fa1045771064947834538409e5d97b3613aac8b4e\n' > /tmp/meson.req \
    && pip3 install --break-system-packages --no-deps --require-hashes -r /tmp/meson.req \
    && rm /tmp/meson.req \
    && meson --version

WORKDIR /workspace
COPY --from=toolchain-pin /zig.lock /tmp/zig.lock
COPY scripts/fetch.sh ./scripts/fetch.sh
RUN chmod +x ./scripts/fetch.sh \
    && case "$TARGETARCH" in \
        amd64) zig_source=zig-x86_64 ;; \
        arm64) zig_source=zig-aarch64 ;; \
        *) echo "unsupported builder architecture: $TARGETARCH" >&2; exit 1 ;; \
       esac \
    && SOURCES_LOCK=/tmp/zig.lock ./scripts/fetch.sh "$zig_source" /tmp/zig.tar.xz \
    && mkdir -p /opt/zig \
    && tar -xJf /tmp/zig.tar.xz -C /opt/zig --strip-components=1 \
    && rm /tmp/zig.tar.xz
# The upstream go.dev release, not Debian's: the same Go on every builder,
# repinned like Zig. GOTOOLCHAIN=local stops a go.mod from fetching another.
COPY --from=toolchain-pin /go.lock /tmp/go.lock
RUN case "$TARGETARCH" in \
        amd64) go_source=go-x86_64 ;; \
        arm64) go_source=go-aarch64 ;; \
        *) echo "unsupported builder architecture: $TARGETARCH" >&2; exit 1 ;; \
       esac \
    && SOURCES_LOCK=/tmp/go.lock ./scripts/fetch.sh "$go_source" /tmp/go.tar.gz \
    && tar -xzf /tmp/go.tar.gz -C /opt \
    && rm /tmp/go.tar.gz
ENV PATH=/opt/go/bin:/opt/zig:${PATH} \
    GOTOOLCHAIN=local
# CPython cannot be cross-compiled without an interpreter of the same X.Y to
# freeze modules and write sysconfig data, and Debian's is older. Build one
# natively from the pinned source, with its dependency-free modules built in:
# scripts/builders/python.sh uses it and it is never shipped. It is part of
# the toolchain, keyed on the python pin alone, so the published image
# carries it and it is compiled once per pin rather than in every build. Kept:
# the interpreter, the build tree's layout, and the Lib it runs from, which it
# finds through the relative source path it was configured with.
COPY --from=toolchain-pin /python.lock /tmp/python.lock
RUN SOURCES_LOCK=/tmp/python.lock ./scripts/fetch.sh python /tmp/python.tar.xz \
    && mkdir -p /opt/build-python /opt/build-python-src \
    && tar -xJf /tmp/python.tar.xz -C /opt/build-python-src --strip-components=1 \
    && rm /tmp/python.tar.xz \
    && cd /opt/build-python \
    && ../build-python-src/configure --without-ensurepip --disable-test-modules \
        --with-pkg-config=no MODULE_BUILDTYPE=static >/dev/null \
    && make -s -j"$(nproc)" python \
    && find . \( -name '*.o' -o -name '*.a' \) -delete \
    && rm -f Programs/_freeze_module _bootstrap_python \
    && find /opt/build-python-src -mindepth 1 -maxdepth 1 ! -name Lib -exec rm -rf {} + \
    && rm -rf /opt/build-python-src/Lib/test \
    && ./python -c 'import sys, struct, compileall; print(sys.version)'

FROM toolchain AS sources
COPY sources.lock ./
COPY scripts/fetch.sh scripts/fetch-sources.sh ./scripts/
RUN --mount=type=cache,id=statics-source-archives,target=/var/cache/statics \
    chmod +x scripts/fetch.sh scripts/fetch-sources.sh \
    && scripts/fetch-sources.sh \
         --archives /var/cache/statics \
         --extract /src \
         --bundle /archives

# The only network access Go gets: the modules the Go tools import, checked
# against each upstream go.sum, for the offline build and the source bundle.
# Its own stage, so the manifests that choose the modules do not invalidate
# the deps stage below.
FROM sources AS go-modules
COPY architectures.tsv components.tsv ./
COPY patches/go-mains/ patches/go-mains/
COPY scripts/fetch-go-modules.sh ./scripts/
RUN chmod +x scripts/fetch-go-modules.sh \
    && scripts/fetch-go-modules.sh /src /go-bundle

# The shared libraries (OpenSSL above all) are about half of every compile and
# change only with their pins or the build scripts, so they get their own
# stage. CI publishes it per arch from main as a layer cache, like the
# toolchain; a miss only costs time. No JOBS argument: it would key the cache
# on the machine size.
FROM sources AS deps
ARG ARCH=x86_64
ARG COMPONENT_TIMEOUT
COPY architectures.tsv ./
COPY scripts/build.sh scripts/run-builder.sh scripts/
COPY scripts/lib/ scripts/lib/
COPY scripts/builders/dependencies.sh scripts/builders/
COPY scripts/toolchain/ scripts/toolchain/
# No network, as for the full build below.
RUN --network=none chmod +x scripts/*.sh scripts/toolchain/* \
    && STATICS_ONLY_DEPS=1 STATICS_COMPONENT_TIMEOUT="$COMPONENT_TIMEOUT" \
        scripts/build.sh "$ARCH" "/deps/$ARCH/out" \
    && mv "/build/$ARCH/prefix" "/deps/$ARCH/prefix" \
    && rm -rf /build

FROM sources AS builder
ARG ARCH=x86_64
# Per-component `make -j` budget. Empty ⇒ build.sh defaults to nproc (correct
# for a plain local build or an isolated hosted runner). On the shared beefy
# host the workflow passes a capped value so concurrent arch builds saturate
# the cores instead of oversubscribing them into scheduler thrash.
ARG JOBS
# Seconds before a component is treated as hung and the build restarts once
# (scripts/run-builder.sh). Empty disables it; CircleCI sets it.
ARG COMPONENT_TIMEOUT
# Only what the build reads. Anything else in the context (CI config, docs,
# verify.sh, dev tooling) must not invalidate every architecture's compile.
COPY --from=go-modules /src/go-modules/ /src/go-modules/
COPY LICENSE architectures.tsv components.tsv ./
COPY configs/ configs/
COPY patches/ patches/
COPY tunpipe/ tunpipe/
COPY scripts/build.sh scripts/run-builder.sh scripts/merge-kconfig.sh \
     scripts/collect-licenses.sh scripts/generate-sbom.py scripts/components.sh \
     scripts/python-stdlib-zip.py scripts/
COPY scripts/lib/ scripts/lib/
COPY scripts/builders/ scripts/builders/
COPY scripts/toolchain/ scripts/toolchain/
COPY --from=deps /deps/ /deps/
# The work tree (a copy of every source plus objects, ~0.9 GB per arch) is
# removed in the same layer: it is never read again, and keeping it made each
# arch's exported layer cache about a gigabyte, enough for the 13 arches to
# evict one another from GitHub's 10 GB cache.
# No network: every input is already in /src, so a build that reaches for one
# (a Go module, a toolchain download, a configure probe) fails here.
RUN --network=none chmod +x scripts/*.sh scripts/toolchain/* \
    && JOBS="$JOBS" STATICS_COMPONENT_TIMEOUT="$COMPONENT_TIMEOUT" \
        STATICS_DEPS_FROM="/deps/$ARCH" scripts/build.sh "$ARCH" "/out/$ARCH" \
    && rm -rf /build

FROM builder AS test
ARG ARCH=x86_64
COPY --chmod=0755 scripts/verify.sh scripts/
# QEMU from bookworm-backports at the same snapshot date: bookworm's 7.2
# cannot run any Go 386 binary ("fatal: morestack on gsignal"), and 8.0 and
# later can. Only this test stage sees it; the build never does.
RUN sed -i 's/^Suites: bookworm bookworm-updates$/& bookworm-backports/' \
        /etc/apt/sources.list.d/debian.sources \
    && grep -q '^Suites: bookworm bookworm-updates bookworm-backports$' \
        /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        -t bookworm-backports qemu-user-static \
    && rm -rf /var/lib/apt/lists/* \
    && scripts/verify.sh "/out/$ARCH" "$ARCH"

FROM scratch AS artifact
COPY --from=builder /out/ /

FROM scratch AS source-artifact
COPY --from=sources /archives/ /
COPY --from=go-modules /go-bundle/ /go-modules/
