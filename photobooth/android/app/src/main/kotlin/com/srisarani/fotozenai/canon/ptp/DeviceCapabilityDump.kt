package com.srisarani.fotozenai.canon.ptp

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * Renders a [PtpDeviceInfo] as a committable Markdown document.
 *
 * M2's acceptance criterion is not "parse DeviceInfo" - it is **commit the dump to
 * `docs/device-capabilities/`**, because that file is the authoritative answer to every
 * later "does this body support X?" question. In particular it is what M7's control
 * surface is derived from, rather than the plan's unverified Appendix B.
 *
 * The dump deliberately calls out which of our transcribed Canon opcodes the body
 * actually reports, so the guesses in [CanonEosOperation] can be confirmed or corrected
 * in one pass rather than discovered one failure at a time.
 */
object DeviceCapabilityDump {

    fun render(info: PtpDeviceInfo, extraNotes: List<String> = emptyList()): String = buildString {
        val timestamp = SimpleDateFormat("yyyy-MM-dd HH:mm:ss", Locale.US).format(Date())

        appendLine("# Device capabilities — ${info.manufacturer} ${info.model}")
        appendLine()
        appendLine("Generated: $timestamp")
        appendLine()
        appendLine("> This file is **generated from the camera itself** and is authoritative.")
        appendLine("> Where it disagrees with `ptp.h`, this file wins. Where `docs/PLAN.md`")
        appendLine("> Appendix A or B disagrees with this file, **fix the plan**.")
        appendLine()

        appendLine("## Identity")
        appendLine()
        appendLine("| Field | Value |")
        appendLine("|---|---|")
        appendLine("| Manufacturer | ${info.manufacturer} |")
        appendLine("| Model | ${info.model} |")
        appendLine("| Firmware | ${info.deviceVersion} |")
        appendLine("| Serial | ${info.serialNumber} |")
        appendLine("| PTP standard version | ${formatVersion(info.standardVersion)} |")
        appendLine("| Vendor extension | ${PtpVendorExtension.name(info.vendorExtensionId)} |")
        appendLine("| Vendor ext. version | ${formatVersion(info.vendorExtensionVersion)} |")
        appendLine("| Vendor ext. description | ${info.vendorExtensionDesc.ifEmpty { "—" }} |")
        appendLine("| Functional mode | 0x%04X |".format(info.functionalMode))
        appendLine()

        appendLine("## Readiness checks")
        appendLine()
        appendLine("| Check | Result |")
        appendLine("|---|---|")
        appendLine("| **Implements EOS operation set** (the test that matters) | ${tick(info.isCanonEos)} |")
        appendLine("| Declares Canon vendor extension | ${tick(info.declaresCanonVendorExtension)} — *expected to be NO; EOS bodies report Microsoft* |")
        appendLine("| JPEG capture supported (plan §2) | ${tick(info.supportsJpegCapture)} |")
        appendLine("| EOS remote mode opcodes present (M3) | ${tick(info.supportsEosRemoteMode)} |")
        appendLine("| `GetPartialObject` present (M4) | ${tick(info.supportsOperation(PtpOperation.GET_PARTIAL_OBJECT))} |")
        appendLine()

        appendLine("## Operations supported (${info.operationsSupported.size})")
        appendLine()
        appendLine("| Code | Name | Notes |")
        appendLine("|---|---|---|")
        info.operationsSupported.sorted().forEach { code ->
            val known = CanonEosOperation.name(code)
            val note = when {
                known != null -> "Canon vendor — **confirms our transcribed constant**"
                code in 0x9000..0x9FFF -> "⚠️ vendor opcode we do not have a name for"
                else -> ""
            }
            appendLine("| `0x%04X` | %s | %s |".format(code, PtpOperation.name(code), note))
        }
        appendLine()

        appendLine("### Transcribed Canon opcodes NOT reported by this body")
        appendLine()
        val missing = knownCanonOpcodes().filterNot { info.supportsOperation(it.first) }
        if (missing.isEmpty()) {
            appendLine("None — every opcode in `CanonEosOperation` is supported.")
        } else {
            appendLine("These are in `CanonEosOperation` but this camera does not list them.")
            appendLine("Either the constant is wrong (check `ptp.h`) or the body genuinely lacks it.")
            appendLine("**Record each one in `GAPS_AND_EDGE_CASES.md` before relying on it.**")
            appendLine()
            missing.forEach { (code, name) -> appendLine("- `0x%04X` %s".format(code, name)) }
        }
        appendLine()

        appendLine("## Device properties supported (${info.devicePropertiesSupported.size})")
        appendLine()
        appendLine("> ⚠️ **This list is NOT the EOS control surface.** Verified on hardware")
        appendLine("> 2026-08-13: an EOS 200D II reports only ~5 standard properties here, while")
        appendLine("> emitting `PropValueChanged` events for dozens of `0xD1xx` EOS properties.")
        appendLine("> **EOS properties are discoverable only through the event stream**, not through")
        appendLine("> `GetDeviceInfo`. M7 must build its control surface from observed events plus")
        appendLine("> `EOS_SetDevicePropValueEx`, not from this list.")
        appendLine()
        appendLine("| Code |")
        appendLine("|---|")
        info.devicePropertiesSupported.sorted().forEach { appendLine("| `0x%04X` |".format(it)) }
        appendLine()

        appendLine("## Events supported (${info.eventsSupported.size})")
        appendLine()
        info.eventsSupported.sorted().forEach { appendLine("- `0x%04X`".format(it)) }
        appendLine()

        appendLine("## Capture formats (${info.captureFormats.size})")
        appendLine()
        info.captureFormats.forEach { appendLine("- `0x%04X` %s".format(it, PtpObjectFormat.name(it))) }
        appendLine()

        appendLine("## Image formats (${info.imageFormats.size})")
        appendLine()
        info.imageFormats.forEach { appendLine("- `0x%04X` %s".format(it, PtpObjectFormat.name(it))) }
        appendLine()

        if (extraNotes.isNotEmpty()) {
            appendLine("## Notes")
            appendLine()
            extraNotes.forEach { appendLine("- $it") }
            appendLine()
        }
    }

    /** Suggested filename, e.g. `canon-eos-200d-ii-capabilities.md`. */
    fun suggestedFilename(info: PtpDeviceInfo): String {
        val slug = "${info.manufacturer} ${info.model}"
            .lowercase(Locale.US)
            .replace(Regex("[^a-z0-9]+"), "-")
            .trim('-')
            .ifEmpty { "unknown-device" }
        return "$slug-capabilities.md"
    }

    private fun tick(value: Boolean) = if (value) "✅ yes" else "❌ **no**"

    /** PTP versions are BCD-ish: 100 = 1.00. */
    private fun formatVersion(raw: Int) = "%d.%02d".format(raw / 100, raw % 100)

    private fun knownCanonOpcodes(): List<Pair<Int, String>> = listOf(
        CanonEosOperation.GET_PARTIAL_OBJECT,
        CanonEosOperation.REMOTE_RELEASE,
        CanonEosOperation.SET_DEVICE_PROP_VALUE_EX,
        CanonEosOperation.GET_REMOTE_MODE,
        CanonEosOperation.SET_REMOTE_MODE,
        CanonEosOperation.SET_EVENT_MODE,
        CanonEosOperation.GET_EVENT,
        CanonEosOperation.TRANSFER_COMPLETE,
        CanonEosOperation.CANCEL_TRANSFER,
        CanonEosOperation.RESET_TRANSFER,
        CanonEosOperation.SET_UI_LOCK,
        CanonEosOperation.RESET_UI_LOCK,
        CanonEosOperation.KEEP_DEVICE_ON,
        CanonEosOperation.SET_NULL_PACKET_MODE,
        CanonEosOperation.BULB_START,
        CanonEosOperation.BULB_END,
        CanonEosOperation.REMOTE_RELEASE_ON,
        CanonEosOperation.REMOTE_RELEASE_OFF,
        CanonEosOperation.GET_VIEWFINDER_DATA,
        CanonEosOperation.DO_AF,
        CanonEosOperation.DRIVE_LENS,
        CanonEosOperation.ZOOM,
        CanonEosOperation.ZOOM_POSITION,
        CanonEosOperation.SET_LIVE_AF_FRAME,
        CanonEosOperation.AF_CANCEL,
    ).map { it to (CanonEosOperation.name(it) ?: "unknown") }
}
