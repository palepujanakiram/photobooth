package com.srisarani.fotozenai.selphy

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import jp.co.canon.android.print.selphy.usbsdk.CanonPermissionRequestCallback
import jp.co.canon.android.print.selphy.usbsdk.CanonPreparationCallback
import jp.co.canon.android.print.selphy.usbsdk.CanonUsbManager
import java.util.concurrent.atomic.AtomicBoolean
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintDevice as UsbPrintDevice
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintJob as UsbPrintJob

/** USB discovery, permission, and print for Canon Selphy. */
internal class SelphyUsbSession(
    private val appContext: Context,
    private val sdkContext: () -> Context,
    private val mainHandler: Handler,
) {
    private val logTag = "SelphyUsb"
    var cachedDevice: UsbPrintDevice? = null
        private set

    fun clear() {
        cachedDevice = null
    }

    fun probeDevice(result: MethodChannel.Result) {
        fun check() {
            try {
                val printers = printerList()
                mainHandler.post { result.success(printers.isNotEmpty()) }
            } catch (e: SecurityException) {
                CanonUsbManager.prepareToGetPrinterList(
                    appContext,
                    object : CanonPreparationCallback() {
                        override fun onSuccess() {
                            try {
                                val printers = printerList()
                                mainHandler.post { result.success(printers.isNotEmpty()) }
                            } catch (ex: Exception) {
                                Log.d(logTag, "probe after prepare failed: ${ex.message}")
                                mainHandler.post { result.success(false) }
                            }
                        }

                        override fun onFailure() {
                            mainHandler.post { result.success(false) }
                        }
                    },
                )
            } catch (e: Exception) {
                Log.d(logTag, "probe failed: ${e.message}")
                mainHandler.post { result.success(false) }
            }
        }
        check()
    }

    fun requestPermission(result: MethodChannel.Result) {
        fun findAndRequestPermission() {
            val printers = printerList()
            if (printers.isEmpty()) {
                mainHandler.post {
                    result.error("NO_PRINTER", "No Canon Selphy printer found via USB", null)
                }
                return
            }

            val device = printers[0]
            if (CanonUsbManager.hasPermission(appContext, device)) {
                cachedDevice = device
                mainHandler.post { result.success("Printer ready: ${device.printerName}") }
                return
            }

            val requested =
                CanonUsbManager.requestPermission(
                    appContext,
                    device,
                    object : CanonPermissionRequestCallback() {
                        override fun onReceivePermissionGranted(
                            dev: UsbPrintDevice,
                            granted: Boolean,
                        ) {
                            mainHandler.post {
                                if (granted) {
                                    cachedDevice = dev
                                    result.success("Printer ready: ${dev.printerName}")
                                } else {
                                    result.error(
                                        "PERMISSION_DENIED",
                                        "USB permission denied for Canon Selphy",
                                        null,
                                    )
                                }
                            }
                        }
                    },
                )

            if (!requested) {
                mainHandler.post {
                    result.error(
                        "PERMISSION_REQUEST_FAILED",
                        "Could not request USB permission for Canon Selphy",
                        null,
                    )
                }
            }
        }

        try {
            findAndRequestPermission()
        } catch (e: SecurityException) {
            CanonUsbManager.prepareToGetPrinterList(
                appContext,
                object : CanonPreparationCallback() {
                    override fun onSuccess() = findAndRequestPermission()

                    override fun onFailure() {
                        mainHandler.post {
                            result.error(
                                "PREPARE_FAILED",
                                "Failed to access USB for Canon Selphy",
                                null,
                            )
                        }
                    }
                },
            )
        }
    }

    fun startPrint(request: SelphyPrintRequest) {
        val device = cachedDevice
        if (device == null || !CanonUsbManager.hasPermission(appContext, device)) {
            mainHandler.post {
                request.result.error("NO_PERMISSION", "Selphy USB printer not ready", null)
            }
            return
        }

        val resizedFile =
            SelphyPrintSupport.preparePrintFile(appContext, request, mainHandler) ?: return

        val job = UsbPrintJob()
        job.setPrintConfiguration(UsbPrintJob.Configuration.Copies, request.copies)
        val uri = Uri.fromFile(resizedFile)
        if (!job.setPrintFile(uri, sdkContext())) {
            resizedFile.delete()
            mainHandler.post {
                request.result.error(
                    "FILE_ERROR",
                    "Selphy rejected the image. Check the paper cassette.",
                    null,
                )
            }
            return
        }

        val state =
            SelphyJobFinishState(
                mainHandler = mainHandler,
                result = request.result,
                resolved = AtomicBoolean(false),
                resizedFile = resizedFile,
            )
        val started = device.print(job, SelphyPrintCallbacks.usb(state, logTag))

        if (!started) {
            SelphyPrintSupport.failStart(state, "Failed to start Selphy USB print")
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun printerList(): List<UsbPrintDevice> = CanonUsbManager.getPrinterList(appContext) as? List<UsbPrintDevice> ?: emptyList()
}
