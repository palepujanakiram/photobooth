#!/usr/bin/env bash
# Builds canon-sidecar inside Docker (Ubuntu 20.04, glibc 2.31) and installs
# the bundle into the Android APK.
#
# Usage:
#   ./build.sh                  # ARM32 + ARM64 (default)
#   SIDECAR_ARCHES=arm32 ./build.sh
#   SIDECAR_ARCHES=arm64 ./build.sh
#   EDSDK_PATH=/path/to/EDSDK/Linux ./build.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

EDSDK_PATH="${EDSDK_PATH:-/Users/janakiram/Downloads/EDSDK132021CD(13.20.21)/Linux}"
ANDROID_JNILIBS_ROOT="$REPO_ROOT/photobooth/android/app/src/main/jniLibs"
ANDROID_ASSETS_ROOT="$REPO_ROOT/photobooth/android/app/src/main/assets/canon_sidecar"
# Space-separated: arm32 and/or arm64
SIDECAR_ARCHES="${SIDECAR_ARCHES:-arm32 arm64}"

echo "==> EDSDK path : $EDSDK_PATH"
echo "==> Arches     : $SIDECAR_ARCHES"

# ── Stage EDSDK into build context ────────────────────────────────────────────
EDSDK_STAGE="$SCRIPT_DIR/EDSDK"
rm -rf "$EDSDK_STAGE"
mkdir -p "$EDSDK_STAGE/Header" \
         "$EDSDK_STAGE/Library/ARM64" \
         "$EDSDK_STAGE/Library/ARM32"
cp "$EDSDK_PATH/EDSDK/Header/EDSDK.h"       "$EDSDK_STAGE/Header/"
cp "$EDSDK_PATH/EDSDK/Header/EDSDKErrors.h"  "$EDSDK_STAGE/Header/"
cp "$EDSDK_PATH/EDSDK/Header/EDSDKTypes.h"   "$EDSDK_STAGE/Header/"
cp "$EDSDK_PATH/EDSDK/Library/ARM64/libEDSDK.so" "$EDSDK_STAGE/Library/ARM64/"
cp "$EDSDK_PATH/EDSDK/Library/ARM32/libEDSDK.so" "$EDSDK_STAGE/Library/ARM32/"

install_bundle() {
    local android_abi="$1"
    local docker_platform="$2"
    local image_tag="$3"
    local interpreter_src="$4"
    local interpreter_dst="$5"
    local sidecar_cross="${6:-none}"
    local bundle_dir="$SCRIPT_DIR/bundle/$android_abi"
    local jnilibs="$ANDROID_JNILIBS_ROOT/$android_abi"
    local assets="$ANDROID_ASSETS_ROOT/$android_abi"

    echo ""
    echo "==> Building $android_abi ($docker_platform, cross=$sidecar_cross)..."
    docker build \
        --platform "$docker_platform" \
        --build-arg "SIDECAR_DOCKER_PLATFORM=$docker_platform" \
        --build-arg "SIDECAR_CROSS=$sidecar_cross" \
        --tag "$image_tag" \
        "$SCRIPT_DIR"

    echo "==> Extracting $android_abi bundle..."
    rm -rf "$bundle_dir"
    mkdir -p "$bundle_dir"
    local container_id
    container_id="$(docker create --platform "$docker_platform" "$image_tag")"
    docker cp "$container_id:/bundle/." "$bundle_dir/"
    docker rm "$container_id" > /dev/null

    echo "==> $android_abi bundle:"
    ls -lh "$bundle_dir"

    local required=(
        canon-sidecar
        "$interpreter_src"
        libusb_open_hook.so
        libEDSDK.so
        libusb-1.0.so.0
        libudev.so.1
        libstdc++.so.6
        libgcc_s.so.1
        libc.so.6
        libm.so.6
        libpthread.so.0
        libdl.so.2
    )
    local f
    for f in "${required[@]}"; do
        if [[ ! -f "$bundle_dir/$f" ]]; then
            echo "ERROR: missing $f in $android_abi bundle" >&2
            exit 1
        fi
    done

    echo "==> Installing $android_abi JNI executables..."
    mkdir -p "$jnilibs"
    chmod u+w "$jnilibs"/* 2>/dev/null || true
    cp "$bundle_dir/$interpreter_src" "$jnilibs/$interpreter_dst"
    cp "$bundle_dir/canon-sidecar"     "$jnilibs/libcanon_sidecar.so"
    cp "$bundle_dir/libEDSDK.so"       "$jnilibs/libEDSDK.so"
    chmod +x "$jnilibs/$interpreter_dst" "$jnilibs/libcanon_sidecar.so"

    echo "==> Installing $android_abi glibc deps into assets..."
    rm -rf "$assets"
    mkdir -p "$assets"
    for f in "$bundle_dir"/*; do
        local name
        name="$(basename "$f")"
        case "$name" in
            canon-sidecar|"$interpreter_src"|libEDSDK.so) continue ;;
        esac
        cp "$f" "$assets/$name"
    done
}

# Legacy layout had glibc files directly in assets/canon_sidecar/.
# Move them under arm64-v8a so 64-bit boxes keep working without a rebuild.
migrate_legacy_arm64_assets() {
    mkdir -p "$ANDROID_ASSETS_ROOT/arm64-v8a"
    local moved=0
    local f
    for f in "$ANDROID_ASSETS_ROOT"/*.so*; do
        [[ -f "$f" ]] || continue
        mv "$f" "$ANDROID_ASSETS_ROOT/arm64-v8a/"
        moved=1
    done
    if [[ "$moved" -eq 1 ]]; then
        echo "==> Migrated legacy ARM64 glibc assets to arm64-v8a/"
    fi
}

migrate_legacy_arm64_assets

for arch in $SIDECAR_ARCHES; do
    case "$arch" in
        arm64)
            install_bundle \
                "arm64-v8a" \
                "linux/arm64" \
                "canon-sidecar-build:arm64" \
                "ld-linux-aarch64.so.1" \
                "libld_linux_aarch64.so"
            ;;
        arm32)
            install_bundle \
                "armeabi-v7a" \
                "linux/arm64" \
                "canon-sidecar-build:arm32" \
                "ld-linux-armhf.so.3" \
                "libld_linux_armhf.so" \
                "armhf"
            ;;
        *)
            echo "ERROR: unknown SIDECAR_ARCHES entry: $arch (use arm32 and/or arm64)" >&2
            exit 1
            ;;
    esac
done

rm -rf "$EDSDK_STAGE"

echo ""
echo "Done. Installed:"
echo "  jniLibs : $ANDROID_JNILIBS_ROOT"
echo "  assets  : $ANDROID_ASSETS_ROOT"
echo ""
echo "Next step — build the APK:"
echo "  cd $REPO_ROOT/photobooth"
echo '  ./scripts/flutter_with_version.sh build apk --release'
