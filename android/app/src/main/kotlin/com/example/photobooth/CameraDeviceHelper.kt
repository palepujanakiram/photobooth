package com.example.photobooth

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel

class CameraDeviceHelper(private val context: Context) {

    companion object {
        private const val TAG = "CameraDeviceHelper"
        private const val USB_VIDEO_CLASS = 14 // UVC
    }

    /**
     * Entry point called from Flutter
     */
    fun getAllAvailableCameras(result: MethodChannel.Result) {
        try {
            val cameras = mutableListOf<Map<String, Any>>()

            // Get Camera2 cameras first (to know which ones are already accounted for)
            val camera2Cameras = getCamera2Cameras()
            cameras.addAll(camera2Cameras)
            
            // Get USB cameras and try to match them with Camera2 IDs
            val usbCameras = getUsbCameras(camera2Cameras)
            cameras.addAll(usbCameras)

            Log.d(TAG, "📸 Total cameras returned: ${cameras.size}")
            result.success(cameras)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to list cameras", e)
            result.error("CAMERA_ERROR", e.message, null)
        }
    }
    
    /**
     * Gets USB vendor/product IDs for a given Camera2 ID
     * Returns null if not found or not a USB camera
     */
    fun getUsbIdsForCameraId(cameraId: String, result: MethodChannel.Result) {
        try {
            val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
            if (usbManager == null) {
                result.success(null)
                return
            }

            val devices = usbManager.deviceList
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager

            // Try to match camera ID with USB devices
            for (device in devices.values) {
                if (isUsbCamera(device)) {
                    // Check if this USB device corresponds to the given camera ID
                    val camera2Id = probeForCamera2Id(device, emptySet(), cameraManager)
                    if (camera2Id == cameraId) {
                        Log.d(TAG, "✅ Found USB device for camera ID $cameraId: vendor=${device.vendorId}, product=${device.productId}")
                        result.success(mapOf(
                            "vendorId" to device.vendorId,
                            "productId" to device.productId
                        ))
                        return
                    }
                }
            }

            Log.d(TAG, "⚠️ No USB device found for camera ID $cameraId")
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Error getting USB IDs for camera ID: ${e.message}", e)
            result.success(null)
        }
    }

    /**
     * Forces Camera2 enumeration by waiting and checking repeatedly
     * This can help when USB cameras take time to be enumerated
     */
    fun forceCamera2Enumeration(vendorId: Int, productId: Int, result: MethodChannel.Result) {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val maxWaitTime = 30 // seconds
            val checkInterval = 2 // seconds
            val maxAttempts = maxWaitTime / checkInterval
            
            Log.d(TAG, "🔄 Forcing Camera2 enumeration for USB camera (vendor=$vendorId, product=$productId)")
            Log.d(TAG, "   Will check every $checkInterval seconds for up to $maxWaitTime seconds")
            
            for (attempt in 1..maxAttempts) {
                Thread.sleep(checkInterval * 1000L)
                
                try {
                    val cameraIds = cameraManager.cameraIdList
                    Log.d(TAG, "   Attempt $attempt/$maxAttempts: Checking ${cameraIds.size} cameras")
                    
                    // Check all cameras for external facing
                    for (cameraId in cameraIds) {
                        try {
                            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                            
                            if (facing == CameraCharacteristics.LENS_FACING_EXTERNAL) {
                                Log.d(TAG, "   ✅ Found external camera with Camera2 ID: $cameraId")
                                result.success(mapOf(
                                    "camera2Id" to cameraId,
                                    "attempt" to attempt,
                                    "found" to true
                                ))
                                return
                            }
                        } catch (e: Exception) {
                            // Skip cameras we can't access
                            continue
                        }
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "   ⚠️ Error checking cameras (attempt $attempt): ${e.message}")
                }
            }
            
            Log.d(TAG, "   ❌ Camera2 ID not found after $maxWaitTime seconds")
            result.success(mapOf(
                "camera2Id" to null,
                "attempt" to maxAttempts,
                "found" to false
            ))
        } catch (e: Exception) {
            Log.e(TAG, "Error forcing Camera2 enumeration: ${e.message}", e)
            result.error("ENUM_ERROR", e.message, null)
        }
    }

    /**
     * Built-in cameras (Camera2) + external cameras
     */
    private fun getCamera2Cameras(): List<Map<String, Any>> {
        val cameraManager =
            context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

        val result = mutableListOf<Map<String, Any>>()

        val cameraIds = try {
            cameraManager.cameraIdList
        } catch (e: CameraAccessException) {
            Log.e(TAG, "CameraAccessException getting camera list: ${e.message}")
            return result
        } catch (e: Exception) {
            Log.e(TAG, "Exception getting camera list: ${e.message}")
            return result
        }

        Log.d(TAG, "Camera2 IDs from cameraIdList: ${cameraIds.joinToString()}")

        // SIMPLE APPROACH: Only use cameras from cameraIdList (the authoritative source)
        // cameraIdList includes all available cameras, including external USB cameras
        // when they're properly connected and enumerated by Android
        
        val maxInitialId = cameraIds.mapNotNull { it.toIntOrNull() }.maxOrNull() ?: 3
        
        for (cameraId in cameraIds) {
            try {
                val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                val cameraIdInt = cameraId.toIntOrNull() ?: -1
                
                // Determine camera name
                val name = when {
                    facing == CameraCharacteristics.LENS_FACING_EXTERNAL -> "External Camera"
                    facing == CameraCharacteristics.LENS_FACING_FRONT -> "Front Camera"
                    facing == CameraCharacteristics.LENS_FACING_BACK -> "Back Camera"
                    // If camera ID is beyond typical built-in range and facing is null/unknown,
                    // it's likely an external USB camera that doesn't report LENS_FACING correctly
                    cameraIdInt > maxInitialId -> "External USB Camera"
                    else -> "Camera $cameraId"
                }

                result.add(
                    mapOf(
                        "uniqueID" to cameraId,
                        "localizedName" to name,
                        "source" to "camera2"
                    )
                )

                Log.d(TAG, "Camera2 → ID=$cameraId, Name=$name, LENS_FACING=$facing")
            } catch (e: Exception) {
                Log.w(TAG, "Skipping camera $cameraId", e)
            }
        }

        Log.d(TAG, "Total Camera2 cameras found: ${result.size}")
        return result
    }
    
    /**
     * Checks if device supports external cameras
     */
    private fun supportsExternalCameras(): Boolean {
        val packageManager = context.packageManager
        val supportsExternal = packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_EXTERNAL)
        val supportsUsbHost = packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
        
        Log.d(TAG, "Device capabilities:")
        Log.d(TAG, "  FEATURE_CAMERA_EXTERNAL: $supportsExternal")
        Log.d(TAG, "  FEATURE_USB_HOST: $supportsUsbHost")
        
        return supportsExternal || supportsUsbHost
    }

    /**
     * USB / UVC cameras
     * Attempts to find corresponding Camera2 IDs for USB cameras
     * If a Camera2 ID is found, uses that instead of the USB ID
     */
    private fun getUsbCameras(knownCamera2Cameras: List<Map<String, Any>>): List<Map<String, Any>> {
        val cameraManager =
            context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

        val result = mutableListOf<Map<String, Any>>()

        // Try to enumerate USB devices
        // Note: On Android 10+ (API 29+), this may require USB permissions
        // If it fails, we'll continue without USB enumeration - Camera2 API should still work
        val devices = try {
            val usbManager =
                context.getSystemService(Context.USB_SERVICE) as UsbManager
            usbManager.deviceList.values.toList()
        } catch (e: SecurityException) {
            Log.d(TAG, "⚠️ USB enumeration requires permissions on this Android version (${android.os.Build.VERSION.SDK_INT})")
            Log.d(TAG, "   This is normal on Android 10+. Camera2 API should still work if camera is enumerated.")
            emptyList()  // Continue without USB enumeration
        } catch (e: Exception) {
            Log.e(TAG, "Error accessing USB devices: ${e.message}")
            emptyList()  // Continue without USB enumeration
        }
        
        Log.d(TAG, "USB devices connected: ${devices.size}")

        // Get list of Camera2 IDs that are already known
        val knownCamera2Ids = knownCamera2Cameras.mapNotNull { it["uniqueID"] as? String }.toSet()
        Log.d(TAG, "Known Camera2 IDs: ${knownCamera2Ids.joinToString()}")

        for (device in devices) {
            if (isUsbCamera(device)) {
                Log.d(
                    TAG,
                    "USB Camera detected → vendor=${device.vendorId}, product=${device.productId}, name=${device.deviceName}"
                )

                // Try to find corresponding Camera2 ID
                val camera2Id = probeForCamera2Id(device, knownCamera2Ids, cameraManager)
                
                if (camera2Id != null) {
                    // Found Camera2 ID - use it instead of USB ID
                    Log.d(TAG, "   ✅ Found Camera2 ID for USB camera: $camera2Id")
                    result.add(
                        mapOf(
                            "uniqueID" to camera2Id,
                            "localizedName" to (device.productName ?: "External USB Camera"),
                            "vendorId" to device.vendorId,
                            "productId" to device.productId,
                            "deviceName" to device.deviceName,
                            "source" to "camera2", // Mark as Camera2 since we found the ID
                            "usbVendorId" to device.vendorId,
                            "usbProductId" to device.productId
                        )
                    )
                } else {
                    // No Camera2 ID found - use USB ID (camera may not be enumerated yet)
                    Log.d(TAG, "   ⚠️ No Camera2 ID found for USB camera - may need time to enumerate")
                    result.add(
                        mapOf(
                            "uniqueID" to "usb_${device.vendorId}_${device.productId}",
                            "localizedName" to (device.productName ?: "USB Camera"),
                            "vendorId" to device.vendorId,
                            "productId" to device.productId,
                            "deviceName" to device.deviceName,
                            "source" to "usb"
                        )
                    )
                }
            }
        }

        if (result.isNotEmpty()) {
            Log.d(TAG, "Found ${result.size} USB cameras")
        }

        return result
    }

    /**
     * Probes for a Camera2 ID that corresponds to a USB camera device
     * Checks cameras in cameraIdList and also probes additional IDs
     */
    private fun probeForCamera2Id(
        usbDevice: UsbDevice,
        knownCamera2Ids: Set<String>,
        cameraManager: CameraManager?
    ): String? {
        if (cameraManager == null) return null

        try {
            // First, check cameras already in cameraIdList that we haven't accounted for
            val cameraIds = cameraManager.cameraIdList
            val maxKnownId = knownCamera2Ids.mapNotNull { it.toIntOrNull() }.maxOrNull() ?: 1
            
            Log.d(TAG, "   🔍 Probing for Camera2 ID for USB camera (vendor=${usbDevice.vendorId}, product=${usbDevice.productId})")
            Log.d(TAG, "   📋 Known Camera2 IDs: ${knownCamera2Ids.joinToString()}")
            Log.d(TAG, "   📋 All Camera2 IDs in list: ${cameraIds.joinToString()}")
            
            // Check cameras in the official list that aren't in our known list
            // ONLY accept cameras explicitly marked as EXTERNAL
            for (cameraId in cameraIds) {
                if (knownCamera2Ids.contains(cameraId)) {
                    continue // Already accounted for
                }
                
                try {
                    val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                    val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                    
                    // ONLY accept cameras that are explicitly marked as EXTERNAL
                    if (facing == CameraCharacteristics.LENS_FACING_EXTERNAL) {
                        Log.d(TAG, "   ✅ Found Camera2 match: ID=$cameraId, LENS_FACING=EXTERNAL")
                        return cameraId
                    } else {
                        Log.d(TAG, "   ⏭️ Camera $cameraId has LENS_FACING=$facing (not EXTERNAL), skipping")
                    }
                } catch (e: Exception) {
                    Log.d(TAG, "   ⚠️ Error checking camera $cameraId: ${e.message}")
                }
            }
            
            // If not found in official list, probe additional IDs
            // USB cameras often get IDs like 2, 3, 4, etc. when they're enumerated
            Log.d(TAG, "   🔍 Probing additional Camera2 IDs beyond official list...")
            val probeStart = maxKnownId + 1
            val probeEnd = maxKnownId + 20 // Probe up to 20 additional IDs (increased from 10)
            
            // Track cameras that exist but are "system only" - might be our USB camera
            var systemOnlyCameraIds = mutableListOf<String>()
            
            for (testId in probeStart..probeEnd) {
                val testIdStr = testId.toString()
                
                // Skip if already in known list or official list
                if (knownCamera2Ids.contains(testIdStr) || cameraIds.contains(testIdStr)) {
                    continue
                }
                
                try {
                    // Try to get characteristics - this will throw if camera doesn't exist
                    val characteristics = cameraManager.getCameraCharacteristics(testIdStr)
                    val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                    
                    // ONLY accept cameras that are explicitly marked as EXTERNAL
                    if (facing == CameraCharacteristics.LENS_FACING_EXTERNAL) {
                        Log.d(TAG, "   ✅ Found Camera2 ID via probing: $testIdStr (LENS_FACING_EXTERNAL)")
                        return testIdStr
                    } else {
                        Log.d(TAG, "   ⏭️ Camera $testIdStr has LENS_FACING=$facing (not EXTERNAL), skipping")
                    }
                } catch (e: IllegalArgumentException) {
                    // Camera doesn't exist at this ID - continue probing
                } catch (e: CameraAccessException) {
                    // Access denied - camera exists but is "system only" or needs permissions
                    val errorCode = e.reason
                    if (errorCode == CameraAccessException.CAMERA_ERROR) {
                        // This might be our USB camera that's not yet accessible
                        Log.d(TAG, "   ⚠️ Camera $testIdStr exists but access denied (system only device) - may be USB camera")
                        systemOnlyCameraIds.add(testIdStr)
                    } else {
                        Log.d(TAG, "   ⚠️ Access denied for camera $testIdStr: ${e.message} (code: $errorCode)")
                    }
                } catch (e: Exception) {
                    // Other error - continue
                    Log.d(TAG, "   ⚠️ Error probing camera $testIdStr: ${e.message}")
                }
            }
            
            // If we found system-only cameras, try using them directly
            // Even though they're marked as "system only", the native controller might be able to access them
            if (systemOnlyCameraIds.isNotEmpty()) {
                Log.d(TAG, "   💡 Found ${systemOnlyCameraIds.size} system-only camera(s): ${systemOnlyCameraIds.joinToString()}")
                Log.d(TAG, "   💡 These may be USB cameras - will try to use them directly")
                
                // Try the first system-only camera ID (usually "2" for first external camera)
                val candidateId = systemOnlyCameraIds.first()
                Log.d(TAG, "   🎯 Attempting to use system-only camera ID: $candidateId")
                Log.d(TAG, "   ⚠️ This camera is marked as 'system only' but we'll try to access it anyway")
                return candidateId
            }
            
            // No Camera2 ID found with LENS_FACING_EXTERNAL
            // Return null so the USB camera will use the UVC path instead
            Log.d(TAG, "   ❌ No Camera2 ID found with LENS_FACING_EXTERNAL for USB camera")
            Log.d(TAG, "   💡 USB camera will use UVC path (usb_vendorId_productId format)")
            
            Log.d(TAG, "   ❌ No Camera2 ID found for USB camera")
            return null
        } catch (e: Exception) {
            Log.e(TAG, "   ❌ Error probing for Camera2 ID: ${e.message}")
            return null
        }
    }

    /**
     * Detect USB Video Class (UVC) devices
     */
    private fun isUsbCamera(device: UsbDevice): Boolean {
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            Log.d(TAG, "   USB Device: ${device.deviceName}, Interface $i: class=${intf.interfaceClass}, subclass=${intf.interfaceSubclass}")
            if (intf.interfaceClass == USB_VIDEO_CLASS) {
                return true
            }
        }
        return false
    }

    /**
     * Diagnostics - call this to log device capabilities
     */
    fun logDeviceCapabilities() {
        val pm = context.packageManager
        Log.d(TAG, "=== Device Camera Capabilities ===")
        Log.d(TAG, "FEATURE_CAMERA = " + pm.hasSystemFeature(PackageManager.FEATURE_CAMERA))
        Log.d(TAG, "FEATURE_CAMERA_ANY = " + pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY))
        Log.d(TAG, "FEATURE_CAMERA_EXTERNAL = " + pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_EXTERNAL))
        Log.d(TAG, "FEATURE_USB_HOST = " + pm.hasSystemFeature(PackageManager.FEATURE_USB_HOST))
        
        // List all cameras
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraIds = cameraManager.cameraIdList
            Log.d(TAG, "Camera IDs in cameraIdList: ${cameraIds.joinToString()}")
            
            for (cameraId in cameraIds) {
                try {
                    val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                    val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                    val facingStr = when (facing) {
                        CameraCharacteristics.LENS_FACING_FRONT -> "FRONT"
                        CameraCharacteristics.LENS_FACING_BACK -> "BACK"
                        CameraCharacteristics.LENS_FACING_EXTERNAL -> "EXTERNAL"
                        else -> "UNKNOWN($facing)"
                    }
                    Log.d(TAG, "  Camera $cameraId: LENS_FACING=$facingStr")
                } catch (e: Exception) {
                    Log.e(TAG, "  Camera $cameraId: Error getting characteristics - ${e.message}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error listing cameras: ${e.message}")
        }
        
        // List USB devices
        try {
            val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            val devices = usbManager.deviceList.values
            Log.d(TAG, "USB Devices: ${devices.size}")
            for (device in devices) {
                Log.d(TAG, "  USB: ${device.deviceName}, vendor=${device.vendorId}, product=${device.productId}")
                for (i in 0 until device.interfaceCount) {
                    val intf = device.getInterface(i)
                    Log.d(TAG, "    Interface $i: class=${intf.interfaceClass}, subclass=${intf.interfaceSubclass}")
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error listing USB devices: ${e.message}")
        }
        Log.d(TAG, "=================================")
    }
}