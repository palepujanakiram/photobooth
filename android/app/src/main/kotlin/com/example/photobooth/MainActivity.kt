package com.example.photobooth

import android.content.Context
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "photobooth/display")
            .setMethodCallHandler { call, result ->
                if (call.method == "getRotation") {
                    val wm = getSystemService(Context.WINDOW_SERVICE) as WindowManager
                    @Suppress("DEPRECATION")
                    result.success(wm.defaultDisplay.rotation)
                } else {
                    result.notImplemented()
                }
            }
    }
}
