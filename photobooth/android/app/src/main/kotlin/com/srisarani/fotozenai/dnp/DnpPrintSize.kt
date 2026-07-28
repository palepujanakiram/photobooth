package com.srisarani.fotozenai.dnp

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
    SIZE_4X6("4x6", 2, 1920, 1240, "s4x6"),
    SIZE_5X7("5x7", 3, 1920, 2138, "s5x7"),
    SIZE_6X8("6x8", 4, 1920, 2436, "s6x8"),
    SIZE_2X6("2x6", 12, 1920, 1240, "s2x6");

    /** Aspect ratio (width / height) for UI preview. */
    val aspectRatio: Float get() = width.toFloat() / height.toFloat()

    companion object {
        const val NATIVE_WIDTH = 1920
        const val MULTICUT_6X4 = 2
        const val MULTICUT_5X7 = 3
        const val MULTICUT_6X8 = 4
        const val MULTICUT_6X4X2 = 12

        fun fromLabel(label: String): DnpPrintSize =
            entries.find { it.label == label } ?: SIZE_4X6
    }
}
