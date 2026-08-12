package com.srisarani.fotozenai.selphy

import android.graphics.Point
import android.graphics.Rect
import io.flutter.plugin.common.MethodChannel

/** Look/finish options applied while preparing a Selphy JPEG. */
internal data class SelphyLookSettings(
    val filter: String = "Off",
    val brightness: Int = 0,
    val bordered: Boolean = false,
)

/** Arguments for a Canon Selphy print job (USB or Wi‑Fi). */
internal data class SelphyPrintRequest(
    val filePath: String,
    val transport: String,
    val copies: Int,
    val paperSize: String,
    val look: SelphyLookSettings,
    val result: MethodChannel.Result,
) {
    val isWifi: Boolean get() = transport == "wifi"

    companion object {
        fun fromChannelArgs(
            arguments: Any?,
            result: MethodChannel.Result,
        ): SelphyPrintRequest? {
            @Suppress("UNCHECKED_CAST")
            val args = arguments as? Map<String, Any?> ?: emptyMap()
            val filePath = args["filePath"] as? String
            if (filePath == null) {
                result.error("INVALID_ARG", "filePath is required", null)
                return null
            }
            return SelphyPrintRequest(
                filePath = filePath,
                transport = (args["transport"] as? String) ?: "usb",
                copies = (args["copies"] as? Number)?.toInt() ?: 1,
                paperSize = (args["paperSize"] as? String) ?: "4x6",
                look =
                    SelphyLookSettings(
                        filter = (args["filter"] as? String) ?: "Off",
                        brightness = (args["brightness"] as? Number)?.toInt() ?: 0,
                        bordered = args["bordered"] as? Boolean ?: false,
                    ),
                result = result,
            )
        }
    }
}

/** Canvas geometry + look settings for [SelphyImageProcessor]. */
internal data class SelphyResizeInput(
    val sourcePath: String,
    val jpegSize: Point,
    val printable: Rect,
    val look: SelphyLookSettings,
)
