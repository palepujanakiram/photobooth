package com.example.photobooth

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel

class CameraDeviceHelper(private val context: Context) {
    companion object {
        private const val TAG = "CameraDeviceHelper"
    }

    fun getAllAvailableCameras(result: MethodChannel.Result) {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraIds = cameraManager.cameraIdList

            Log.d(TAG, "Found ${cameraIds.size} camera(s)")

            val cameras = mutableListOf<Map<String, Any>>()

            for (cameraId in cameraIds) {
                try {
                    val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                    val facing = characteristics.get(CameraCharacteristics.LENS_FACING)

                    // Generate camera name based on facing direction and camera ID
                    val cameraName = when (facing) {
                        CameraCharacteristics.LENS_FACING_BACK -> "Back Camera"
                        CameraCharacteristics.LENS_FACING_FRONT -> "Front Camera"
                        CameraCharacteristics.LENS_FACING_EXTERNAL -> "External Camera $cameraId"
                        else -> "Camera $cameraId"
                    }

                    // Return only uniqueID (cameraId) and localizedName (cameraName)
                    val cameraInfo = mapOf(
                        "uniqueID" to cameraId,
                        "localizedName" to cameraName
                    )

                    cameras.add(cameraInfo)

                    Log.d(TAG, "Camera: $cameraId")
                    Log.d(TAG, "  Name: $cameraName")
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting camera info for $cameraId: ${e.message}")
                }
            }

            result.success(cameras)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting cameras: ${e.message}")
            result.error("CAMERA_ERROR", "Failed to get cameras: ${e.message}", null)
        }
    }
}

