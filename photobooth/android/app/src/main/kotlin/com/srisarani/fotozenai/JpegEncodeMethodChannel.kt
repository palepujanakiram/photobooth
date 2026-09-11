package com.srisarani.fotozenai

import android.graphics.Bitmap
import android.graphics.Bitmap.CompressFormat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Hardware JPEG encode for Classic print sheets.
 *
 * Dart `image` encodeJpg of a 1200×1800 RGBA sheet is 15–30s on 4GB Amlogic
 * TV boxes and is what staff see as "Building your strip…".
 */
object JpegEncodeMethodChannel {
    private const val CHANNEL_NAME = "photobooth/jpeg_encode"

    fun register(messenger: BinaryMessenger) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            if (call.method != "encodeRgba") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val rgba = call.argument<ByteArray>("rgba")
            val width = call.argument<Int>("width") ?: 0
            val height = call.argument<Int>("height") ?: 0
            val quality = (call.argument<Int>("quality") ?: 92).coerceIn(1, 100)
            if (rgba == null || width <= 0 || height <= 0) {
                result.success(null)
                return@setMethodCallHandler
            }
            if (rgba.size < width * height * 4) {
                result.success(null)
                return@setMethodCallHandler
            }
            result.success(encode(rgba, width, height, quality))
        }
    }

    fun register(flutterEngine: FlutterEngine) {
        register(flutterEngine.dartExecutor.binaryMessenger)
    }

    private fun encode(
        rgba: ByteArray,
        width: Int,
        height: Int,
        quality: Int,
    ): ByteArray? {
        val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        return try {
            val pixels = IntArray(width * height)
            var i = 0
            var p = 0
            while (p < pixels.size) {
                val r = rgba[i].toInt() and 0xFF
                val g = rgba[i + 1].toInt() and 0xFF
                val b = rgba[i + 2].toInt() and 0xFF
                val a = rgba[i + 3].toInt() and 0xFF
                pixels[p] = (a shl 24) or (r shl 16) or (g shl 8) or b
                i += 4
                p++
            }
            bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
            val out = ByteArrayOutputStream()
            if (!bitmap.compress(CompressFormat.JPEG, quality, out)) return null
            out.toByteArray()
        } catch (_: RuntimeException) {
            null
        } finally {
            bitmap.recycle()
        }
    }
}
