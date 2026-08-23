package com.srisarani.fotozenai.canon.eos

import com.srisarani.fotozenai.canon.ptp.PtpReader
import com.srisarani.fotozenai.canon.CanonLog

/**
 * Canon EOS event codes.
 *
 * ⚠️ **UNVERIFIED** — transcribed the same way as the opcodes in `PtpConstants.kt`. Check
 * against libgphoto2's `ptp.h` (`PTP_EC_CANON_EOS_*`). The M2 capability dump lists the
 * events this body actually reports, which is the authoritative set.
 *
 * Getting a code wrong here is *not* fatal by design: the parser keeps unrecognised
 * records as [EosEvent.Unknown] rather than throwing, so a wrong constant costs us a
 * feature, never the session.
 */
object EosEventCode {
    const val REQUEST_GET_EVENT = 0xC101
    const val OBJECT_ADDED_EX = 0xC181
    const val OBJECT_REMOVED = 0xC182
    const val REQUEST_GET_OBJECT_INFO_EX = 0xC183
    const val STORAGE_STATUS_CHANGED = 0xC184
    const val STORAGE_INFO_CHANGED = 0xC185
    const val REQUEST_OBJECT_TRANSFER = 0xC186
    const val OBJECT_INFO_CHANGED_EX = 0xC187
    const val OBJECT_CONTENT_CHANGED = 0xC188
    const val PROP_VALUE_CHANGED = 0xC189
    const val AVAIL_LIST_CHANGED = 0xC18A
    const val CAMERA_STATUS_CHANGED = 0xC18B
    const val WILL_SOON_SHUTDOWN = 0xC18D
    const val SHUTDOWN_TIMER_UPDATED = 0xC18E
    const val REQUEST_CANCEL_TRANSFER = 0xC18F
    const val REQUEST_OBJECT_TRANSFER_DT = 0xC190
    const val STORE_ADDED = 0xC192
    const val STORE_REMOVED = 0xC193
    const val BULB_EXPOSURE_TIME = 0xC194
    const val RECORDING_TIME = 0xC195
    const val REQUEST_OBJECT_TRANSFER_TS = 0xC1A2
    const val AF_RESULT = 0xC1A3

    /**
     * **`ObjectAddedEx64` — what a 200D II actually sends when a photo is taken.**
     *
     * Decoded from live hardware 2026-08-13. Newer EOS bodies use this 64-bit-size variant
     * instead of [OBJECT_ADDED_EX] (0xC181). The 200D II lists 0xC181 in its DeviceInfo
     * events array but emits 0xC1A9 in practice — a good reminder that the capability list
     * says what a body *supports*, not what it *uses*.
     *
     * Payload, 44 bytes, all little-endian, **no filename**:
     * ```
     * 0   u32  objectHandle
     * 4   u32  objectFormat      (0x3801 = EXIF/JPEG)
     * 8   u32  (zero)
     * 12  u64  sizeBytes         <- 64-bit, hence "Ex64"
     * 20  u32  parentObjectHandle
     * 24  u32[4] (zero)
     * 40  u32  flag (observed 1)
     * ```
     */
    const val OBJECT_ADDED_EX64 = 0xC1A9

    private val names = mapOf(
        REQUEST_GET_EVENT to "RequestGetEvent",
        OBJECT_ADDED_EX to "ObjectAddedEx",
        OBJECT_REMOVED to "ObjectRemoved",
        REQUEST_GET_OBJECT_INFO_EX to "RequestGetObjectInfoEx",
        STORAGE_STATUS_CHANGED to "StorageStatusChanged",
        STORAGE_INFO_CHANGED to "StorageInfoChanged",
        REQUEST_OBJECT_TRANSFER to "RequestObjectTransfer",
        OBJECT_INFO_CHANGED_EX to "ObjectInfoChangedEx",
        OBJECT_CONTENT_CHANGED to "ObjectContentChanged",
        PROP_VALUE_CHANGED to "PropValueChanged",
        AVAIL_LIST_CHANGED to "AvailListChanged",
        CAMERA_STATUS_CHANGED to "CameraStatusChanged",
        WILL_SOON_SHUTDOWN to "WillSoonShutdown",
        SHUTDOWN_TIMER_UPDATED to "ShutdownTimerUpdated",
        REQUEST_CANCEL_TRANSFER to "RequestCancelTransfer",
        REQUEST_OBJECT_TRANSFER_DT to "RequestObjectTransferDT",
        STORE_ADDED to "StoreAdded",
        STORE_REMOVED to "StoreRemoved",
        BULB_EXPOSURE_TIME to "BulbExposureTime",
        RECORDING_TIME to "RecordingTime",
        REQUEST_OBJECT_TRANSFER_TS to "RequestObjectTransferTS",
        AF_RESULT to "AfResult",
        OBJECT_ADDED_EX64 to "ObjectAddedEx64",
    )

    fun name(code: Int): String = names[code] ?: "EosEvent(0x%04X)".format(code)
}

/**
 * A single decoded EOS event.
 *
 * Only the events later milestones actually consume get a typed variant. Everything else
 * is preserved as [Unknown] with its raw bytes - deliberately, so that an event we did not
 * anticipate can be decoded from a committed log later rather than being lost.
 */
sealed interface EosEvent {

    val code: Int

    /** A new object is available on the camera. **M4's capture trigger.** */
    data class ObjectAdded(
        val objectHandle: Long,
        val storageId: Long,
        val objectFormat: Int,
        val sizeBytes: Long,
        val filename: String,
        override val code: Int = EosEventCode.OBJECT_ADDED_EX,
    ) : EosEvent

    /** The camera is asking the host to pull an object. Also a capture path on some bodies. */
    data class ObjectTransferRequested(
        val objectHandle: Long,
        val sizeBytes: Long,
        val filename: String,
        override val code: Int = EosEventCode.REQUEST_OBJECT_TRANSFER,
    ) : EosEvent

    /** A device property changed - on the host's request, or on the camera's own dials. M7. */
    data class PropertyChanged(
        val propertyCode: Int,
        val rawValue: ByteArray,
        override val code: Int = EosEventCode.PROP_VALUE_CHANGED,
    ) : EosEvent {
        override fun equals(other: Any?): Boolean =
            other is PropertyChanged && propertyCode == other.propertyCode &&
                rawValue.contentEquals(other.rawValue)

        override fun hashCode(): Int = 31 * propertyCode + rawValue.contentHashCode()
    }

    /** The set of legal values for a property changed - usually because the mode dial moved (C-04). */
    data class AvailableValuesChanged(
        val propertyCode: Int,
        override val code: Int = EosEventCode.AVAIL_LIST_CHANGED,
    ) : EosEvent

    data class CameraStatusChanged(
        val status: Long,
        override val code: Int = EosEventCode.CAMERA_STATUS_CHANGED,
    ) : EosEvent

    /** Autofocus finished. M4 needs this to distinguish "AF failed" from "event loop dead" (C-02). */
    data class AfResult(
        val result: Long,
        override val code: Int = EosEventCode.AF_RESULT,
    ) : EosEvent

    /**
     * The camera is about to power off. **Actionable**: the keepalive is not working, or
     * auto power-off is enabled in the camera menu (C-03).
     */
    data class WillSoonShutdown(
        override val code: Int = EosEventCode.WILL_SOON_SHUTDOWN,
    ) : EosEvent

    data class StorageChanged(
        override val code: Int,
    ) : EosEvent

    /**
     * An event we do not decode. Kept with its raw payload rather than dropped.
     *
     * The plan is explicit about this (M3): log unknown event codes rather than throwing.
     * A body that emits something unexpected must not be able to kill the event loop,
     * because a dead event loop silently breaks capture (C-01).
     */
    data class Unknown(
        override val code: Int,
        val payload: ByteArray,
    ) : EosEvent {
        override fun equals(other: Any?): Boolean =
            other is Unknown && code == other.code && payload.contentEquals(other.payload)

        override fun hashCode(): Int = 31 * code + payload.contentHashCode()

        override fun toString(): String =
            "Unknown(${EosEventCode.name(code)}, ${payload.size}B: ${payload.toHexPreview()})"
    }
}

private fun ByteArray.toHexPreview(limit: Int = 96): String =
    take(limit).joinToString(" ") { "%02X".format(it) } + if (size > limit) " ..." else ""

/**
 * Parses the packed event array returned by `EOS_GetEvent`.
 *
 * ## Wire format
 *
 * A concatenated sequence of variable-length records, each:
 *
 * ```
 * u32 size    total record length INCLUDING these 8 header bytes
 * u32 type    event code
 * ...         payload, (size - 8) bytes
 * ```
 *
 * The array ends at a record with `size == 0`, or when the buffer runs out.
 *
 * ## Why this parser is aggressively defensive
 *
 * The plan calls this out directly: *"parse defensively and log unknown event codes rather
 * than throwing."* The reason is C-01. This parser runs inside the event loop, and if it
 * throws, the loop dies. A dead event loop does not announce itself - the camera simply
 * stops responding to capture, which looks like a bug in the capture code and sends you
 * debugging entirely the wrong milestone.
 *
 * So: a malformed record ends parsing and returns what was decoded so far. It never
 * propagates.
 */
object EosEventParser {

    /** Records shorter than the 8-byte header are impossible; treat as end of array. */
    private const val RECORD_HEADER_SIZE = 8

    /** A record larger than this is nonsense and means we have lost sync. */
    private const val MAX_RECORD_SIZE = 16 * 1024 * 1024

    fun parse(payload: ByteArray): List<EosEvent> {
        val events = mutableListOf<EosEvent>()
        val reader = PtpReader(payload)
        while (reader.remaining >= RECORD_HEADER_SIZE) {
            when (val record = readNextRecord(reader, events.size)) {
                RecordRead.End -> break
                RecordRead.Skip -> continue
                is RecordRead.Item -> events.add(record.event)
            }
        }
        return events
    }

    private fun readNextRecord(reader: PtpReader, decodedSoFar: Int): RecordRead {
        val recordStart = reader.position
        val size = readU32OrNull(reader) ?: run {
            CanonLog.w("Event array truncated at offset %d", recordStart)
            return RecordRead.End
        }
        if (size == 0L) return RecordRead.End
        if (size < RECORD_HEADER_SIZE || size > MAX_RECORD_SIZE) {
            CanonLog.e(
                "Implausible EOS event record size %d at offset %d - stopping. " +
                    "Decoded %d event(s) before this.",
                size,
                recordStart,
                decodedSoFar,
            )
            return RecordRead.End
        }
        val type = readU32OrNull(reader)?.toInt() ?: return RecordRead.End
        if (type == 0) {
            // Observed on a real 200D II: 8-byte type-0 records are padding.
            val skip = (size - RECORD_HEADER_SIZE).toInt()
            if (skip in 1..reader.remaining) reader.skip(skip)
            return RecordRead.Skip
        }
        return readTypedRecord(reader, type, size)
    }

    private fun readTypedRecord(reader: PtpReader, type: Int, size: Long): RecordRead {
        val payloadSize = (size - RECORD_HEADER_SIZE).toInt()
        if (payloadSize > reader.remaining) {
            CanonLog.w(
                "EOS event %s declares %dB payload but only %dB remain - stopping",
                EosEventCode.name(type),
                payloadSize,
                reader.remaining,
            )
            return RecordRead.End
        }
        val recordPayload = if (payloadSize > 0) reader.bytes(payloadSize) else ByteArray(0)
        val event = try {
            decode(type, recordPayload)
        } catch (e: Exception) {
            CanonLog.w(e, "Failed to decode %s, keeping raw", EosEventCode.name(type))
            EosEvent.Unknown(type, recordPayload)
        }
        return RecordRead.Item(event)
    }

    private fun decode(type: Int, payload: ByteArray): EosEvent {
        val r = PtpReader(payload)
        return when (type) {
            EosEventCode.OBJECT_ADDED_EX -> decodeObjectAddedEx(r)
            EosEventCode.OBJECT_ADDED_EX64 -> decodeObjectAddedEx64(r)
            EosEventCode.REQUEST_OBJECT_TRANSFER -> EosEvent.ObjectTransferRequested(
                objectHandle = r.u32(),
                sizeBytes = run {
                    r.u32()
                    r.u32()
                    r.u32()
                },
                filename = readCString(r),
            )
            EosEventCode.PROP_VALUE_CHANGED -> EosEvent.PropertyChanged(
                propertyCode = r.u32().toInt(),
                rawValue = if (r.hasRemaining()) r.bytes(r.remaining) else ByteArray(0),
            )
            EosEventCode.AVAIL_LIST_CHANGED -> EosEvent.AvailableValuesChanged(
                propertyCode = r.u32().toInt(),
            )
            EosEventCode.CAMERA_STATUS_CHANGED -> EosEvent.CameraStatusChanged(status = r.u32())
            EosEventCode.AF_RESULT -> EosEvent.AfResult(result = r.u32())
            EosEventCode.WILL_SOON_SHUTDOWN -> EosEvent.WillSoonShutdown()
            EosEventCode.STORAGE_STATUS_CHANGED,
            EosEventCode.STORAGE_INFO_CHANGED,
            EosEventCode.STORE_ADDED,
            EosEventCode.STORE_REMOVED,
            -> EosEvent.StorageChanged(type)
            else -> EosEvent.Unknown(type, payload)
        }
    }

    private fun decodeObjectAddedEx(r: PtpReader): EosEvent.ObjectAdded =
        EosEvent.ObjectAdded(
            objectHandle = r.u32(),
            storageId = r.u32(),
            objectFormat = r.u32().toInt(),
            sizeBytes = run {
                r.u32()
                r.u32()
            },
            filename = readCString(r),
        )

    private fun decodeObjectAddedEx64(r: PtpReader): EosEvent.ObjectAdded {
        val handle = r.u32()
        val format = r.u32().toInt()
        r.u32()
        val size = r.u64()
        val parent = r.u32()
        return EosEvent.ObjectAdded(
            objectHandle = handle,
            storageId = parent,
            objectFormat = format,
            sizeBytes = size,
            filename = "",
            code = EosEventCode.OBJECT_ADDED_EX64,
        )
    }

    private fun readU32OrNull(reader: PtpReader): Long? =
        try {
            reader.u32()
        } catch (_: Exception) {
            null
        }

    private sealed class RecordRead {
        object End : RecordRead()
        object Skip : RecordRead()
        data class Item(val event: EosEvent) : RecordRead()
    }

    /**
     * EOS event payloads carry plain null-terminated ASCII filenames, not PTP strings.
     * Different convention in the same protocol - worth being explicit about.
     */
    private fun readCString(r: PtpReader): String {
        val sb = StringBuilder()
        while (r.hasRemaining()) {
            val b = r.u8()
            if (b == 0) break
            sb.append(b.toChar())
        }
        return sb.toString()
    }
}
