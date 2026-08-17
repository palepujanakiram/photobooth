package com.srisarani.fotozenai.canon.ptp

/**
 * PTP / PTP-over-USB constants.
 *
 * > **The rule (plan section 0): these are a starting point, not the truth.** The standard
 * > PTP codes below are from ISO 15740 and are stable. The Canon EOS vendor codes are
 * > transcribed and MUST be checked against libgphoto2's `ptp.h` before being relied on.
 * > Where `ptp.h` disagrees, `ptp.h` wins. Where the body's own `GetDeviceInfo` disagrees
 * > with `ptp.h`, **the body wins** - that dump is the only authoritative list for this
 * > specific camera, which is why M2 commits it to `docs/device-capabilities/`.
 */

/** Container types. The first field after the length in every PTP packet. */
object PtpContainerType {
    const val COMMAND = 1
    const val DATA = 2
    const val RESPONSE = 3
    const val EVENT = 4

    fun name(type: Int): String = when (type) {
        COMMAND -> "Command"
        DATA -> "Data"
        RESPONSE -> "Response"
        EVENT -> "Event"
        else -> "Unknown($type)"
    }
}

/** Standard PTP operation codes (ISO 15740). These are stable across all PTP devices. */
object PtpOperation {
    const val GET_DEVICE_INFO = 0x1001
    const val OPEN_SESSION = 0x1002
    const val CLOSE_SESSION = 0x1003
    const val GET_STORAGE_IDS = 0x1004
    const val GET_STORAGE_INFO = 0x1005
    const val GET_NUM_OBJECTS = 0x1006
    const val GET_OBJECT_HANDLES = 0x1007
    const val GET_OBJECT_INFO = 0x1008
    const val GET_OBJECT = 0x1009
    const val GET_THUMB = 0x100A
    const val DELETE_OBJECT = 0x100B
    const val INITIATE_CAPTURE = 0x100E
    const val GET_DEVICE_PROP_DESC = 0x1014
    const val GET_DEVICE_PROP_VALUE = 0x1015
    const val SET_DEVICE_PROP_VALUE = 0x1016
    const val GET_PARTIAL_OBJECT = 0x101B

    private val names = mapOf(
        GET_DEVICE_INFO to "GetDeviceInfo",
        OPEN_SESSION to "OpenSession",
        CLOSE_SESSION to "CloseSession",
        GET_STORAGE_IDS to "GetStorageIDs",
        GET_STORAGE_INFO to "GetStorageInfo",
        GET_NUM_OBJECTS to "GetNumObjects",
        GET_OBJECT_HANDLES to "GetObjectHandles",
        GET_OBJECT_INFO to "GetObjectInfo",
        GET_OBJECT to "GetObject",
        GET_THUMB to "GetThumb",
        DELETE_OBJECT to "DeleteObject",
        INITIATE_CAPTURE to "InitiateCapture",
        GET_DEVICE_PROP_DESC to "GetDevicePropDesc",
        GET_DEVICE_PROP_VALUE to "GetDevicePropValue",
        SET_DEVICE_PROP_VALUE to "SetDevicePropValue",
        GET_PARTIAL_OBJECT to "GetPartialObject",
    )

    fun name(code: Int): String =
        names[code] ?: CanonEosOperation.name(code) ?: "Operation(0x%04X)".format(code)
}

/**
 * Canon EOS vendor operations (0x91xx).
 *
 * ⚠️ **UNVERIFIED — transcribed from the plan's Appendix A, which was itself written from
 * memory.** Check every one against `ptp.h` before use, and correct both this file and
 * Appendix A together. Nothing here is used before M3.
 */
object CanonEosOperation {
    const val GET_PARTIAL_OBJECT = 0x9107
    const val REMOTE_RELEASE = 0x910F
    const val SET_DEVICE_PROP_VALUE_EX = 0x9110
    const val GET_REMOTE_MODE = 0x9113
    const val SET_REMOTE_MODE = 0x9114
    const val SET_EVENT_MODE = 0x9115
    const val GET_EVENT = 0x9116
    const val TRANSFER_COMPLETE = 0x9117
    const val CANCEL_TRANSFER = 0x9118
    const val RESET_TRANSFER = 0x9119

    /**
     * **The capacity hack (`P-05`) — an OPERATION, not a device property.**
     *
     * Confirmed present on the 200D II. Takes three parameters
     * (capacity, blockSize, flag). Getting this wrong costs a lot of time: writing
     * `0xD11A` as a *property* instead returns `DeviceBusy` forever, which reads as a
     * transient error and invites a pointless retry loop. It is not transient — it is the
     * camera rejecting a write it does not implement.
     */
    const val PC_HDD_CAPACITY = 0x911A
    const val SET_UI_LOCK = 0x911B
    const val RESET_UI_LOCK = 0x911C
    const val KEEP_DEVICE_ON = 0x911D
    const val SET_NULL_PACKET_MODE = 0x911E
    const val BULB_START = 0x9125
    const val BULB_END = 0x9126
    const val REMOTE_RELEASE_ON = 0x9128
    const val REMOTE_RELEASE_OFF = 0x9129
    const val GET_VIEWFINDER_DATA = 0x9153
    const val DO_AF = 0x9154
    const val DRIVE_LENS = 0x9155
    const val ZOOM = 0x9158
    const val ZOOM_POSITION = 0x9159
    const val SET_LIVE_AF_FRAME = 0x915A
    const val AF_CANCEL = 0x9160

    private val names = mapOf(
        GET_PARTIAL_OBJECT to "EOS_GetPartialObject",
        REMOTE_RELEASE to "EOS_RemoteRelease",
        SET_DEVICE_PROP_VALUE_EX to "EOS_SetDevicePropValueEx",
        GET_REMOTE_MODE to "EOS_GetRemoteMode",
        SET_REMOTE_MODE to "EOS_SetRemoteMode",
        SET_EVENT_MODE to "EOS_SetEventMode",
        GET_EVENT to "EOS_GetEvent",
        TRANSFER_COMPLETE to "EOS_TransferComplete",
        CANCEL_TRANSFER to "EOS_CancelTransfer",
        RESET_TRANSFER to "EOS_ResetTransfer",
        PC_HDD_CAPACITY to "EOS_PCHDDCapacity",
        SET_UI_LOCK to "EOS_SetUILock",
        RESET_UI_LOCK to "EOS_ResetUILock",
        KEEP_DEVICE_ON to "EOS_KeepDeviceOn",
        SET_NULL_PACKET_MODE to "EOS_SetNullPacketMode",
        BULB_START to "EOS_BulbStart",
        BULB_END to "EOS_BulbEnd",
        REMOTE_RELEASE_ON to "EOS_RemoteReleaseOn",
        REMOTE_RELEASE_OFF to "EOS_RemoteReleaseOff",
        GET_VIEWFINDER_DATA to "EOS_GetViewFinderData",
        DO_AF to "EOS_DoAf",
        DRIVE_LENS to "EOS_DriveLens",
        ZOOM to "EOS_Zoom",
        ZOOM_POSITION to "EOS_ZoomPosition",
        SET_LIVE_AF_FRAME to "EOS_SetLiveAfFrame",
        AF_CANCEL to "EOS_AfCancel",
    )

    fun name(code: Int): String? = names[code]
}

/** Standard PTP response codes. 0x2001 is the only success value. */
object PtpResponse {
    const val OK = 0x2001
    const val GENERAL_ERROR = 0x2002
    const val SESSION_NOT_OPEN = 0x2003
    const val INVALID_TRANSACTION_ID = 0x2004
    const val OPERATION_NOT_SUPPORTED = 0x2005
    const val PARAMETER_NOT_SUPPORTED = 0x2006
    const val INCOMPLETE_TRANSFER = 0x2007
    const val INVALID_STORAGE_ID = 0x2008
    const val INVALID_OBJECT_HANDLE = 0x2009
    const val DEVICE_PROP_NOT_SUPPORTED = 0x200A
    const val INVALID_OBJECT_FORMAT_CODE = 0x200B
    const val STORE_FULL = 0x200C
    const val OBJECT_WRITE_PROTECTED = 0x200D
    const val STORE_READ_ONLY = 0x200E
    const val ACCESS_DENIED = 0x200F
    const val NO_THUMBNAIL_PRESENT = 0x2010
    const val PARTIAL_DELETION = 0x2012
    const val STORE_NOT_AVAILABLE = 0x2013
    const val NO_VALID_OBJECT_INFO = 0x2015
    const val INVALID_CODE_FORMAT = 0x2016
    const val UNKNOWN_VENDOR_CODE = 0x2017
    const val CAPTURE_ALREADY_TERMINATED = 0x2018
    const val DEVICE_BUSY = 0x2019
    const val INVALID_PARENT_OBJECT = 0x201A
    const val INVALID_DEVICE_PROP_FORMAT = 0x201B
    const val INVALID_DEVICE_PROP_VALUE = 0x201C
    const val INVALID_PARAMETER = 0x201D
    const val SESSION_ALREADY_OPEN = 0x201E
    const val TRANSACTION_CANCELLED = 0x201F

    /**
     * Canon vendor code: the requested subsystem is not ready **yet**.
     *
     * > `P-21`, observed on hardware 2026-08-14. `EOS_GetViewFinderData` answers `0xA102`
     * > for the first stretch after live view is enabled, while the mirror flips up and the
     * > sensor starts streaming. It is transient in exactly the way `DeviceBusy` is, but it
     * > is a *vendor* code, so treating only `DeviceBusy` as retryable makes live view look
     * > permanently broken when it is merely still waking up.
     */
    const val CANON_EOS_NOT_READY = 0xA102

    private val names = mapOf(
        OK to "OK",
        GENERAL_ERROR to "GeneralError",
        SESSION_NOT_OPEN to "SessionNotOpen",
        INVALID_TRANSACTION_ID to "InvalidTransactionID",
        OPERATION_NOT_SUPPORTED to "OperationNotSupported",
        PARAMETER_NOT_SUPPORTED to "ParameterNotSupported",
        INCOMPLETE_TRANSFER to "IncompleteTransfer",
        INVALID_STORAGE_ID to "InvalidStorageID",
        INVALID_OBJECT_HANDLE to "InvalidObjectHandle",
        DEVICE_PROP_NOT_SUPPORTED to "DevicePropNotSupported",
        INVALID_OBJECT_FORMAT_CODE to "InvalidObjectFormatCode",
        STORE_FULL to "StoreFull",
        OBJECT_WRITE_PROTECTED to "ObjectWriteProtected",
        STORE_READ_ONLY to "StoreReadOnly",
        ACCESS_DENIED to "AccessDenied",
        NO_THUMBNAIL_PRESENT to "NoThumbnailPresent",
        PARTIAL_DELETION to "PartialDeletion",
        STORE_NOT_AVAILABLE to "StoreNotAvailable",
        NO_VALID_OBJECT_INFO to "NoValidObjectInfo",
        INVALID_CODE_FORMAT to "InvalidCodeFormat",
        UNKNOWN_VENDOR_CODE to "UnknownVendorCode",
        CAPTURE_ALREADY_TERMINATED to "CaptureAlreadyTerminated",
        DEVICE_BUSY to "DeviceBusy",
        INVALID_PARENT_OBJECT to "InvalidParentObject",
        INVALID_DEVICE_PROP_FORMAT to "InvalidDevicePropFormat",
        INVALID_DEVICE_PROP_VALUE to "InvalidDevicePropValue",
        INVALID_PARAMETER to "InvalidParameter",
        SESSION_ALREADY_OPEN to "SessionAlreadyOpen",
        TRANSACTION_CANCELLED to "TransactionCancelled",
    )

    fun name(code: Int): String = names[code] ?: "Response(0x%04X)".format(code)

    /** Canon vendor responses live in 0xAxxx. Worth flagging distinctly in logs. */
    fun isVendorSpecific(code: Int): Boolean = code in 0xA000..0xAFFF
}

/** Object format codes. Only the ones we care about for JPEG-only capture (plan section 2). */
object PtpObjectFormat {
    const val UNDEFINED = 0x3000
    const val ASSOCIATION = 0x3001
    const val EXIF_JPEG = 0x3801
    const val TIFF = 0x380D
    /** Canon CR3. Present for recognition only - we do not shoot raw (plan section 2). */
    const val CANON_CR3 = 0xB108

    fun name(code: Int): String = when (code) {
        UNDEFINED -> "Undefined"
        ASSOCIATION -> "Association"
        EXIF_JPEG -> "EXIF/JPEG"
        TIFF -> "TIFF"
        CANON_CR3 -> "Canon CR3"
        else -> "Format(0x%04X)".format(code)
    }
}

/** Vendor extension IDs reported in DeviceInfo. */
object PtpVendorExtension {
    const val EASTMAN_KODAK = 0x00000001
    const val MICROSOFT = 0x00000006
    const val NIKON = 0x0000000A
    const val CANON = 0x0000000B
    const val SONY = 0x00000011

    fun name(id: Long): String = when (id.toInt()) {
        EASTMAN_KODAK -> "Eastman Kodak"
        MICROSOFT -> "Microsoft"
        NIKON -> "Nikon"
        CANON -> "Canon"
        SONY -> "Sony"
        0 -> "none"
        else -> "Vendor(0x%08X)".format(id)
    }
}

/** Fixed sizes of the PTP-over-USB container header. */
object PtpHeader {
    const val SIZE = 12
    const val MAX_PARAMS = 5
    /** A command or response container is the header plus at most five u32 parameters. */
    const val MAX_COMMAND_SIZE = SIZE + MAX_PARAMS * 4
}
