# syntax=docker/dockerfile:1.25.0@sha256:0adf442eae370b6087e08edc7c50b552d80ddf261576f4ebd6421006b2461f12

FROM docker.io/library/debian:bookworm-slim@sha256:abd67ffcfa541b485a3dff59865ab629aa048a6c613e639d36e7456b0b229241 AS base

# Only the Zig records reach the toolchain stage, so repinning any other
# upstream source leaves the toolchain layers cached. (GitHub's per-layer
# cache benefits; CircleCI's single stage-cache key still hashes the whole
# lock.)
FROM base AS zig-pin
COPY sources.lock /tmp/sources.lock
RUN grep '^zig-' /tmp/sources.lock >/zig.lock

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
COPY --from=zig-pin /zig.lock /tmp/zig.lock
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
ENV PATH=/opt/zig:${PATH}

FROM toolchain AS sources
COPY sources.lock ./
COPY scripts/fetch.sh scripts/fetch-sources.sh ./scripts/
RUN --mount=type=cache,id=statics-source-archives,target=/var/cache/statics \
    chmod +x scripts/fetch.sh scripts/fetch-sources.sh \
    && scripts/fetch-sources.sh \
         --archives /var/cache/statics \
         --extract /src \
         --bundle /archives

FROM sources AS builder
ARG ARCH=x86_64
# Per-component `make -j` budget. Empty ⇒ build.sh defaults to nproc (correct
# for a plain local build or an isolated hosted runner). On the shared beefy
# host the workflow passes a capped value so concurrent arch builds saturate
# the cores instead of oversubscribing them into scheduler thrash.
ARG JOBS
# Only what the build reads. Anything else in the context (CI config, docs,
# verify.sh, dev tooling) must not invalidate every architecture's compile.
COPY LICENSE architectures.tsv components.tsv ./
COPY configs/ configs/
COPY patches/ patches/
COPY scripts/build.sh scripts/run-builder.sh scripts/merge-kconfig.sh \
     scripts/collect-licenses.sh scripts/generate-sbom.py scripts/
COPY scripts/lib/ scripts/lib/
COPY scripts/builders/ scripts/builders/
COPY scripts/toolchain/ scripts/toolchain/
RUN chmod +x scripts/*.sh scripts/toolchain/* \
    && JOBS="$JOBS" scripts/build.sh "$ARCH" "/out/$ARCH"

FROM builder AS test
ARG ARCH=x86_64
COPY --chmod=0755 scripts/verify.sh scripts/
RUN apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        qemu-user-static \
    && rm -rf /var/lib/apt/lists/* \
    && scripts/verify.sh "/out/$ARCH" "$ARCH"

FROM scratch AS artifact
COPY --from=builder /out/ /

FROM scratch AS source-artifact
COPY --from=sources /archives/ /
