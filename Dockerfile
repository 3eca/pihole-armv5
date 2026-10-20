# syntax=docker/dockerfile:1
ARG BASE_IMAGE=arm32v5/debian:12.10
FROM ${BASE_IMAGE} AS ftl-build
ARG TARGETARCH
ARG TARGETVARIANT
RUN test "${TARGETARCH}/${TARGETVARIANT}" = arm/v5
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake git curl ca-certificates bzip2 m4 pkg-config \
    patch libgmp-dev libidn2-dev libunistring-dev libreadline-dev xxd file \
    && rm -rf /var/lib/apt/lists/*
ENV CFLAGS="-O2 -march=armv5te -mfloat-abi=soft"
WORKDIR /build
ARG BUILD_JOBS=4
COPY patches/event_atomic.h tests/test_event_atomic.c /build/
RUN gcc $CFLAGS -pthread -o /build/test-events /build/test_event_atomic.c \
    && QEMU_CPU=arm926 timeout 60 /build/test-events
COPY scripts/build-deps.sh /build/build-deps.sh
RUN bash /build/build-deps.sh
ARG FTL_VERSION=v6.8
ARG FTL_COMMIT=29c8b13f4bba0c4f4f47598e45a65cbf1cedac88
COPY scripts/build-ftl.sh patches/armv5-events.patch /build/
RUN bash /build/build-ftl.sh

FROM scratch AS binary
COPY --from=ftl-build /out/ /
COPY patches/armv5-events.patch patches/event_atomic.h /

FROM ${BASE_IMAGE} AS runtime
ENV DEBIAN_FRONTEND=noninteractive
RUN printf '#!/bin/sh\nexit 101\n' > /usr/sbin/policy-rc.d && chmod +x /usr/sbin/policy-rc.d \
    && apt-get update && apt-get install -y --no-install-recommends \
    bash-completion binutils ca-certificates cron curl dialog dnsutils dns-root-data git \
    iproute2 iputils-ping jq libcap2-bin logrotate lshw procps psmisc sudo unzip \
    openssh-server vim libgmp10 libidn2-0 libunistring2 libreadline8 tini \
    && rm -rf /var/lib/apt/lists/* /etc/ssh/ssh_host_* /usr/sbin/policy-rc.d
ARG CORE_VERSION=v6.5
ARG WEB_VERSION=v6.6.1
ARG CORE_COMMIT=f503a65d3a07cb71fd931389f1d3babf718249aa
ARG WEB_COMMIT=fb699c4e3fd6965d1c9a5253250d8a9b3c6f7a0e
RUN git clone --depth 1 --branch "${CORE_VERSION}" https://github.com/pi-hole/pi-hole.git /etc/.pihole \
    && git clone --depth 1 --branch "${WEB_VERSION}" https://github.com/pi-hole/web.git /var/www/html/admin \
    && test "$(git -C /etc/.pihole rev-parse HEAD)" = "$CORE_COMMIT" \
    && test "$(git -C /var/www/html/admin rev-parse HEAD)" = "$WEB_COMMIT"
COPY --from=ftl-build /out/pihole-FTL /usr/bin/pihole-FTL
COPY scripts/make_ssh_user.sh /data/make_ssh_user.sh
COPY scripts/install.sh scripts/start.sh /data/
RUN bash /data/install.sh && bash /data/make_ssh_user.sh
COPY --from=ftl-build /out/FTL_COMMIT /out/SHA256SUMS /out/LICENSE /usr/share/doc/pihole-ftl-armv5/
COPY patches/armv5-events.patch patches/event_atomic.h /usr/share/doc/pihole-ftl-armv5/
EXPOSE 22/tcp 53/tcp 53/udp 80/tcp 443/tcp 67/udp 123/udp
ENTRYPOINT ["/usr/bin/tini", "--", "/bin/bash", "/data/start.sh"]
