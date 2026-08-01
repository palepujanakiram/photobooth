package com.srisarani.fotozenai.dnp

/** Input for [DnpImageProcessor.prepareBitmap] — keeps the native call surface small. */
data class DnpPrepareBitmapOptions(
    val sourcePath: String,
    val size: DnpPrintSize,
    val filter: String = "Off",
    val brightness: Int = 0,
    val bordered: Boolean = false,
    val memoryEfficient: Boolean = false,
    val networkPrintSize: String? = null,
)
