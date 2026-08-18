package com.srisarani.fotozenai.canon.ptp

/**
 * PTP dataset parsers (ISO 15740).
 *
 * Field order and width here are fixed by the standard. There is no padding and no
 * self-describing structure, so the parser must agree with the spec exactly - one wrong
 * width and everything after it is silently wrong.
 */

/**
 * The `DeviceInfo` dataset, returned by `GetDeviceInfo` (0x1001).
 *
 * **This is the most valuable thing in M2.** [operationsSupported] is the authoritative
 * list of what this specific body can do, and it settles every later "is X supported?"
 * question - including which of the unverified Canon opcodes in [CanonEosOperation]
 * actually exist. M7's control surface is derived from [devicePropertiesSupported], not
 * from the plan's Appendix B.
 *
 * Wire layout:
 * ```
 * u16      standardVersion
 * u32      vendorExtensionId
 * u16      vendorExtensionVersion
 * string   vendorExtensionDesc
 * u16      functionalMode
 * u16[]    operationsSupported
 * u16[]    eventsSupported
 * u16[]    devicePropertiesSupported
 * u16[]    captureFormats
 * u16[]    imageFormats
 * string   manufacturer
 * string   model
 * string   deviceVersion
 * string   serialNumber
 * ```
 */
data class PtpDeviceInfo(
    val standardVersion: Int,
    val vendorExtensionId: Long,
    val vendorExtensionVersion: Int,
    val vendorExtensionDesc: String,
    val functionalMode: Int,
    val operationsSupported: IntArray,
    val eventsSupported: IntArray,
    val devicePropertiesSupported: IntArray,
    val captureFormats: IntArray,
    val imageFormats: IntArray,
    val manufacturer: String,
    val model: String,
    val deviceVersion: String,
    val serialNumber: String,
) {
    fun supportsOperation(code: Int): Boolean = operationsSupported.contains(code)
    fun supportsProperty(code: Int): Boolean = devicePropertiesSupported.contains(code)
    fun supportsEvent(code: Int): Boolean = eventsSupported.contains(code)

    /**
     * ⚠️ **Do not use this to decide whether EOS operations will work.**
     *
     * Verified on hardware 2026-08-13: a Canon EOS 200D II reports
     * `vendorExtensionId = 6` (**Microsoft**), not Canon. Canon bodies advertise the MTP
     * extension while still implementing the full EOS 0x91xx vendor operation set. An
     * earlier version of this code warned "EOS operations will not work" on that basis,
     * which was flatly wrong - the handshake succeeded seconds later.
     *
     * Use [supportsEosRemoteMode], or the USB vendor ID (0x04A9), instead.
     */
    val declaresCanonVendorExtension: Boolean
        get() = vendorExtensionId.toInt() == PtpVendorExtension.CANON

    /**
     * The reliable test: does the body actually implement the EOS operation set?
     *
     * Capability is proven by the opcodes the camera reports, never by the vendor
     * extension field.
     */
    val isCanonEos: Boolean
        get() = supportsOperation(CanonEosOperation.SET_REMOTE_MODE) &&
            supportsOperation(CanonEosOperation.GET_EVENT)

    /** True when the body exposes the EOS remote-mode opcodes M3 depends on. */
    val supportsEosRemoteMode: Boolean
        get() = supportsOperation(CanonEosOperation.SET_REMOTE_MODE) &&
            supportsOperation(CanonEosOperation.SET_EVENT_MODE) &&
            supportsOperation(CanonEosOperation.GET_EVENT)

    /** True when the body can produce JPEG - the only format we shoot (plan section 2). */
    val supportsJpegCapture: Boolean
        get() = captureFormats.contains(PtpObjectFormat.EXIF_JPEG) ||
            imageFormats.contains(PtpObjectFormat.EXIF_JPEG)

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is PtpDeviceInfo) return false
        return standardVersion == other.standardVersion &&
            vendorExtensionId == other.vendorExtensionId &&
            model == other.model &&
            serialNumber == other.serialNumber &&
            operationsSupported.contentEquals(other.operationsSupported)
    }

    override fun hashCode(): Int {
        var result = standardVersion
        result = 31 * result + vendorExtensionId.hashCode()
        result = 31 * result + model.hashCode()
        result = 31 * result + operationsSupported.contentHashCode()
        return result
    }

    override fun toString(): String =
        "PtpDeviceInfo($manufacturer $model fw=$deviceVersion serial=$serialNumber, " +
            "vendor=${PtpVendorExtension.name(vendorExtensionId)}, " +
            "${operationsSupported.size} ops, ${devicePropertiesSupported.size} props, " +
            "${eventsSupported.size} events)"

    companion object {
        fun parse(payload: ByteArray): PtpDeviceInfo {
            val r = PtpReader(payload)
            return PtpDeviceInfo(
                standardVersion = r.u16(),
                vendorExtensionId = r.u32(),
                vendorExtensionVersion = r.u16(),
                vendorExtensionDesc = r.string(),
                functionalMode = r.u16(),
                operationsSupported = r.u16Array(),
                eventsSupported = r.u16Array(),
                devicePropertiesSupported = r.u16Array(),
                captureFormats = r.u16Array(),
                imageFormats = r.u16Array(),
                manufacturer = r.string(),
                model = r.string(),
                deviceVersion = r.string(),
                serialNumber = r.string(),
            )
        }
    }
}

/**
 * The `ObjectInfo` dataset, returned by `GetObjectInfo` (0x1008).
 *
 * M4 uses [compressedSize] to size the download and to verify it afterwards - a downloaded
 * byte count that disagrees with this is P-08, silent truncation.
 */
data class PtpObjectInfo(
    val storageId: Long,
    val objectFormat: Int,
    val protectionStatus: Int,
    val compressedSize: Long,
    val thumbFormat: Int,
    val thumbCompressedSize: Long,
    val thumbPixWidth: Long,
    val thumbPixHeight: Long,
    val imagePixWidth: Long,
    val imagePixHeight: Long,
    val imageBitDepth: Long,
    val parentObject: Long,
    val associationType: Int,
    val associationDesc: Long,
    val sequenceNumber: Long,
    val filename: String,
    val captureDate: String,
    val modificationDate: String,
    val keywords: String,
) {
    val isJpeg: Boolean get() = objectFormat == PtpObjectFormat.EXIF_JPEG
    val isFolder: Boolean get() = objectFormat == PtpObjectFormat.ASSOCIATION
    val megapixels: Double get() = (imagePixWidth * imagePixHeight) / 1_000_000.0

    override fun toString(): String =
        "PtpObjectInfo($filename, ${PtpObjectFormat.name(objectFormat)}, " +
            "${imagePixWidth}x$imagePixHeight (%.1fMP), %,d bytes)".format(megapixels, compressedSize)

    companion object {
        fun parse(payload: ByteArray): PtpObjectInfo {
            val r = PtpReader(payload)
            return PtpObjectInfo(
                storageId = r.u32(),
                objectFormat = r.u16(),
                protectionStatus = r.u16(),
                compressedSize = r.u32(),
                thumbFormat = r.u16(),
                thumbCompressedSize = r.u32(),
                thumbPixWidth = r.u32(),
                thumbPixHeight = r.u32(),
                imagePixWidth = r.u32(),
                imagePixHeight = r.u32(),
                imageBitDepth = r.u32(),
                parentObject = r.u32(),
                associationType = r.u16(),
                associationDesc = r.u32(),
                sequenceNumber = r.u32(),
                filename = r.string(),
                captureDate = r.string(),
                modificationDate = r.string(),
                keywords = r.string(),
            )
        }
    }
}

/** The `StorageInfo` dataset (0x1005). M6/M7 surface free space and card state from this. */
data class PtpStorageInfo(
    val storageType: Int,
    val filesystemType: Int,
    val accessCapability: Int,
    val maxCapacityBytes: Long,
    val freeSpaceBytes: Long,
    val freeSpaceInImages: Long,
    val storageDescription: String,
    val volumeLabel: String,
) {
    val isReadOnly: Boolean get() = accessCapability != 0

    companion object {
        fun parse(payload: ByteArray): PtpStorageInfo {
            val r = PtpReader(payload)
            return PtpStorageInfo(
                storageType = r.u16(),
                filesystemType = r.u16(),
                accessCapability = r.u16(),
                maxCapacityBytes = r.u64(),
                freeSpaceBytes = r.u64(),
                freeSpaceInImages = r.u32(),
                storageDescription = r.string(),
                volumeLabel = r.string(),
            )
        }
    }
}
