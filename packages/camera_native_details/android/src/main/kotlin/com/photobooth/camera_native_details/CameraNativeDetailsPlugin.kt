package com.photobooth.camera_native_details

import android.content.Context
import android.graphics.ImageFormat
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.os.Build
import android.graphics.SurfaceTexture
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class CameraNativeDetailsPlugin : FlutterPlugin, MethodCallHandler {

    private lateinit var channel: MethodChannel
    private var applicationContext: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(binding.binaryMessenger, "com.photobooth/camera_native_details")
        channel.setMethodCallHandler(this)
        applicationContext = binding.applicationContext
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        applicationContext = null
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "getCameraDetails") {
            val cameraId = call.arguments as? String ?: run {
                result.error("INVALID_ARGS", "cameraId is required", null)
                return
            }
            getCameraDetails(cameraId, result)
        } else {
            result.notImplemented()
        }
    }

    private fun getCameraDetails(cameraId: String, result: Result) {
        val context = applicationContext ?: run {
            result.error("UNAVAILABLE", "Application context not available", null)
            return
        }
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: run {
            result.error("UNAVAILABLE", "CameraManager not available", null)
            return
        }
        try {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val map = mutableMapOf<String, Any?>()

            // SENSOR_INFO_ACTIVE_ARRAY_SIZE
            val activeArray = characteristics.get(CameraCharacteristics.SENSOR_INFO_ACTIVE_ARRAY_SIZE)
            if (activeArray != null) {
                map["activeArrayWidth"] = activeArray.width()
                map["activeArrayHeight"] = activeArray.height()
            }

            // CONTROL_ZOOM_RATIO_RANGE (API 30+)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                val zoomRange = characteristics.get(CameraCharacteristics.CONTROL_ZOOM_RATIO_RANGE)
                if (zoomRange != null) {
                    map["zoomRatioRangeMin"] = zoomRange.lower.toDouble()
                    map["zoomRatioRangeMax"] = zoomRange.upper.toDouble()
                }
            }

            // SCALER_AVAILABLE_MAX_DIGITAL_ZOOM
            val maxZoom = characteristics.get(CameraCharacteristics.SCALER_AVAILABLE_MAX_DIGITAL_ZOOM)
            if (maxZoom != null) {
                map["maxDigitalZoom"] = maxZoom.toDouble()
            }

            // SCALER_STREAM_CONFIGURATION_MAP - supported output sizes
            val configMap = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            if (configMap != null) {
                val previewSizes = configMap.getOutputSizes(SurfaceTexture::class.java)
                    ?: configMap.getOutputSizes(ImageFormat.JPEG)
                    ?: configMap.getOutputSizes(ImageFormat.YUV_420_888)
                map["supportedPreviewSizes"] = previewSizes
                    ?.map { "${it.width}x${it.height}" }
                    ?.distinct()
                    ?.sortedWith(compareBy({ it.split("x")[0].toIntOrNull() ?: 0 }, { it.split("x").getOrNull(1)?.toIntOrNull() ?: 0 }))
                    ?: emptyList<String>()
                val captureSizes = configMap.getOutputSizes(ImageFormat.JPEG)
                map["supportedCaptureSizes"] = captureSizes
                    ?.map { "${it.width}x${it.height}" }
                    ?.distinct()
                    ?.sortedWith(compareBy({ it.split("x")[0].toIntOrNull() ?: 0 }, { it.split("x").getOrNull(1)?.toIntOrNull() ?: 0 }))
                    ?: emptyList<String>()
            } else {
                map["supportedPreviewSizes"] = emptyList<String>()
                map["supportedCaptureSizes"] = emptyList<String>()
            }

            // LENS_FACING
            val lensFacing = characteristics.get(CameraCharacteristics.LENS_FACING)
            map["lensFacing"] = when (lensFacing) {
                CameraCharacteristics.LENS_FACING_BACK -> "back"
                CameraCharacteristics.LENS_FACING_FRONT -> "front"
                CameraCharacteristics.LENS_FACING_EXTERNAL -> "external"
                else -> null
            }

            map["platform"] = "android"
            result.success(map)
        } catch (e: Exception) {
            result.error("ERROR", e.message ?: "Failed to get camera characteristics", null)
        }
    }
}
