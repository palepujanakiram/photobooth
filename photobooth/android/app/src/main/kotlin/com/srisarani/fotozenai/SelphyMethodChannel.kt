package com.srisarani.fotozenai

import android.content.Context
import android.net.Uri
import android.os.Handler
import android.os.Looper
import com.srisarani.fotozenai.dnp.DnpWifiNetworkBinder
import com.srisarani.fotozenai.selphy.SelphyImageProcessor
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import jp.co.canon.android.print.selphy.usbsdk.CanonPermissionRequestCallback
import jp.co.canon.android.print.selphy.usbsdk.CanonPreparationCallback
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintCallback as UsbPrintCallback
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintDevice as UsbPrintDevice
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintJob as UsbPrintJob
import jp.co.canon.android.print.selphy.usbsdk.CanonPrintSizeInfo as UsbPrintSizeInfo
import jp.co.canon.android.print.selphy.usbsdk.CanonPrinterAccessoryInfo as UsbAccessoryInfo
import jp.co.canon.android.print.selphy.usbsdk.CanonPrinterStatus as UsbPrinterStatus
import jp.co.canon.android.print.selphy.usbsdk.CanonUsbManager
import jp.co.canon.android.print.selphy.wifisdk.CanonDiscoveryCallback
import jp.co.canon.android.print.selphy.wifisdk.CanonPrintCallback as WifiPrintCallback
import jp.co.canon.android.print.selphy.wifisdk.CanonPrintDevice as WifiPrintDevice
import jp.co.canon.android.print.selphy.wifisdk.CanonPrintJob as WifiPrintJob
import jp.co.canon.android.print.selphy.wifisdk.CanonPrinterStatus as WifiPrinterStatus
import java.util.concurrent.atomic.AtomicBoolean

/** Native Canon Selphy CP1500 USB / Wi‑Fi printing (official Selphy SDKs). */
object SelphyMethodChannel {
    const val METHOD_CHANNEL = "com.srisarani.fotozenai/selphy"

    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var appContext: Context
    /** Activity/context used for SDK discovery & print (prefer Activity over Application). */
    private var hostContext: Context? = null
    private var wifiNetworkBinder: DnpWifiNetworkBinder? = null

    private var cachedUsbDevice: UsbPrintDevice? = null
    private var cachedWifiDevice: WifiPrintDevice? = null

    fun register(flutterEngine: FlutterEngine, context: Context) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        hostContext = context
        wifiNetworkBinder = DnpWifiNetworkBinder(appContext, mainHandler)

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "probeUsb" -> probeUsbDevice(result)
                "requestPermission" -> requestUsbPermission(result)
                "discoverWifi" -> discoverWifiPrinter(result)
                "releaseWifi" -> {
                    releaseWifiBinding()
                    result.success(null)
                }
                "resetSession" -> {
                    cachedUsbDevice = null
                    cachedWifiDevice = null
                    releaseWifiBinding()
                    result.success(null)
                }
                "print" -> handlePrint(call.arguments, result)
                else -> result.notImplemented()
            }
        }
    }

    fun onDestroy() {
        releaseWifiBinding()
        cachedUsbDevice = null
        cachedWifiDevice = null
        hostContext = null
    }

    private fun sdkContext(): Context = hostContext ?: appContext

    private fun handlePrint(arguments: Any?, result: MethodChannel.Result) {
        @Suppress("UNCHECKED_CAST")
        val args = arguments as? Map<String, Any?> ?: emptyMap()
        val filePath = args["filePath"] as? String
        if (filePath == null) {
            result.error("INVALID_ARG", "filePath is required", null)
            return
        }
        val transport = (args["transport"] as? String) ?: "usb"
        val copies = (args["copies"] as? Number)?.toInt() ?: 1
        val paperSize = (args["paperSize"] as? String) ?: "4x6"
        val filter = (args["filter"] as? String) ?: "Off"
        val brightness = (args["brightness"] as? Number)?.toInt() ?: 0
        val bordered = args["bordered"] as? Boolean ?: false
        if (transport == "wifi") {
            startWifiPrint(filePath, copies, paperSize, filter, brightness, bordered, result)
        } else {
            startUsbPrint(filePath, copies, paperSize, filter, brightness, bordered, result)
        }
    }

    private fun releaseWifiBinding() {
        try {
            WifiPrintDevice.stopDiscovery()
        } catch (_: Exception) {
        }
        wifiNetworkBinder?.release()
    }

    private fun probeUsbDevice(result: MethodChannel.Result) {
        fun check() {
            try {
                @Suppress("UNCHECKED_CAST")
                val printers =
                    CanonUsbManager.getPrinterList(appContext) as? List<UsbPrintDevice> ?: emptyList()
                mainHandler.post { result.success(printers.isNotEmpty()) }
            } catch (e: SecurityException) {
                CanonUsbManager.prepareToGetPrinterList(
                    appContext,
                    object : CanonPreparationCallback() {
                        override fun onSuccess() {
                            try {
                                @Suppress("UNCHECKED_CAST")
                                val printers =
                                    CanonUsbManager.getPrinterList(appContext) as? List<UsbPrintDevice>
                                        ?: emptyList()
                                mainHandler.post { result.success(printers.isNotEmpty()) }
                            } catch (_: Exception) {
                                mainHandler.post { result.success(false) }
                            }
                        }

                        override fun onFailure() {
                            mainHandler.post { result.success(false) }
                        }
                    },
                )
            } catch (_: Exception) {
                mainHandler.post { result.success(false) }
            }
        }
        check()
    }

    private fun requestUsbPermission(result: MethodChannel.Result) {
        fun findAndRequestPermission() {
            @Suppress("UNCHECKED_CAST")
            val printers =
                CanonUsbManager.getPrinterList(appContext) as? List<UsbPrintDevice> ?: emptyList()

            if (printers.isEmpty()) {
                mainHandler.post {
                    result.error("NO_PRINTER", "No Canon Selphy printer found via USB", null)
                }
                return
            }

            val device = printers[0]
            if (CanonUsbManager.hasPermission(appContext, device)) {
                cachedUsbDevice = device
                mainHandler.post { result.success("Printer ready: ${device.printerName}") }
                return
            }

            val requested = CanonUsbManager.requestPermission(
                appContext,
                device,
                object : CanonPermissionRequestCallback() {
                    override fun onReceivePermissionGranted(dev: UsbPrintDevice, granted: Boolean) {
                        mainHandler.post {
                            if (granted) {
                                cachedUsbDevice = dev
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

    private fun discoverWifiPrinter(result: MethodChannel.Result) {
        val binder = wifiNetworkBinder
        if (binder == null) {
            result.error("WIFI_BIND_FAILED", "Wi-Fi binder not initialized", null)
            return
        }
        binder.bind { bound ->
            if (!bound) {
                result.error(
                    "WIFI_BIND_FAILED",
                    "Could not route to the Selphy Wi-Fi network",
                    null,
                )
                return@bind
            }
            startWifiDiscovery(result)
        }
    }

    private fun startWifiDiscovery(result: MethodChannel.Result) {
        val resolved = AtomicBoolean(false)
        val started = WifiPrintDevice.startDiscovery(
            sdkContext(),
            object : CanonDiscoveryCallback() {
                override fun onFoundPrinter(device: WifiPrintDevice) {
                    if (resolved.compareAndSet(false, true)) {
                        cachedWifiDevice = device
                        try {
                            WifiPrintDevice.stopDiscovery()
                        } catch (_: Exception) {
                        }
                        mainHandler.post {
                            result.success(
                                "Printer ready: ${device.printerName} (${device.printerIpAddress})",
                            )
                        }
                    }
                }

                override fun onFinished(found: Boolean) {
                    if (resolved.compareAndSet(false, true)) {
                        mainHandler.post {
                            result.error(
                                "NO_PRINTER",
                                "No Canon Selphy printer found on Wi-Fi",
                                null,
                            )
                        }
                    }
                }
            },
        )

        if (!started && resolved.compareAndSet(false, true)) {
            mainHandler.post {
                result.error(
                    "DISCOVERY_FAILED",
                    "Could not start Selphy Wi-Fi discovery",
                    null,
                )
            }
        }
    }

    private fun startUsbPrint(
        filePath: String,
        copies: Int,
        paperSize: String,
        filter: String,
        brightness: Int,
        bordered: Boolean,
        result: MethodChannel.Result,
    ) {
        val device = cachedUsbDevice
        if (device == null || !CanonUsbManager.hasPermission(appContext, device)) {
            mainHandler.post {
                result.error("NO_PERMISSION", "Selphy USB printer not ready", null)
            }
            return
        }

        val sizeInfo = sizeInfoFor(paperSize)
        val resizedFile = try {
            SelphyImageProcessor.resizeForPrinting(
                appContext,
                filePath,
                sizeInfo.printableJpegSize,
                sizeInfo.printableArea,
                filter,
                brightness,
                bordered,
            )
        } catch (e: Exception) {
            mainHandler.post {
                result.error("IMAGE_ERROR", "Failed to prepare image: ${e.message}", null)
            }
            return
        }

        val job = UsbPrintJob()
        job.setPrintConfiguration(UsbPrintJob.Configuration.Copies, copies)
        val uri = Uri.fromFile(resizedFile)
        if (!job.setPrintFile(uri, sdkContext())) {
            resizedFile.delete()
            mainHandler.post {
                result.error(
                    "FILE_ERROR",
                    "Selphy rejected the image. Check the paper cassette.",
                    null,
                )
            }
            return
        }

        val resolved = AtomicBoolean(false)
        val started = device.print(
            job,
            object : UsbPrintCallback() {
                override fun onChangedJobStatus(job: UsbPrintJob) {
                    if (job.isFinished && resolved.compareAndSet(false, true)) {
                        resizedFile.delete()
                        val statusMsg = job.status.toString()
                        mainHandler.post {
                            if (statusMsg.contains("Error", ignoreCase = true)) {
                                result.error("PRINT_ERROR", "Print failed: $statusMsg", null)
                            } else {
                                result.success("Print completed: $statusMsg")
                            }
                        }
                    }
                }

                override fun onChangedPrinterStatus(job: UsbPrintJob, status: UsbPrinterStatus) {
                    // no-op
                }
            },
        )

        if (!started && resolved.compareAndSet(false, true)) {
            resizedFile.delete()
            mainHandler.post {
                result.error("PRINT_START_FAILED", "Failed to start Selphy USB print", null)
            }
        }
    }

    private fun startWifiPrint(
        filePath: String,
        copies: Int,
        paperSize: String,
        filter: String,
        brightness: Int,
        bordered: Boolean,
        result: MethodChannel.Result,
    ) {
        val device = cachedWifiDevice
        if (device == null) {
            mainHandler.post {
                result.error("NO_PRINTER", "Selphy Wi-Fi printer not ready", null)
            }
            return
        }

        val sizeInfo = sizeInfoFor(paperSize)
        val resizedFile = try {
            SelphyImageProcessor.resizeForPrinting(
                appContext,
                filePath,
                sizeInfo.printableJpegSize,
                sizeInfo.printableArea,
                filter,
                brightness,
                bordered,
            )
        } catch (e: Exception) {
            mainHandler.post {
                result.error("IMAGE_ERROR", "Failed to prepare image: ${e.message}", null)
            }
            return
        }

        val job = WifiPrintJob()
        job.setPrintConfiguration(WifiPrintJob.Configuration.Copies, copies)
        job.setPrintFile(Uri.fromFile(resizedFile), sdkContext())

        val resolved = AtomicBoolean(false)
        val started = device.print(
            job,
            sdkContext(),
            object : WifiPrintCallback() {
                override fun onChangedJobStatus(job: WifiPrintJob) {
                    if (job.isFinished && resolved.compareAndSet(false, true)) {
                        resizedFile.delete()
                        val statusMsg = job.status.toString()
                        mainHandler.post {
                            if (statusMsg.contains("Error", ignoreCase = true)) {
                                result.error("PRINT_ERROR", "Print failed: $statusMsg", null)
                            } else {
                                result.success("Print completed: $statusMsg")
                            }
                        }
                    }
                }

                override fun onChangedPrinterStatus(job: WifiPrintJob, status: WifiPrinterStatus) {
                    // no-op
                }
            },
        )

        if (!started && resolved.compareAndSet(false, true)) {
            resizedFile.delete()
            mainHandler.post {
                result.error("PRINT_START_FAILED", "Failed to start Selphy Wi-Fi print", null)
            }
        }
    }

    private fun sizeInfoFor(paperSize: String): UsbPrintSizeInfo {
        val paperType = when (paperSize) {
            "L-size" -> UsbAccessoryInfo.PaperCassetteStatus.L
            "Card" -> UsbAccessoryInfo.PaperCassetteStatus.Card
            else -> UsbAccessoryInfo.PaperCassetteStatus.Post
        }
        return UsbPrintSizeInfo.getPrintSizeInfo(paperType)
    }
}
