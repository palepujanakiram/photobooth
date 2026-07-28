package com.srisarani.fotozenai

import android.app.ActivityManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbManager
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.srisarani.fotozenai.dnp.DnpImageProcessor
import com.srisarani.fotozenai.dnp.DnpPrintSize
import com.srisarani.fotozenai.dnp.DnpPrinterException
import com.srisarani.fotozenai.dnp.DnpUsbPrinter
import com.srisarani.fotozenai.dnp.PrintProgressCallback
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Native DNP DS-RX1(S)HS USB printing for Android kiosk builds. */
object DnpUsbMethodChannel {
    const val METHOD_CHANNEL = "com.srisarani.fotozenai/dnp_usb"
    const val PROGRESS_CHANNEL = "com.srisarani.fotozenai/dnp_print_progress"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private lateinit var appContext: Context
    private lateinit var usbPrinter: DnpUsbPrinter

    private var printProgressSink: EventChannel.EventSink? = null
    private var permissionReceiverRegistered = false

    private var connectivityManager: ConnectivityManager? = null
    private var wifiNetworkCallback: ConnectivityManager.NetworkCallback? = null

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != DnpUsbPrinter.ACTION_USB_PERMISSION) return
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
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
        try {
            connectivityManager?.bindProcessToNetwork(null)
            wifiNetworkCallback?.let { connectivityManager?.unregisterNetworkCallback(it) }
        } catch (_: Exception) {
        }
        usbPrinter.disconnect()
        ioExecutor.shutdownNow()
    }

    private fun requestUsbPermission(result: MethodChannel.Result) {
        val dev = usbPrinter.findDevice()
        if (dev == null) {
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
        bindToWifiNetwork { bound ->
            mainHandler.post { result.success(bound) }
        }
    }

    private fun bindToWifiNetwork(onResult: (Boolean) -> Unit) {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
        connectivityManager = cm

        val bound = cm.boundNetworkForProcess
        if (bound != null) {
            val caps = cm.getNetworkCapabilities(bound)
            if (caps != null && caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) {
                onResult(true)
                return
            }
        }

        val request = NetworkRequest.Builder()
            .addTransportType(NetworkCapabilities.TRANSPORT_WIFI)
            .build()

        val resolved = AtomicBoolean(false)
        val timeout = Runnable {
            if (resolved.compareAndSet(false, true)) onResult(false)
        }

        val callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                val ok = cm.bindProcessToNetwork(network)
                if (resolved.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeout)
                    mainHandler.post { onResult(ok) }
                }
            }

            override fun onUnavailable() {
                if (resolved.compareAndSet(false, true)) {
                    mainHandler.removeCallbacks(timeout)
                    mainHandler.post { onResult(false) }
                }
            }
        }
        wifiNetworkCallback = callback
        cm.requestNetwork(request, callback)
        mainHandler.postDelayed(timeout, 8000)
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
                    filePath,
                    size,
                    filter = "Off",
                    brightness = 0,
                    bordered = false,
                    memoryEfficient = memoryEfficient,
                    networkPrintSize = networkPrintSize,
                )
                emitPrintProgress(
                    "prepare",
                    "Photo prepared (${bitmap.width}×${bitmap.height})",
                    0.18,
                )

                emitPrintProgress("convert", "Reading pixel data…", 0.20)
                val pixels = DnpImageProcessor.bitmapToPixels(bitmap)
                val w = bitmap.width
                val h = bitmap.height
                bitmap.recycle()

                usbPrinter.print(
                    pixels,
                    w,
                    h,
                    size,
                    copies,
                    matte = false,
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

    private data class PendingProgress(
        val stage: String,
        val message: String,
        val progress: Double?,
    )

    private var lastEmittedProgressStage: String? = null
    private var lastProgressEmitMs = 0L
    private var pendingProgress: PendingProgress? = null
    private var progressFlushRunnable: Runnable? = null

    private fun emitPrintProgress(stage: String, message: String, progress: Double?) {
        mainHandler.post {
            val now = System.currentTimeMillis()
            val stageChanged = stage != lastEmittedProgressStage
            val terminal = stage == "complete"

            if (stageChanged || terminal || now - lastProgressEmitMs >= 150) {
                progressFlushRunnable?.let { mainHandler.removeCallbacks(it) }
                progressFlushRunnable = null
                pendingProgress = null
                dispatchPrintProgress(stage, message, progress)
                return@post
            }

            pendingProgress = PendingProgress(stage, message, progress)
            if (progressFlushRunnable != null) return@post

            val delay = (150 - (now - lastProgressEmitMs)).coerceAtLeast(0)
            progressFlushRunnable = Runnable {
                progressFlushRunnable = null
                val pending = pendingProgress ?: return@Runnable
                pendingProgress = null
                dispatchPrintProgress(pending.stage, pending.message, pending.progress)
            }
            mainHandler.postDelayed(progressFlushRunnable!!, delay.toLong())
        }
    }

    private fun dispatchPrintProgress(stage: String, message: String, progress: Double?) {
        lastEmittedProgressStage = stage
        lastProgressEmitMs = System.currentTimeMillis()
        printProgressSink?.success(
            mapOf(
                "stage" to stage,
                "message" to message,
                "progress" to progress,
            ),
        )
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
