package com.srisarani.fotozenai.canon.usb

/**
 * Pure (Android-free) USB descriptor model.
 *
 * The Android `UsbEndpoint` / `UsbInterface` classes cannot be constructed in a plain JVM
 * unit test. Mirroring the handful of fields we actually care about lets the endpoint
 * resolution logic - which is where the real bugs live - be tested as a pure function,
 * with a thin adapter converting the Android objects at the edge.
 *
 * This is the same seam O-03 calls for at a larger scale in M11.
 */

object UsbDirection {
    const val OUT = 0
    const val IN = 0x80
}

object UsbTransferType {
    const val CONTROL = 0
    const val ISOCHRONOUS = 1
    const val BULK = 2
    const val INTERRUPT = 3
}

object UsbClass {
    /** USB Still Image Capture class. Interface class 6 / subclass 1 / protocol 1 = PTP. */
    const val STILL_IMAGE = 6
    const val STILL_IMAGE_SUBCLASS = 1
    const val STILL_IMAGE_PROTOCOL_PTP = 1
}

/** Canon's USB vendor ID. Note: `device_filter.xml` needs this in DECIMAL (1193). */
const val CANON_VENDOR_ID = 0x04A9

data class EndpointDescriptor(
    val address: Int,
    val direction: Int,
    val type: Int,
    val maxPacketSize: Int,
) {
    val isIn: Boolean get() = direction == UsbDirection.IN
    val isOut: Boolean get() = direction == UsbDirection.OUT
    val isBulk: Boolean get() = type == UsbTransferType.BULK
    val isInterrupt: Boolean get() = type == UsbTransferType.INTERRUPT
}

data class InterfaceDescriptor(
    val id: Int,
    val alternateSetting: Int,
    val interfaceClass: Int,
    val interfaceSubclass: Int,
    val interfaceProtocol: Int,
    val endpoints: List<EndpointDescriptor>,
) {
    /**
     * Matches the PTP still-image interface.
     *
     * Deliberately does NOT require subclass/protocol to match exactly - a handful of
     * bodies report the right class with odd subclass values, and the endpoint layout is
     * what actually matters. Class 6 plus a usable endpoint triple is the real test.
     */
    val isStillImage: Boolean get() = interfaceClass == UsbClass.STILL_IMAGE
}

/**
 * The three endpoints every PTP session needs.
 *
 * bulkOut  - commands go out here
 * bulkIn   - data and response containers come back here
 * interruptIn - asynchronous events (M3 uses this; M1 only has to find it)
 */
data class ResolvedEndpoints(
    val bulkOut: EndpointDescriptor,
    val bulkIn: EndpointDescriptor,
    val interruptIn: EndpointDescriptor?,
) {
    override fun toString(): String = buildString {
        append("bulkOut=0x%02X".format(bulkOut.address))
        append(" bulkIn=0x%02X(max=%d)".format(bulkIn.address, bulkIn.maxPacketSize))
        append(" interruptIn=")
        append(interruptIn?.let { "0x%02X".format(it.address) } ?: "none")
    }
}

/** Typed failures. Every one carries enough detail to diagnose without a debugger attached. */
sealed class UsbError(message: String, cause: Throwable? = null) : Exception(message, cause) {

    class NoStillImageInterface(val interfacesSeen: List<InterfaceDescriptor>) :
        UsbError(
            "No USB still-image (class ${UsbClass.STILL_IMAGE}) interface found. " +
                "Interfaces seen: " + interfacesSeen.joinToString {
                    "id=${it.id} class=${it.interfaceClass}/${it.interfaceSubclass}/${it.interfaceProtocol}"
                },
        )

    class MissingEndpoints(val found: List<EndpointDescriptor>, val detail: String) :
        UsbError(
            "Still-image interface lacks the required endpoints ($detail). Found: " +
                found.joinToString {
                    "addr=0x%02X dir=%s type=%d max=%d".format(
                        it.address,
                        if (it.isIn) "IN" else "OUT",
                        it.type,
                        it.maxPacketSize,
                    )
                },
        )

    class PermissionDenied(deviceName: String) :
        UsbError("USB permission denied for $deviceName")

    class OpenFailed(deviceName: String, cause: Throwable? = null) :
        UsbError("Could not open $deviceName", cause)

    class ClaimFailed(interfaceId: Int) :
        UsbError(
            "claimInterface($interfaceId) failed. Another process may hold the device - " +
                "MTP handler, gallery importer or photo backup app (U-02).",
        )

    class Timeout(operation: String, timeoutMs: Int) :
        UsbError("$operation timed out after ${timeoutMs}ms")

    class TransferFailed(operation: String, returned: Int) :
        UsbError("$operation failed, bulkTransfer returned $returned")

    class Detached : UsbError("Device detached")

    class Closed : UsbError("Transport is closed")
}
