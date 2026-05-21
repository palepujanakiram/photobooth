package com.srisarani.fotozenai

import android.content.Context
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object DisplayMethodChannel {
    private const val CHANNEL_NAME = "photobooth/display"

    fun register(
        messenger: BinaryMessenger,
        context: Context,
    ) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            if (call.method != "getRotation") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            @Suppress("DEPRECATION")
            result.success(wm.defaultDisplay.rotation)
        }
    }

    fun register(
        flutterEngine: FlutterEngine,
        context: Context,
    ) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }
}
