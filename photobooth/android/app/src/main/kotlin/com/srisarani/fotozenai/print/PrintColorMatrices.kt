package com.srisarani.fotozenai.print

import android.graphics.ColorMatrix

/** Shared photo-print color matrices used by DNP and Canon Selphy pipelines. */
object PrintColorMatrices {
    fun combined(
        filter: String,
        brightness: Int,
    ): ColorMatrix? {
        var matrix: ColorMatrix? =
            when (filter) {
                "B&W" -> {
                    ColorMatrix().apply { setSaturation(0f) }
                }

                "Sepia" -> {
                    ColorMatrix().apply {
                        set(
                            floatArrayOf(
                                0.393f,
                                0.769f,
                                0.189f,
                                0f,
                                0f,
                                0.349f,
                                0.686f,
                                0.168f,
                                0f,
                                0f,
                                0.272f,
                                0.534f,
                                0.131f,
                                0f,
                                0f,
                                0f,
                                0f,
                                0f,
                                1f,
                                0f,
                            ),
                        )
                    }
                }

                "Vivid" -> {
                    ColorMatrix().apply { setSaturation(1.6f) }
                }

                else -> {
                    null
                }
            }

        if (brightness != 0) {
            val scaleFactor = 1f + brightness * 0.12f
            val brightMatrix =
                ColorMatrix().apply {
                    setScale(scaleFactor, scaleFactor, scaleFactor, 1f)
                }
            matrix =
                if (matrix != null) {
                    val filterMatrix = matrix
                    ColorMatrix().apply { setConcat(brightMatrix, filterMatrix) }
                } else {
                    brightMatrix
                }
        }

        return matrix
    }
}
