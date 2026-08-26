package com.srisarani.fotozenai

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.srisarani.fotozenai.dnp.DnpImageProcessor
import com.srisarani.fotozenai.dnp.DnpPrepareBitmapOptions
import com.srisarani.fotozenai.dnp.DnpPrintImage
import com.srisarani.fotozenai.dnp.DnpPrintJob
import com.srisarani.fotozenai.dnp.DnpPrintProgressEmitter
import com.srisarani.fotozenai.dnp.DnpPrintSize
import com.srisarani.fotozenai.dnp.DnpPrinterException
import com.srisarani.fotozenai.dnp.DnpUsbPrinter
import com.srisarani.fotozenai.dnp.DnpWifiNetworkBinder
import com.srisarani.fotozenai.dnp.PrintProgressCallback
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Native DNP DS-RX1(S)HS USB printing for Android kiosk builds. */
object DnpUsbMethodChannel {
    private const val TAG = "DnpUsbMethodChannel"

    const val METHOD_CHANNEL = "com.srisarani.fotozenai/dnp_usb"
    const val PROGRESS_CHANNEL = "com.srisarani.fotozenai/dnp_print_progress"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private lateinit var appContext: Context
    private lateinit var usbPrinter: DnpUsbPrinter

    private var printProgressSink: EventChannel.EventSink? = null
    private var permissionReceiverRegistered = false
    private var wifiNetworkBinder: DnpWifiNetworkBinder? = null
    private var printProgressEmitter: DnpPrintProgressEmitter? = null

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != DnpUsbPrinter.ACTION_USB_PERMISSION) return
            // A missing extra is the signature of an immutable PendingIntent swallowing the
            // system's fill-in — it used to read as a plain denial and cost the print.
            // Distinguish the two so a repeat report is diagnosable from logcat alone.
            val hasExtra = intent.hasExtra(UsbManager.EXTRA_PERMISSION_GRANTED)
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            if (!hasExtra) {
                Log.e(
                    TAG,
                    "USB permission result arrived with no EXTRA_PERMISSION_GRANTED - the " +
                        "PendingIntent is not mutable. Treating as denied; print will fail.",
                )
            } else {
                Log.i(TAG, "USB permission ${if (granted) "GRANTED" else "DENIED"} by user")
            }
            DnpUsbPrinter.pendingPermissionCallback?.invoke(granted)
            DnpUsbPrinter.pendingPermissionCallback = null
        }
    }

    fun register(flutterEngine: FlutterEngine, context: Context) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        val usbManager = appContext.getSystemService(Context.USB_SERVICE) as UsbManager
        usbPrinter = DnpUsbPrinter(appContext, usbManager)
        wifiNetworkBinder = DnpWifiNetworkBinder(appContext, mainHandler)
        printProgressEmitter = DnpPrintProgressEmitter(mainHandler) { printProgressSink }

        EventChannel(messenger, PROGRESS_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    printProgressSink = events
                }

                override fun onCancel(arguments: Any?) {
                    printProgressSink = null
                }
            },
        )

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsbHost" -> result.success(hasUsbHost(context))
                "probeDevice" -> result.success(usbPrinter.findDevice() != null)
                "prepareWifiNetwork" -> prepareWifiNetwork(result)
                "requestPermission" -> requestUsbPermission(result)
                "disconnect" -> disconnectUsb(result)
                "getPrinterStatus" -> getPrinterStatus(result)
                "print" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath == null) {
                        result.error("INVALID_ARG", "filePath is required", null)
                    } else {
                        val copies = call.argument<Int>("copies") ?: 1
                        val paperSize = call.argument<String>("paperSize") ?: "4x6"
                        val printSize = call.argument<String>("printSize")
                        startUsbPrint(filePath, copies, paperSize, printSize, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onResume(context: Context) {
        if (permissionReceiverRegistered) return
        val filter = IntentFilter(DnpUsbPrinter.ACTION_USB_PERMISSION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(usbPermissionReceiver, filter)
        }
        permissionReceiverRegistered = true
    }

    fun onDestroy() {
        if (permissionReceiverRegistered) {
            try {
                appContext.unregisterReceiver(usbPermissionReceiver)
            } catch (_: Exception) {
            }
            permissionReceiverRegistered = false
        }
        wifiNetworkBinder?.release()
        usbPrinter.disconnect()
        ioExecutor.shutdownNow()
    }

    private fun requestUsbPermission(result: MethodChannel.Result) {
        val dev = usbPrinter.findDevice()
        if (dev == null) {
            Log.w(
                TAG,
                "No DNP printer on USB. Devices seen: ${usbPrinter.describeAttachedDevices()}",
            )
            mainHandler.post {
                result.error(
                    "NO_PRINTER",
                    "No DNP DS-RX1 printer found via USB. Connect the printer and tap Allow if prompted.",
                    null,
                )
            }
            return
        }

        fun onGranted(granted: Boolean) {
            if (!granted) {
                Log.w(TAG, "USB print aborted - permission not granted for ${usbPrinter.describe(dev)}")
                mainHandler.post {
                    result.error(
                        "PERMISSION_DENIED",
                        "USB permission denied. Reconnect the printer and try again.",
                        null,
                    )
                }
                return
            }
            ioExecutor.execute {
                try {
                    val info = usbPrinter.connect(dev)
                    val code = usbPrinter.queryLiveStatus()
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "name" to info,
                                "transport" to "usb",
                                "status" to code,
                                "statusLabel" to usbPrinter.statusLabel(code),
                                "ready" to usbPrinter.isReadyStatus(code),
                            ),
                        )
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "USB connect failed for ${usbPrinter.describe(dev)}", e)
                    mainHandler.post {
                        result.error("CONNECT_FAILED", e.message ?: "USB connect failed", null)
                    }
                }
            }
        }

        if (usbPrinter.hasPermission(dev)) {
            onGranted(true)
        } else {
            usbPrinter.requestPermission(dev, ::onGranted)
        }
    }

    private fun disconnectUsb(result: MethodChannel.Result) {
        ioExecutor.execute {
            try {
                usbPrinter.disconnect()
                mainHandler.post { result.success(null) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("DISCONNECT_FAILED", e.message ?: "USB disconnect failed", null)
                }
            }
        }
    }

    private fun getPrinterStatus(result: MethodChannel.Result) {
        if (!usbPrinter.isConnected) {
            result.error("NO_PRINTER", "Printer not connected", null)
            return
        }
        ioExecutor.execute {
            try {
                val code = usbPrinter.queryLiveStatus()
                mainHandler.post {
                    result.success(
                        mapOf(
                            "name" to usbPrinter.displayName,
                            "transport" to "usb",
                            "status" to code,
                            "statusLabel" to usbPrinter.statusLabel(code),
                            "ready" to usbPrinter.isReadyStatus(code),
                        ),
                    )
                }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("STATUS_ERROR", e.message ?: "Could not read printer status", null)
                }
            }
        }
    }

    private fun prepareWifiNetwork(result: MethodChannel.Result) {
        wifiNetworkBinder?.bind { bound ->
            mainHandler.post { result.success(bound) }
        } ?: mainHandler.post { result.success(false) }
    }

    private fun startUsbPrint(
        filePath: String,
        copies: Int,
        paperSize: String,
        networkPrintSize: String?,
        result: MethodChannel.Result,
    ) {
        if (!usbPrinter.isConnected) {
            mainHandler.post {
                result.error("NO_PRINTER", "Printer not ready. Reconnect USB and try again.", null)
            }
            return
        }

        ioExecutor.execute {
            try {
                val memoryEfficient = memoryEfficientMode()
                if (memoryEfficient) System.gc()
                emitPrintProgress("prepare", "Preparing photo for print…", 0.05)
                val size = networkPrintSize?.let { DnpPrintSize.fromNetworkPrintSize(it) }
                    ?: DnpPrintSize.fromLabel(paperSize)
                val bitmap = DnpImageProcessor.prepareBitmap(
                    DnpPrepareBitmapOptions(
                        sourcePath = filePath,
                        size = size,
                        memoryEfficient = memoryEfficient,
                        networkPrintSize = networkPrintSize,
                    ),
                )
                emitPrintProgress(
                    "prepare",
                    "Photo prepared (${bitmap.width}×${bitmap.height})",
                    0.18,
                )

                emitPrintProgress("convert", "Reading pixel data…", 0.20)
                val pixels = DnpImageProcessor.bitmapToPixels(bitmap, mirrorHorizontal = true)
                val w = bitmap.width
                val h = bitmap.height
                bitmap.recycle()

                usbPrinter.print(
                    DnpPrintJob(
                        image = DnpPrintImage(pixels, w, h),
                        size = size,
                        copies = copies,
                    ),
                    onProgress = printProgressReporter,
                )
                mainHandler.post {
                    result.success("Print completed ($copies ${if (copies == 1) "copy" else "copies"})")
                }
            } catch (e: DnpPrinterException) {
                mainHandler.post { result.error("PRINT_ERROR", e.message, null) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("PRINT_ERROR", "Print failed: ${e.message}", null)
                }
            }
        }
    }

    private fun emitPrintProgress(stage: String, message: String, progress: Double?) {
        printProgressEmitter?.emit(stage, message, progress)
    }

    private val printProgressReporter: PrintProgressCallback = { stage, message, progress ->
        emitPrintProgress(stage, message, progress)
    }

    private fun hasUsbHost(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)

    private fun memoryEfficientMode(): Boolean {
        val pm = appContext.packageManager
        if (pm.hasSystemFeature(PackageManager.FEATURE_LEANBACK)) return true
        val am = appContext.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        return am.isLowRamDevice || am.memoryClass <= 384
    }
}
