package com.photobooth.face_count

import android.content.Context
import android.net.Uri
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File

class FaceCountPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.photobooth/face_count")
        channel.setMethodCallHandler(this)
        applicationContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        applicationContext = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method != "detectFaceCount") {
            result.notImplemented()
            return
        }

        val path = call.arguments as? String
        if (path.isNullOrEmpty()) {
            result.success(0)
            return
        }

        val file = File(path)
        if (!file.exists()) {
            result.success(0)
            return
        }

        val context = applicationContext
        if (context == null) {
            result.success(0)
            return
        }

        val options = FaceDetectorOptions.Builder()
            .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
            .build()
        val detector = FaceDetection.getClient(options)

        try {
            val image = InputImage.fromFilePath(context, Uri.fromFile(file))
            detector.process(image)
                .addOnSuccessListener { faces -> result.success(faces.size) }
                .addOnFailureListener { result.success(0) }
        } catch (_: Exception) {
            result.success(0)
        }
    }
}
