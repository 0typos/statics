# syntax=docker/dockerfile:1.25.0@sha256:0adf442eae370b6087e08edc7c50b552d80ddf261576f4ebd6421006b2461f12

FROM docker.io/library/debian:bookworm-slim@sha256:7b140f374b289a7c2befc338f42ebe6441b7ea838a042bbd5acbfca6ec875818 AS toolchain

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
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
        patch \
        perl \
        pkg-config \
        python3 \
        xz-utils \
        bzip2 \
    && rm -rf /var/lib/apt/lists/*

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
COPY . .
RUN chmod +x scripts/*.sh scripts/toolchain/* \
    && scripts/build.sh "$ARCH" "/out/$ARCH"

FROM builder AS test
ARG ARCH=x86_64
RUN apt-get update && apt-get install -y --no-install-recommends qemu-user-static \
    && rm -rf /var/lib/apt/lists/* \
    && scripts/verify.sh "/out/$ARCH" "$ARCH"

FROM scratch AS artifact
COPY --from=builder /out/ /

FROM scratch AS source-artifact
COPY --from=sources /archives/ /
