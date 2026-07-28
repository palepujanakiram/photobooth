package com.srisarani.fotozenai.dnp

/** Native print width at 300 dpi (DS-RX1 / DS-RX1HS). */
private const val NATIVE_WIDTH = 1920

/** DNP multicut codes — must not be referenced from enum companion (init order). */
private const val MULTICUT_6X4 = 2
private const val MULTICUT_5X7 = 3
private const val MULTICUT_6X8 = 4

/**
 * Print dimensions for DNP DS-RX1 / DS-RX1HS at 300 dpi (native width 1920 px).
 * Values align with the open-source dnpds40 CUPS backend and DNP driver specs.
 */
enum class DnpPrintSize(
    val label: String,
    val multicut: Int,
    val width: Int,
    val height: Int,
    val wifiPrintSize: String,
) {
    SIZE_4X6("4x6", MULTICUT_6X4, NATIVE_WIDTH, 1240, "s4x6"),
    SIZE_5X7("5x7", MULTICUT_5X7, NATIVE_WIDTH, 2138, "s5x7"),
    SIZE_6X8("6x8", MULTICUT_6X8, NATIVE_WIDTH, 2436, "s6x8"),
    /** 2-inch strip cut on loaded 4×6 media — multicut must stay 6×4 (2), not 12. */
    SIZE_2X6("2x6", MULTICUT_6X4, NATIVE_WIDTH, 1240, "s2x6");

    /** Aspect ratio (width / height) for UI preview. */
    val aspectRatio: Float get() = width.toFloat() / height.toFloat()

    companion object {
        /** Two 4×6 frames on one sheet — not 2-inch cutter mode. */
        const val MULTICUT_6X4X2 = 12

        fun fromLabel(label: String): DnpPrintSize =
            entries.find { it.label == label } ?: SIZE_4X6

        /** Maps kiosk / WCM `printSize` tokens to native paper + multicut settings. */
        fun fromNetworkPrintSize(token: String): DnpPrintSize =
            when (token.trim().lowercase()) {
                "s6x4" -> SIZE_4X6
                "s5x7" -> SIZE_5X7
                "s6x8" -> SIZE_6X8
                "s2x6", "s6x2_2" -> SIZE_2X6
                else -> SIZE_4X6
            }
    }

    val usesStripCutter: Boolean
        get() = this == SIZE_2X6
}
