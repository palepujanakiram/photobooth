package com.srisarani.fotozenai

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.srisarani.fotozenai.receipt.ReceiptPrinterException
import com.srisarani.fotozenai.receipt.ReceiptUsbPrinter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Native Posiflow / ESC/POS USB receipt printing for Android kiosk builds. */
object ReceiptUsbMethodChannel {
    const val METHOD_CHANNEL = "com.srisarani.fotozenai/receipt_usb"

    private val mainHandler = Handler(Looper.getMainLooper())
    private val ioExecutor = Executors.newSingleThreadExecutor()

    private lateinit var appContext: Context
    private lateinit var usbPrinter: ReceiptUsbPrinter

    private var permissionReceiverRegistered = false

    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action != ReceiptUsbPrinter.ACTION_USB_PERMISSION) return
            val granted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
            ReceiptUsbPrinter.pendingPermissionCallback?.invoke(granted)
            ReceiptUsbPrinter.pendingPermissionCallback = null
        }
    }

    fun register(flutterEngine: FlutterEngine, context: Context) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }

    fun register(messenger: BinaryMessenger, context: Context) {
        appContext = context.applicationContext
        val usbManager = appContext.getSystemService(Context.USB_SERVICE) as UsbManager
        usbPrinter = ReceiptUsbPrinter(appContext, usbManager)

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasUsbHost" -> result.success(hasUsbHost(context))
                "probeDevice" -> result.success(usbPrinter.findDevice() != null)
                "requestPermission" -> requestUsbPermission(result)
                "sendEscPos" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    if (bytes == null || bytes.isEmpty()) {
                        result.error("INVALID_ARG", "bytes is required", null)
                    } else {
                        sendEscPos(bytes, result)
                    }
                }
                "sendEscPosFile" -> {
                    val filePath = call.argument<String>("filePath")
                    if (filePath.isNullOrBlank()) {
                        result.error("INVALID_ARG", "filePath is required", null)
                    } else {
                        sendEscPosFile(filePath, result)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun onResume(context: Context) {
        if (permissionReceiverRegistered) return
        val filter = IntentFilter(ReceiptUsbPrinter.ACTION_USB_PERMISSION)
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
        usbPrinter.disconnect()
        ioExecutor.shutdownNow()
    }

    private fun requestUsbPermission(result: MethodChannel.Result) {
        val dev = usbPrinter.findDevice()
        if (dev == null) {
            mainHandler.post {
                result.error(
                    "NO_PRINTER",
                    "No USB receipt printer found. Connect the Posiflow printer and tap Allow if prompted.",
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
                        "USB permission denied. Reconnect the receipt printer and try again.",
                        null,
                    )
                }
                return
            }
            ioExecutor.execute {
                try {
                    val name = usbPrinter.connect(dev)
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "name" to name,
                                "transport" to "usb",
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

    private fun sendEscPosFile(filePath: String, result: MethodChannel.Result) {
        sendEscPosOnUsb(result) { usbPrinter.writeEscPosFile(filePath) }
    }

    private fun sendEscPos(bytes: ByteArray, result: MethodChannel.Result) {
        sendEscPosOnUsb(result) { usbPrinter.writeEscPos(bytes) }
    }

    private fun sendEscPosOnUsb(result: MethodChannel.Result, write: () -> Unit) {
        ioExecutor.execute {
            try {
                ensureReceiptPrinterConnected()
                write()
                mainHandler.post { result.success(null) }
            } catch (e: ReceiptPrinterException) {
                mainHandler.post { result.error("PRINT_ERROR", e.message, null) }
            } catch (e: Exception) {
                mainHandler.post {
                    result.error("PRINT_ERROR", e.message ?: "Receipt USB print failed", null)
                }
            }
        }
    }

    private fun ensureReceiptPrinterConnected() {
        if (usbPrinter.isConnected) return
        val dev = usbPrinter.findDevice()
            ?: throw ReceiptPrinterException("Receipt printer not connected")
        if (!usbPrinter.hasPermission(dev)) {
            throw ReceiptPrinterException("USB permission not granted")
        }
        usbPrinter.connect(dev)
    }

    private fun hasUsbHost(context: Context): Boolean =
        context.packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
}
