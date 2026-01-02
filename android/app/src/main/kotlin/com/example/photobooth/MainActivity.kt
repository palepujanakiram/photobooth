package com.example.photobooth

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.photobooth/camera_device_helper"
    private lateinit var cameraDeviceHelper: CameraDeviceHelper

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        cameraDeviceHelper = CameraDeviceHelper(this)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllAvailableCameras" -> {
                    cameraDeviceHelper.getAllAvailableCameras(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}

