package com.srisarani.fotozenai.selphy

import android.content.Context
import android.os.Handler
import io.flutter.plugin.common.MethodChannel
import java.io.File
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintSizeInfo as UsbPrintSizeInfo
import jp.co.canon.android.print.selphy.usbsdk.CanonPrinterAccessoryInfo as UsbAccessoryInfo

/** Shared helpers for USB/Wi‑Fi Selphy print jobs. */
internal object SelphyPrintSupport {
    fun sizeInfoFor(paperSize: String): UsbPrintSizeInfo {
        val paperType =
            when (paperSize) {
                "L-size" -> UsbAccessoryInfo.PaperCassetteStatus.L
                "Card" -> UsbAccessoryInfo.PaperCassetteStatus.Card
                else -> UsbAccessoryInfo.PaperCassetteStatus.Post
            }
        return UsbPrintSizeInfo.getPrintSizeInfo(paperType)
    }

    fun preparePrintFile(
        context: Context,
        request: SelphyPrintRequest,
        mainHandler: Handler,
    ): File? {
        val sizeInfo = sizeInfoFor(request.paperSize)
        return try {
            SelphyImageProcessor.resizeForPrinting(
                context,
                SelphyResizeInput(
                    sourcePath = request.filePath,
                    jpegSize = sizeInfo.printableJpegSize,
                    printable = sizeInfo.printableArea,
                    look = request.look,
                ),
            )
        } catch (e: Exception) {
            mainHandler.post {
                request.result.error(
                    "IMAGE_ERROR",
                    "Failed to prepare image: ${e.message}",
                    null,
                )
            }
            null
        }
    }

    fun finishJob(
        state: SelphyJobFinishState,
        statusMessage: String,
    ) {
        if (!state.resolved.compareAndSet(false, true)) return
        state.resizedFile.delete()
        state.mainHandler.post {
            if (statusMessage.contains("Error", ignoreCase = true)) {
                state.result.error("PRINT_ERROR", "Print failed: $statusMessage", null)
            } else {
                state.result.success("Print completed: $statusMessage")
            }
        }
    }

    fun failStart(
        state: SelphyJobFinishState,
        message: String,
    ) {
        if (!state.resolved.compareAndSet(false, true)) return
        state.resizedFile.delete()
        state.mainHandler.post {
            state.result.error("PRINT_START_FAILED", message, null)
        }
    }
}
