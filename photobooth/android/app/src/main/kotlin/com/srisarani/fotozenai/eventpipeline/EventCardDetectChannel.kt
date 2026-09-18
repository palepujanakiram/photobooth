package com.srisarani.fotozenai.eventpipeline

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Streams card insert and removal to Dart so an import can auto-scan.
 *
 * A **runtime** receiver, which is what makes this work without touching
 * `device_filter.xml`. That file only drives the manifest intent filter that
 * *launches* a closed app; a registered receiver sees every device while the app
 * is running. Confirmed in the field — the existing `uvccamera` monitor already
 * logs the card reader's attach and detach today, then ignores it as non-UVC.
 *
 * Callers must not scan on the mount broadcast alone. A card mounts with **zero**
 * MediaStore rows and takes time to index — measured at ~11 s for 261 files, so
 * roughly two minutes for a 3,000-frame card. Scanning immediately reports
 * "0 new photos" on a full card, which is why Dart polls until the count settles.
 */
object EventCardDetectChannel {
    private const val TAG = "EventCardDetect"
    const val CHANNEL_NAME = "com.srisarani.fotozenai/event_card_detect"

    private val mainHandler = Handler(Looper.getMainLooper())

    private var sink: EventChannel.EventSink? = null
    private var receiver: BroadcastReceiver? = null
    private var registeredContext: Context? = null

    fun register(
        flutterEngine: FlutterEngine,
        context: Context,
    ) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }

    fun register(
        messenger: BinaryMessenger,
        context: Context,
    ) {
        val appContext = context.applicationContext
        EventChannel(messenger, CHANNEL_NAME).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(
                    arguments: Any?,
                    events: EventChannel.EventSink?,
                ) {
                    sink = events
                    attach(appContext)
                }

                override fun onCancel(arguments: Any?) {
                    sink = null
                    detach()
                }
            },
        )
    }

    private fun attach(context: Context) {
        if (receiver != null) return
        val handler =
            object : BroadcastReceiver() {
                override fun onReceive(
                    ctx: Context?,
                    intent: Intent?,
                ) {
                    val action = intent?.action ?: return
                    emit(action, intent)
                }
            }

        // Media mount/unmount carry the volume; USB attach/detach fires earlier and
        // covers the case where vold has not finished mounting yet.
        val mediaFilter =
            IntentFilter().apply {
                addAction(Intent.ACTION_MEDIA_MOUNTED)
                addAction(Intent.ACTION_MEDIA_UNMOUNTED)
                addAction(Intent.ACTION_MEDIA_EJECT)
                addAction(Intent.ACTION_MEDIA_REMOVED)
                addAction(Intent.ACTION_MEDIA_BAD_REMOVAL)
                addDataScheme("file")
            }
        val usbFilter =
            IntentFilter().apply {
                addAction(UsbManager.ACTION_USB_DEVICE_ATTACHED)
                addAction(UsbManager.ACTION_USB_DEVICE_DETACHED)
            }

        context.registerReceiver(handler, mediaFilter)
        context.registerReceiver(handler, usbFilter)
        receiver = handler
        registeredContext = context
        Log.d(TAG, "card detect receiver registered")
    }

    private fun detach() {
        val handler = receiver ?: return
        try {
            registeredContext?.unregisterReceiver(handler)
        } catch (e: IllegalArgumentException) {
            Log.d(TAG, "receiver already unregistered: ${e.message}")
        }
        receiver = null
        registeredContext = null
    }

    private fun emit(
        action: String,
        intent: Intent,
    ) {
        val kind =
            when (action) {
                Intent.ACTION_MEDIA_MOUNTED -> "mounted"
                Intent.ACTION_MEDIA_UNMOUNTED,
                Intent.ACTION_MEDIA_EJECT,
                Intent.ACTION_MEDIA_REMOVED,
                Intent.ACTION_MEDIA_BAD_REMOVAL,
                -> "unmounted"
                UsbManager.ACTION_USB_DEVICE_ATTACHED -> "usbAttached"
                UsbManager.ACTION_USB_DEVICE_DETACHED -> "usbDetached"
                else -> return
            }

        val device =
            @Suppress("DEPRECATION")
            intent.getParcelableExtra<android.hardware.usb.UsbDevice>(
                UsbManager.EXTRA_DEVICE,
            )
        val payload =
            mapOf(
                "kind" to kind,
                "path" to intent.data?.path,
                "vendorId" to device?.vendorId,
                "productId" to device?.productId,
                "productName" to device?.productName,
                "isMassStorage" to
                    (
                        device != null &&
                            (0 until device.interfaceCount).any {
                                device.getInterface(it).interfaceClass == 8
                            }
                    ),
            )

        mainHandler.post { sink?.success(payload) }
    }
}
