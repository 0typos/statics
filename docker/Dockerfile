# syntax=docker/dockerfile:1.25.0@sha256:0adf442eae370b6087e08edc7c50b552d80ddf261576f4ebd6421006b2461f12

FROM docker.io/library/debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171 AS toolchain

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive
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
COPY sources.lock ./
COPY scripts/fetch.sh ./scripts/fetch.sh
RUN chmod +x ./scripts/fetch.sh \
    && case "$TARGETARCH" in \
        amd64) zig_source=zig-x86_64 ;; \
        arm64) zig_source=zig-aarch64 ;; \
        *) echo "unsupported builder architecture: $TARGETARCH" >&2; exit 1 ;; \
       esac \
    && ./scripts/fetch.sh "$zig_source" /tmp/zig.tar.xz \
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
COPY . .
RUN chmod +x scripts/*.sh scripts/toolchain/* \
    && JOBS="$JOBS" scripts/build.sh "$ARCH" "/out/$ARCH"

FROM builder AS test
ARG ARCH=x86_64
RUN apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        qemu-user-static \
    && rm -rf /var/lib/apt/lists/* \
    && scripts/verify.sh "/out/$ARCH" "$ARCH"

FROM scratch AS artifact
COPY --from=builder /out/ /

FROM scratch AS source-artifact
COPY --from=sources /archives/ /
