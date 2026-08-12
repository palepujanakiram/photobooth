package com.srisarani.fotozenai

import android.content.Context
import android.os.Handler
import android.os.Looper
import com.srisarani.fotozenai.dnp.DnpWifiNetworkBinder
import com.srisarani.fotozenai.selphy.SelphyPrintRequest
import com.srisarani.fotozenai.selphy.SelphyUsbSession
import com.srisarani.fotozenai.selphy.SelphyWifiSession
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Native Canon Selphy CP1500 USB / Wi‑Fi printing (official Selphy SDKs). */
object SelphyMethodChannel {
    const val METHOD_CHANNEL = "com.srisarani.fotozenai/selphy"

    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var appContext: Context

    /** Activity/context used for SDK discovery & print (prefer Activity over Application). */
    private var hostContext: Context? = null

    private var usbSession: SelphyUsbSession? = null
    private var wifiSession: SelphyWifiSession? = null

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
        appContext = context.applicationContext
        hostContext = context
        val binder = DnpWifiNetworkBinder(appContext, mainHandler)
        usbSession =
            SelphyUsbSession(
                appContext = appContext,
                sdkContext = ::sdkContext,
                mainHandler = mainHandler,
            )
        wifiSession =
            SelphyWifiSession(
                appContext = appContext,
                sdkContext = ::sdkContext,
                mainHandler = mainHandler,
                wifiNetworkBinder = binder,
            )

        MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "probeUsb" -> {
                    usbSession?.probeDevice(result)
                }

                "requestPermission" -> {
                    usbSession?.requestPermission(result)
                }

                "discoverWifi" -> {
                    wifiSession?.discover(result)
                }

                "releaseWifi" -> {
                    wifiSession?.releaseBinding()
                    result.success(null)
                }

                "resetSession" -> {
                    usbSession?.clear()
                    wifiSession?.clear()
                    wifiSession?.releaseBinding()
                    result.success(null)
                }

                "print" -> {
                    handlePrint(call.arguments, result)
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    fun onDestroy() {
        wifiSession?.releaseBinding()
        usbSession?.clear()
        wifiSession?.clear()
        usbSession = null
        wifiSession = null
        hostContext = null
    }

    private fun sdkContext(): Context = hostContext ?: appContext

    private fun handlePrint(
        arguments: Any?,
        result: MethodChannel.Result,
    ) {
        val request = SelphyPrintRequest.fromChannelArgs(arguments, result) ?: return
        if (request.isWifi) {
            wifiSession?.startPrint(request)
        } else {
            usbSession?.startPrint(request)
        }
    }
}
