package com.srisarani.fotozenai.canon.eos

import com.srisarani.fotozenai.canon.ptp.PtpReader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import com.srisarani.fotozenai.canon.CanonLog

/**
 * Live camera settings, built by observing the EOS event stream.
 *
 * ## Why this is not read from `GetDeviceInfo`
 *
 * `P-12`, discovered on hardware: an EOS 200D II reports **5** device properties in
 * `GetDeviceInfo` while emitting `PropValueChanged` events for **dozens** of `0xD1xx` EOS
 * properties. The standard property list is effectively empty for our purposes. The plan
 * originally said to derive the control surface from that list; hardware proved that
 * wrong and the plan has been corrected.
 *
 * So the catalogue builds itself: every `PropValueChanged` event records the property and
 * its current value. Two useful consequences fall out of that —
 *
 * - **Changes made on the camera body propagate to the app for free.** Turn the mode dial
 *   or the exposure wheel and the UI follows, because the camera announces it the same way
 *   it announces our own writes.
 * - **We never guess what a body supports.** If a property never appears in the stream,
 *   this body does not expose it, and the UI simply has nothing to show.
 */
class EosCameraSettings(
    private val eos: EosSession,
    private val properties: EosProperties,
    private val scope: CoroutineScope,
) {

    /** Raw property values, keyed by EOS property code, as last announced by the camera. */
    private val _values = MutableStateFlow<Map<Int, Long>>(emptyMap())
    val values: StateFlow<Map<Int, Long>> = _values.asStateFlow()

    /** Property codes seen at least once — the body's actual, observed control surface. */
    private val _observedProperties = MutableStateFlow<Set<Int>>(emptySet())
    val observedProperties: StateFlow<Set<Int>> = _observedProperties.asStateFlow()

    fun start() {
        scope.launch {
            eos.events.collect { event ->
                when (event) {
                    is EosEvent.PropertyChanged -> record(event.propertyCode, event.rawValue)
                    else -> Unit
                }
            }
        }
    }

    private fun record(propertyCode: Int, rawValue: ByteArray) {
        // Most EOS properties carry a single u32. Longer payloads are structs we do not
        // decode yet - recording the first word keeps them visible without pretending to
        // understand them.
        if (rawValue.size < 4) return
        val value = runCatching { PtpReader(rawValue).u32() }.getOrNull() ?: return

        _values.value = _values.value + (propertyCode to value)
        if (propertyCode !in _observedProperties.value) {
            _observedProperties.value = _observedProperties.value + propertyCode
            CanonLog.d("New EOS property observed: %s = 0x%08X", EosProperty.name(propertyCode), value)
        }
    }

    fun raw(propertyCode: Int): Long? = _values.value[propertyCode]

    // ------------------------------------------------------------------ reads

    val iso: Long? get() = raw(EosProperty.ISO_SPEED)
    val aperture: Long? get() = raw(EosProperty.APERTURE)
    val shutter: Long? get() = raw(EosProperty.SHUTTER_SPEED)
    val whiteBalance: Long? get() = raw(EosProperty.WHITE_BALANCE)
    val driveMode: Long? get() = raw(EosProperty.DRIVE_MODE)
    val meteringMode: Long? get() = raw(EosProperty.METERING_MODE)
    val shootingMode: Long? get() = raw(EosProperty.AUTO_EXPOSURE_MODE)
    val batteryLevel: Long? get() = raw(EosProperty.BATTERY_POWER)
    val availableShots: Long? get() = raw(EosProperty.AVAILABLE_SHOTS)
    val colorSpace: Long? get() = raw(EosProperty.COLOR_SPACE)
    val focusMode: Long? get() = raw(EosProperty.FOCUS_MODE)

    /**
     * `C-04`: whether exposure properties can be written right now.
     *
     * The mode dial is physical and cannot be set remotely, so in Auto and scene positions
     * the camera owns exposure and rejects writes with unhelpful errors. The UI greys the
     * controls out rather than letting the user discover this by failure.
     */
    val exposureControlAllowed: Boolean
        get() = shootingMode?.let { EosPropertyValues.allowsExposureControl(it) } ?: false

    // ----------------------------------------------------------------- writes

    /**
     * Sets a property, taking the camera's UI lock for the duration.
     *
     * The lock stops the camera's own dials fighting the write mid-set. It is best-effort:
     * a lock we could not take is a degraded experience, not a reason to refuse the write.
     */
    fun set(propertyCode: Int, value: Long): Boolean {
        if (!exposureControlAllowed && propertyCode in EXPOSURE_PROPERTIES) {
            CanonLog.w(
                "Refusing to set %s: mode dial is at %s, which does not allow exposure control (C-04)",
                EosProperty.name(propertyCode),
                EosPropertyValues.label(EosPropertyValues.SHOOTING_MODE, shootingMode ?: -1),
            )
            return false
        }

        eos.setUiLock(true)
        return try {
            properties.setUInt32WithRetry(propertyCode, value)
        } finally {
            eos.setUiLock(false)
        }
    }

    /**
     * Steps a property through its value table.
     *
     * Note we do **not** optimistically update local state: the camera echoes the new value
     * back as a `PropValueChanged` event, and taking that as the source of truth means the
     * UI can never disagree with the body. A write the camera silently clamps or refuses
     * shows the camera's answer, not our hope.
     */
    fun step(propertyCode: Int, table: Map<Int, String>, forward: Boolean): Boolean {
        val current = raw(propertyCode) ?: return false
        val next = EosPropertyValues.step(table, current, forward)
        if (next == current) return false
        return set(propertyCode, next)
    }

    /** Sets the camera clock to device time (`C-15`). */
    fun syncClock(): Boolean {
        val nowSeconds = System.currentTimeMillis() / 1000
        return properties.trySetUInt32(EosProperty.CAMERA_TIME, nowSeconds)
    }

    /** Human-readable snapshot for the status panel and the M9 assessment. */
    fun summary(): String = buildString {
        append("ISO ").append(label(EosProperty.ISO_SPEED, EosPropertyValues.ISO))
        append(" · ").append(label(EosProperty.APERTURE, EosPropertyValues.APERTURE))
        append(" · ").append(label(EosProperty.SHUTTER_SPEED, EosPropertyValues.SHUTTER))
    }

    fun label(propertyCode: Int, table: Map<Int, String>): String =
        raw(propertyCode)?.let { EosPropertyValues.label(table, it) } ?: "—"

    private companion object {
        /** Properties the camera owns unless the mode dial allows manual control. */
        val EXPOSURE_PROPERTIES = setOf(
            EosProperty.ISO_SPEED,
            EosProperty.APERTURE,
            EosProperty.SHUTTER_SPEED,
            EosProperty.EXPOSURE_COMPENSATION,
        )
    }
}
