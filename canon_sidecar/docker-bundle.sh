#!/bin/sh
# Assemble the glibc + EDSDK runtime bundle inside the Docker builder.
set -eu

mkdir -p /bundle
cp canon-sidecar /bundle/
cp libusb_open_hook.so /bundle/

if [ "${SIDECAR_CROSS:-none}" = "armhf" ] || [ -d /lib/arm-linux-gnueabihf ]; then
    GLIBC=/lib/arm-linux-gnueabihf
    USRLIB=/usr/lib/arm-linux-gnueabihf
    LD=ld-linux-armhf.so.3
    EDSDK=EDSDK/Library/ARM32/libEDSDK.so
elif [ -d /lib/aarch64-linux-gnu ]; then
    GLIBC=/lib/aarch64-linux-gnu
    USRLIB=/usr/lib/aarch64-linux-gnu
    LD=ld-linux-aarch64.so.1
    EDSDK=EDSDK/Library/ARM64/libEDSDK.so
else
    echo "Unknown glibc layout:" >&2
    ls -l /lib
    exit 1
fi

copy_lib() {
    n="$1"
    src=""
    if [ -e "$GLIBC/$n" ]; then
        src="$GLIBC/$n"
    elif [ -e "$USRLIB/$n" ]; then
        src="$USRLIB/$n"
    else
        echo "missing $n in $GLIBC or $USRLIB" >&2
        exit 1
    fi
    # Follow soname symlinks so the bundle has a real ELF, not a dangling link.
    cp -L "$src" "/bundle/$n"
}

cp "$EDSDK" /bundle/libEDSDK.so
copy_lib "$LD"
copy_lib libc.so.6
copy_lib libm.so.6
copy_lib libpthread.so.0
copy_lib libdl.so.2
copy_lib libusb-1.0.so.0
copy_lib libudev.so.1
copy_lib libstdc++.so.6
copy_lib libgcc_s.so.1
if [ -e "$GLIBC/libatomic.so.1" ] || [ -e "$USRLIB/libatomic.so.1" ]; then
    copy_lib libatomic.so.1
fi

patchelf --set-rpath '$ORIGIN' /bundle/canon-sidecar
patchelf --set-rpath '$ORIGIN' /bundle/libusb_open_hook.so
chmod +x /bundle/canon-sidecar /bundle/"$LD"
echo "Bundle contents:"
ls -lh /bundle/
