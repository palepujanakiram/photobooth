# Ubuntu 20.04 glibc 2.31 — matches Canon's Linux EDSDK targets.
# ARM64: native (or qemu) linux/arm64.
# ARM32: cross-compile armhf from linux/arm64 (avoids broken qemu cmake).
# Run via build.sh; do not invoke docker build directly.
ARG SIDECAR_DOCKER_PLATFORM=linux/arm64
FROM --platform=${SIDECAR_DOCKER_PLATFORM} ubuntu:20.04 AS builder

ARG SIDECAR_CROSS=none
ENV DEBIAN_FRONTEND=noninteractive
ENV SIDECAR_CROSS=${SIDECAR_CROSS}

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        cmake \
        patchelf \
        ca-certificates \
        libusb-1.0-0-dev \
        libusb-1.0-0 \
        libudev1 \
        libatomic1 \
    && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    if [ "$SIDECAR_CROSS" = "armhf" ]; then \
        dpkg --add-architecture armhf; \
        apt-get update; \
        apt-get install -y --no-install-recommends \
            gcc-arm-linux-gnueabihf \
            g++-arm-linux-gnueabihf \
            libc6:armhf \
            libc6-dev:armhf \
            libstdc++6:armhf \
            libstdc++-9-dev:armhf \
            libgcc-s1:armhf \
            libatomic1:armhf \
            libusb-1.0-0:armhf \
            libusb-1.0-0-dev:armhf \
            libudev1:armhf; \
        rm -rf /var/lib/apt/lists/*; \
    fi

WORKDIR /build

COPY src/          ./src/
COPY CMakeLists.txt ./
COPY docker-bundle.sh ./
COPY EDSDK/        ./EDSDK/

RUN set -eux; \
    if [ "$SIDECAR_CROSS" = "armhf" ]; then \
        cmake -DCMAKE_BUILD_TYPE=Release \
            -DCMAKE_SYSTEM_NAME=Linux \
            -DCMAKE_SYSTEM_PROCESSOR=arm \
            -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc \
            -DCMAKE_CXX_COMPILER=arm-linux-gnueabihf-g++; \
    else \
        cmake -DCMAKE_BUILD_TYPE=Release; \
    fi; \
    make -j"$(nproc)"

RUN chmod +x docker-bundle.sh && ./docker-bundle.sh

FROM ubuntu:20.04 AS export
COPY --from=builder /bundle /bundle
