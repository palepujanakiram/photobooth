package com.srisarani.fotozenai.canoncapture

/**
 * Which Canon implementation drives the DSLR.
 *
 * The app now carries two, and **they must never run at the same time**. PTP is a strictly
 * serialised protocol over one USB endpoint; two clients on it corrupt each other's
 * transactions and present as protocol bugs. We already watched that happen when the
 * standalone POC app auto-launched on camera attach and claimed the interface before the
 * booth could — the booth read the tail of the POC's transfer as a container header
 * (*"Container truncated: declared 1140862976"*) and needed a camera power cycle to clear.
 *
 * **To switch, change [current] and rebuild.** A Kotlin constant rather than a dart-define
 * because [com.srisarani.fotozenai.MainActivity] has to make this decision in `onCreate`,
 * before any Dart has run — `CanonSidecarService` starts there.
 */
enum class CanonCameraStack {

    /**
     * Pure-Kotlin PTP over `UsbDeviceConnection`, with the native capture screen.
     *
     * No bundled binaries, no glibc, no NDK. Goes through `UsbManager`, so it does not
     * depend on SELinux allowing an app direct `/dev/bus/usb` access — on this TV box those
     * reads are logged as `avc: denied ... permissive=1`, which an enforcing device would
     * refuse outright.
     */
    PTP,

    /**
     * Canon EDSDK running under bundled glibc as a forked sidecar on `127.0.0.1:8791`,
     * reached over HTTP by `LocalCameraService` exactly like the Raspberry Pi.
     *
     * Its advantage is that the whole existing Flutter capture flow — live preview poller,
     * sidecar helpers, HDMI pose — works unchanged, because only the *address* of the
     * sidecar moves. Its cost is per-ABI EDSDK and glibc payloads in the APK and a
     * dependency on direct usbfs access.
     */
    EDSDK_SIDECAR,
    ;

    companion object {
        /** The stack this build uses. Change this line to switch. */
        val current: CanonCameraStack = PTP

        val usesPtp: Boolean get() = current == PTP
        val usesEdsdkSidecar: Boolean get() = current == EDSDK_SIDECAR
    }
}
