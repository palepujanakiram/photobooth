package com.srisarani.fotozenai

import android.app.ActivityManager
import android.content.Context
import android.os.Debug
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

object DeviceMemoryMethodChannel {
    private const val CHANNEL_NAME = "photobooth/device_memory"

    fun register(
        messenger: BinaryMessenger,
        context: Context,
    ) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            if (call.method != "getMemoryInfo") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val activityManager =
                context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memInfo = ActivityManager.MemoryInfo()
            activityManager.getMemoryInfo(memInfo)
            val processRssBytes = Debug.getPss() * 1024L
            result.success(
                mapOf(
                    "processRssBytes" to processRssBytes,
                    "availableBytes" to memInfo.availMem,
                    "totalBytes" to memInfo.totalMem,
                    "lowMemory" to memInfo.lowMemory,
                ),
            )
        }
    }

    fun register(
        flutterEngine: FlutterEngine,
        context: Context,
    ) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }
}
