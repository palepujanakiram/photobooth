package com.srisarani.fotozenai.dnp

/** Raster payload for a DNP USB print. */
class DnpPrintImage(
    val pixels: IntArray,
    val width: Int,
    val height: Int,
)

/** Settings plus raster for [DnpUsbPrinter.print]. */
class DnpPrintJob(
    val image: DnpPrintImage,
    val size: DnpPrintSize,
    val copies: Int,
    val matte: Boolean = false,
)
