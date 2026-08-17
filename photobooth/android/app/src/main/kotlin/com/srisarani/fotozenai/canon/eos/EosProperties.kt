package com.srisarani.fotozenai.canon.eos

import com.srisarani.fotozenai.canon.ptp.CanonEosOperation
import com.srisarani.fotozenai.canon.ptp.PtpException
import com.srisarani.fotozenai.canon.ptp.PtpSession
import com.srisarani.fotozenai.canon.ptp.PtpWriter
import com.srisarani.fotozenai.canon.CanonLog

/**
 * Canon EOS device property codes.
 *
 * > ⚠️ **These are NOT discoverable from `GetDeviceInfo`.** Verified on hardware
 * > 2026-08-13 (`P-12`): an EOS 200D II reports 5 standard properties in `DeviceInfo`
 * > while emitting `PropValueChanged` events for dozens of these `0xD1xx` codes. The
 * > event stream is the only way to enumerate them, which is why M7 builds its catalogue
 * > by observing events.
 *
 * The codes below are transcribed and still unverified individually. The live event stream
 * from the connected body showed traffic on 0xD101–0xD11B and beyond, which is consistent
 * with this block being broadly right, but each one still needs confirming against `ptp.h`
 * before M7 relies on its *meaning*.
 */
object EosProperty {
    const val APERTURE = 0xD101
    const val SHUTTER_SPEED = 0xD102
    const val ISO_SPEED = 0xD103
    const val EXPOSURE_COMPENSATION = 0xD104
    const val AUTO_EXPOSURE_MODE = 0xD105
    const val DRIVE_MODE = 0xD106
    const val METERING_MODE = 0xD107
    const val FOCUS_MODE = 0xD108
    const val WHITE_BALANCE = 0xD109
    const val COLOR_TEMPERATURE = 0xD10A
    const val COLOR_SPACE = 0xD10F
    const val PICTURE_STYLE = 0xD110
    const val BATTERY_POWER = 0xD111
    const val CAMERA_TIME = 0xD113
    const val OWNER = 0xD115

    /** The fake free-space value. See [EosCapture.configureForHostCapture] and `P-05`. */
    const val CAPACITY = 0xD11A
    const val AVAILABLE_SHOTS = 0xD11B
    const val CAPTURE_DESTINATION = 0xD11C
    const val CURRENT_STORAGE = 0xD11E
    const val CURRENT_FOLDER = 0xD11F
    const val IMAGE_FORMAT = 0xD120

    const val EVF_OUTPUT_DEVICE = 0xD1B0

    private val names = mapOf(
        APERTURE to "Aperture",
        SHUTTER_SPEED to "ShutterSpeed",
        ISO_SPEED to "ISOSpeed",
        EXPOSURE_COMPENSATION to "ExpCompensation",
        AUTO_EXPOSURE_MODE to "AutoExposureMode",
        DRIVE_MODE to "DriveMode",
        METERING_MODE to "MeteringMode",
        FOCUS_MODE to "FocusMode",
        WHITE_BALANCE to "WhiteBalance",
        COLOR_TEMPERATURE to "ColorTemperature",
        COLOR_SPACE to "ColorSpace",
        PICTURE_STYLE to "PictureStyle",
        BATTERY_POWER to "BatteryPower",
        CAMERA_TIME to "CameraTime",
        OWNER to "Owner",
        CAPACITY to "Capacity",
        AVAILABLE_SHOTS to "AvailableShots",
        CAPTURE_DESTINATION to "CaptureDestination",
        CURRENT_STORAGE to "CurrentStorage",
        CURRENT_FOLDER to "CurrentFolder",
        IMAGE_FORMAT to "ImageFormat",
        EVF_OUTPUT_DEVICE to "EVFOutputDevice",
    )

    fun name(code: Int): String = names[code] ?: "EosProp(0x%04X)".format(code)
}

/**
 * Values for [EosProperty.DRIVE_MODE].
 *
 * ## Why the booth cares
 *
 * The body's drive mode is what produces a countdown before the shutter fires — it is a
 * *camera* setting, not anything the app does. Observed on hardware 2026-08-14: the 200D II
 * reported `DriveMode = 0x10` (10-second self-timer), so every remote release counted down
 * ten seconds first. For an unattended booth that is simply broken, and it is invisible
 * from the app unless you decode this property.
 *
 * [SINGLE_SHOT] is forced at connect so the shutter fires immediately regardless of how the
 * body was left configured.
 */
object EosDriveMode {
    const val SINGLE_SHOT = 0x00L
    const val CONTINUOUS = 0x01L
    const val VIDEO = 0x02L
    const val SELF_TIMER_10S = 0x10L
    const val SELF_TIMER_CONTINUOUS = 0x11L
    const val SELF_TIMER_2S = 0x12L

    private val names = mapOf(
        SINGLE_SHOT to "Single",
        CONTINUOUS to "Continuous",
        VIDEO to "Video",
        SELF_TIMER_10S to "Self-timer 10s",
        SELF_TIMER_CONTINUOUS to "Self-timer continuous",
        SELF_TIMER_2S to "Self-timer 2s",
    )

    fun name(value: Long): String = names[value] ?: "DriveMode(0x%02X)".format(value)

    /** True for any value that delays the shutter — what the booth must never ship with. */
    fun isSelfTimer(value: Long): Boolean = value >= SELF_TIMER_10S
}

/** Values for [EosProperty.CAPTURE_DESTINATION]. ⚠️ VERIFY against `ptp.h`. */
object EosCaptureDestination {
    const val CAMERA_CARD = 2
    /** Save to the host rather than the card. Requires the capacity hack — see `P-05`. */
    const val HOST = 4
    const val BOTH =
        CAMERA_CARD or HOST
}

/**
 * Writes EOS device properties via `EOS_SetDevicePropValueEx` (0x9110).
 *
 * Payload layout (little-endian):
 * ```
 * u32 size        total byte count INCLUDING this field
 * u32 propCode
 * ...  value      typically a single u32
 * ```
 *
 * Note this is a *data-phase* operation: the property code travels in the payload, not as
 * a command parameter. Passing it as a parameter instead is a silent no-op on some bodies.
 */
class EosProperties(private val ptp: PtpSession) {

    /** Sets a property whose value is a single u32. Covers nearly everything we need. */
    fun setUInt32(propertyCode: Int, value: Long) {
        val payload = PtpWriter(12)
            .u32(12L) // size: 4 (size) + 4 (propcode) + 4 (value)
            .u32(propertyCode.toLong())
            .u32(value)
            .toByteArray()

        CanonLog.d("EOS set %s = 0x%08X", EosProperty.name(propertyCode), value)
        ptp.transact(CanonEosOperation.SET_DEVICE_PROP_VALUE_EX, outgoingData = payload)
    }

    /** Sets a property carrying an arbitrary payload (strings, structs). */
    fun setRaw(propertyCode: Int, value: ByteArray) {
        val payload = PtpWriter(8 + value.size)
            .u32((8 + value.size).toLong())
            .u32(propertyCode.toLong())
            .bytes(value)
            .toByteArray()

        CanonLog.d("EOS set %s = %d bytes", EosProperty.name(propertyCode), value.size)
        ptp.transact(CanonEosOperation.SET_DEVICE_PROP_VALUE_EX, outgoingData = payload)
    }

    /**
     * Best-effort set. Returns false instead of throwing.
     *
     * Used where a property may legitimately be read-only — most obviously when the mode
     * dial is in an Auto position, where writes fail with unhelpful errors (`C-04`).
     */
    fun trySetUInt32(propertyCode: Int, value: Long): Boolean =
        runCatching { setUInt32(propertyCode, value) }
            .onFailure { CanonLog.w("Could not set %s: %s", EosProperty.name(propertyCode), it.message) }
            .isSuccess

    /**
     * Sets a property, retrying on `DeviceBusy`.
     *
     * ## Why this exists (`P-07`, observed on hardware 2026-08-13)
     *
     * Immediately after the EOS handshake the camera returns `DeviceBusy` for property
     * writes — it is still settling into remote mode. The very first thing we try to set
     * is the capacity hack (`P-05`), so without a retry the *most important* property in
     * the capture path is the one most likely to fail.
     *
     * `DeviceBusy` is explicitly transient and is the one response code worth retrying
     * blind. Everything else (read-only, unsupported) is a real answer and returns
     * immediately — retrying those would just add latency to a guaranteed failure.
     */
    fun setUInt32WithRetry(
        propertyCode: Int,
        value: Long,
        maxAttempts: Int = 5,
        initialDelayMs: Long = 100,
    ): Boolean {
        var delayMs = initialDelayMs
        repeat(maxAttempts) { attempt ->
            try {
                setUInt32(propertyCode, value)
                if (attempt > 0) {
                    CanonLog.i("Set %s on attempt %d", EosProperty.name(propertyCode), attempt + 1)
                }
                return true
            } catch (e: PtpException.OperationFailed) {
                if (!e.isBusy) {
                    // A definitive answer - read-only, unsupported. Retrying is pointless.
                    CanonLog.w("Could not set %s: %s", EosProperty.name(propertyCode), e.message)
                    return false
                }
                CanonLog.d(
                    "%s busy, retrying in %dms (attempt %d/%d)",
                    EosProperty.name(propertyCode),
                    delayMs,
                    attempt + 1,
                    maxAttempts,
                )
                Thread.sleep(delayMs)
                delayMs *= 2
            } catch (e: Exception) {
                CanonLog.w(e, "Could not set %s", EosProperty.name(propertyCode))
                return false
            }
        }
        CanonLog.e("Gave up setting %s after %d attempts (still busy)", EosProperty.name(propertyCode), maxAttempts)
        return false
    }
}
