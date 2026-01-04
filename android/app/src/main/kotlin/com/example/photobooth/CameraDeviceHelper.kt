package com.example.photobooth

import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

class CameraDeviceHelper(private val context: Context) {
    companion object {
        private const val TAG = "CameraDeviceHelper"
    }
    
    private var availabilityCallback: CameraManager.AvailabilityCallback? = null
    
    /**
     * Checks if the device supports external cameras
     */
    private fun supportsExternalCameras(): Boolean {
        val packageManager = context.packageManager
        val supportsExternal = packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_EXTERNAL)
        val supportsUsbHost = packageManager.hasSystemFeature(PackageManager.FEATURE_USB_HOST)
        
        Log.d(TAG, "🔍 Device capabilities:")
        Log.d(TAG, "   FEATURE_CAMERA_EXTERNAL: $supportsExternal")
        Log.d(TAG, "   FEATURE_USB_HOST: $supportsUsbHost")
        
        return supportsExternal || supportsUsbHost
    }
    
    /**
     * Checks for connected USB devices that might be cameras
     * This helps diagnose if USB camera is connected but not enumerated by Camera2
     */
    private fun checkUsbDevices() {
        try {
            val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager
            if (usbManager == null) {
                Log.w(TAG, "⚠️ USB Manager not available")
                return
            }
            
            val deviceList = usbManager.deviceList
            Log.d(TAG, "🔌 USB Devices connected: ${deviceList.size}")
            
            if (deviceList.isEmpty) {
                Log.d(TAG, "   No USB devices found")
            } else {
                deviceList.forEach { (deviceName, device) ->
                    Log.d(TAG, "   USB Device: $deviceName")
                    Log.d(TAG, "      Vendor ID: 0x${Integer.toHexString(device.vendorId)}")
                    Log.d(TAG, "      Product ID: 0x${Integer.toHexString(device.productId)}")
                    Log.d(TAG, "      Class: ${device.deviceClass}")
                    Log.d(TAG, "      Subclass: ${device.deviceSubclass}")
                    Log.d(TAG, "      Protocol: ${device.deviceProtocol}")
                    
                    // Check if this might be a camera (USB Video Class = 14)
                    if (device.deviceClass == 14 || device.deviceSubclass == 1) {
                        Log.d(TAG, "      ✅ This appears to be a USB Video Class (UVC) device - likely a camera!")
                        Log.d(TAG, "      ⚠️ If this camera is not in Camera2 list, it may need:")
                        Log.d(TAG, "         - USB permissions")
                        Log.d(TAG, "         - Time to enumerate")
                        Log.d(TAG, "         - Device-specific driver support")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error checking USB devices: ${e.message}")
        }
    }
    
    /**
     * Determines if a camera is external based on multiple characteristics
     * @param cameraId The camera ID to check
     * @param characteristics The camera characteristics
     * @param isInInitialList Whether this camera was in the initial cameraIdList
     * @param maxInitialId The maximum camera ID from the initial list (built-in cameras typically 0-3)
     */
    private fun isExternalCamera(
        cameraId: String,
        characteristics: CameraCharacteristics,
        isInInitialList: Boolean = true,
        maxInitialId: Int = 3
    ): Boolean {
        val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
        val cameraIdInt = cameraId.toIntOrNull() ?: -1
        
        // Method 1: Explicit external facing
        if (facing == CameraCharacteristics.LENS_FACING_EXTERNAL) {
            Log.d(TAG, "✅ Camera $cameraId is EXTERNAL (LENS_FACING_EXTERNAL)")
            return true
        }
        
        // Method 2: Null facing often indicates external USB camera
        if (facing == null) {
            Log.d(TAG, "⚠️ Camera $cameraId has null LENS_FACING - likely external USB camera")
            return true
        }
        
        // Method 3: Camera not in initial list with higher ID
        // Built-in cameras are typically 0-3, external USB cameras get higher IDs (4+)
        if (!isInInitialList && cameraIdInt > maxInitialId) {
            Log.d(TAG, "✅ Camera $cameraId is EXTERNAL (ID $cameraIdInt > $maxInitialId and not in initial list)")
            Log.d(TAG, "   This is a strong indicator of an external USB camera")
            return true
        }
        
        // Method 4: Check camera ID pattern for high IDs
        // External cameras typically get IDs 4, 5, 6, etc. even if they report BACK/FRONT facing
        // This is because Android may misclassify them
        if (cameraIdInt >= 4) {
            Log.d(TAG, "⚠️ Camera $cameraId has high ID ($cameraIdInt >= 4) - likely external USB camera")
            Log.d(TAG, "   Even though LENS_FACING is $facing, high IDs typically indicate external cameras")
            return true
        }
        
        // Method 5: Check if camera is not front or back
        // If it's not explicitly front or back, it might be external
        if (facing != CameraCharacteristics.LENS_FACING_FRONT && 
            facing != CameraCharacteristics.LENS_FACING_BACK) {
            Log.d(TAG, "⚠️ Camera $cameraId has unknown facing value: $facing - treating as external")
            return true
        }
        
        return false
    }

    fun getAllAvailableCameras(result: MethodChannel.Result) {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            
            // Check device capabilities first
            val supportsExternal = supportsExternalCameras()
            if (!supportsExternal) {
                Log.w(TAG, "⚠️ Device may not support external cameras")
            }
            
            // Check for USB devices that might be cameras
            checkUsbDevices()
            
            // Get all camera IDs - this should include external USB cameras
            val cameraIds = try {
                cameraManager.cameraIdList
            } catch (e: CameraAccessException) {
                Log.e(TAG, "CameraAccessException getting camera list: ${e.message}")
                result.error("CAMERA_ACCESS_ERROR", "Failed to access camera service: ${e.message}", null)
                return
            } catch (e: Exception) {
                Log.e(TAG, "Exception getting camera list: ${e.message}")
                result.error("CAMERA_ERROR", "Failed to get camera list: ${e.message}", null)
                return
            }

            Log.d(TAG, "📷 Found ${cameraIds.size} camera(s) total")
            Log.d(TAG, "📋 Camera IDs list: ${cameraIds.joinToString(", ")}")

            val cameras = mutableListOf<Map<String, Any>>()
            var externalCount = 0
            var backCount = 0
            var frontCount = 0
            
            // Additional check: Try to query camera characteristics for all possible IDs
            // Some devices might have cameras that aren't in cameraIdList immediately
            // This is a workaround for devices that enumerate cameras slowly
            // External USB cameras often get higher IDs (4, 5, 6, etc.)
            val maxInitialId = cameraIds.maxOfOrNull { it.toIntOrNull() ?: 0 } ?: 3
            if (supportsExternal) {
                Log.d(TAG, "🔍 Checking for additional cameras beyond ID $maxInitialId (common for USB cameras)")
                
                // Check IDs from maxId+1 to maxId+10 (USB cameras typically get higher IDs)
                var foundAdditionalCameras = 0
                for (testId in (maxInitialId + 1)..(maxInitialId + 10)) {
                    try {
                        val testCharacteristics = cameraManager.getCameraCharacteristics(testId.toString())
                        val testFacing = testCharacteristics.get(CameraCharacteristics.LENS_FACING)
                        // Pass false for isInInitialList and maxInitialId to help detection
                        val testIsExternal = isExternalCamera(
                            testId.toString(), 
                            testCharacteristics,
                            isInInitialList = false,
                            maxInitialId = maxInitialId
                        )
                        
                        Log.w(TAG, "   ⚠️ Found camera ID $testId that wasn't in cameraIdList!")
                        Log.w(TAG, "      LENS_FACING: $testFacing")
                        Log.w(TAG, "      Is External: $testIsExternal")
                        
                        // Add this camera to our list even though it's not in cameraIdList
                        foundAdditionalCameras++
                        val cameraName = when {
                            testIsExternal -> {
                                externalCount++
                                val facingValue = testFacing?.let { 
                                    when (it) {
                                        CameraCharacteristics.LENS_FACING_EXTERNAL -> "External"
                                        else -> "External USB"
                                    }
                                } ?: "External USB"
                                "$facingValue Camera"
                            }
                            testFacing == CameraCharacteristics.LENS_FACING_BACK -> {
                                backCount++
                                "Back Camera"
                            }
                            testFacing == CameraCharacteristics.LENS_FACING_FRONT -> {
                                frontCount++
                                "Front Camera"
                            }
                            else -> "Camera $testId"
                        }
                        
                        val cameraInfo = mapOf(
                            "uniqueID" to testId.toString(),
                            "localizedName" to cameraName
                        )
                        cameras.add(cameraInfo)
                        
                        Log.w(TAG, "      ✅ Added camera $testId to list: $cameraName")
                    } catch (e: IllegalArgumentException) {
                        // Camera doesn't exist at this ID, continue
                    } catch (e: CameraAccessException) {
                        Log.d(TAG, "   Camera $testId access denied (may need permissions)")
                    } catch (e: Exception) {
                        // Ignore other errors
                    }
                }
                
                if (foundAdditionalCameras > 0) {
                    Log.w(TAG, "⚠️ Found $foundAdditionalCameras camera(s) not in initial cameraIdList!")
                    Log.w(TAG, "   This suggests camera enumeration is incomplete or delayed")
                    Log.w(TAG, "   These cameras are likely external USB cameras")
                }
            }

            // Now process cameras from the official cameraIdList
            for (cameraId in cameraIds) {
                try {
                    val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                    val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                    
                    // Get additional camera info for better identification
                    val capabilities = characteristics.get(CameraCharacteristics.REQUEST_AVAILABLE_CAPABILITIES)
                    val physicalIds = characteristics.get(CameraCharacteristics.LOGICAL_MULTI_CAMERA_SENSOR_SYNC_TYPE)
                    val sensorOrientation = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION)
                    val supportedHardwareLevel = characteristics.get(CameraCharacteristics.INFO_SUPPORTED_HARDWARE_LEVEL)
                    
                    Log.d(TAG, "🔍 Analyzing camera ID: $cameraId")
                    Log.d(TAG, "   LENS_FACING: $facing (0=FRONT, 1=BACK, 2=EXTERNAL)")
                    Log.d(TAG, "   SENSOR_ORIENTATION: $sensorOrientation")
                    Log.d(TAG, "   LOGICAL_MULTI_CAMERA_SENSOR_SYNC_TYPE: $physicalIds")
                    Log.d(TAG, "   SUPPORTED_HARDWARE_LEVEL: $supportedHardwareLevel")
                    
                    // Determine if this is an external camera using comprehensive detection
                    // Pass true for isInInitialList since this camera is from cameraIdList
                    val isExternal = isExternalCamera(
                        cameraId, 
                        characteristics,
                        isInInitialList = true,
                        maxInitialId = maxInitialId
                    )
                    
                    // Generate camera name based on detection
                    val cameraName = when {
                        isExternal -> {
                            externalCount++
                            // Try to get a better name if available
                            val facingValue = facing?.let { 
                                when (it) {
                                    CameraCharacteristics.LENS_FACING_EXTERNAL -> "External"
                                    else -> "External USB"
                                }
                            } ?: "External USB"
                            "$facingValue Camera"
                        }
                        facing == CameraCharacteristics.LENS_FACING_BACK -> {
                            backCount++
                            "Back Camera"
                        }
                        facing == CameraCharacteristics.LENS_FACING_FRONT -> {
                            frontCount++
                            "Front Camera"
                        }
                        else -> {
                            Log.w(TAG, "⚠️ Camera $cameraId has unknown characteristics")
                            "Camera $cameraId"
                        }
                    }

                    // Return only uniqueID (cameraId) and localizedName (cameraName)
                    val cameraInfo = mapOf(
                        "uniqueID" to cameraId,
                        "localizedName" to cameraName
                    )

                    cameras.add(cameraInfo)

                    Log.d(TAG, "✅ Camera detected:")
                    Log.d(TAG, "   ID: $cameraId")
                    Log.d(TAG, "   Name: $cameraName")
                    Log.d(TAG, "   Facing: $facing")
                    Log.d(TAG, "   Is External: $isExternal")
                    Log.d(TAG, "   Capabilities: ${capabilities?.contentToString() ?: "null"}")
                } catch (e: CameraAccessException) {
                    Log.e(TAG, "CameraAccessException getting info for $cameraId: ${e.message}")
                    // Continue with other cameras even if one fails
                } catch (e: Exception) {
                    Log.e(TAG, "Error getting camera info for $cameraId: ${e.message}", e)
                    // Continue with other cameras even if one fails
                }
            }

            Log.d(TAG, "📸 Returning ${cameras.size} camera(s) to Flutter")
            Log.d(TAG, "📊 Summary:")
            Log.d(TAG, "   Total cameras: ${cameras.size}")
            Log.d(TAG, "   Back cameras: $backCount")
            Log.d(TAG, "   Front cameras: $frontCount")
            Log.d(TAG, "   External cameras: $externalCount")
            
            if (externalCount == 0 && supportsExternal) {
                Log.w(TAG, "⚠️ WARNING: Device supports external cameras but none detected!")
                Log.w(TAG, "   Current camera count: ${cameraIds.size}")
                Log.w(TAG, "   Expected: More than ${cameraIds.size} if USB camera is connected")
                Log.w(TAG, "")
                Log.w(TAG, "   Troubleshooting steps:")
                Log.w(TAG, "   1. Ensure USB camera is properly connected and powered")
                Log.w(TAG, "   2. Check if camera appears in Android Settings > Connected devices")
                Log.w(TAG, "   3. Try disconnecting and reconnecting the USB camera")
                Log.w(TAG, "   4. Wait 10-15 seconds after connecting for Android to enumerate")
                Log.w(TAG, "   5. Check if camera works in native Camera app")
                Log.w(TAG, "   6. Verify USB OTG adapter is working (if using adapter)")
                Log.w(TAG, "   7. Check USB device logs above to see if camera is detected at USB level")
                Log.w(TAG, "   8. Some USB cameras require specific drivers - check device compatibility")
                Log.w(TAG, "")
                Log.w(TAG, "   IMPORTANT: If USB device is detected but not in Camera2 list:")
                Log.w(TAG, "   - Camera may need USB permissions (check USB device logs)")
                Log.w(TAG, "   - Camera may need time to initialize")
                Log.w(TAG, "   - Camera may not be UVC-compliant")
                Log.w(TAG, "   - Device may not support this specific camera model")
            } else if (externalCount > 0) {
                Log.d(TAG, "✅ Successfully detected $externalCount external camera(s)")
            }
            
            result.success(cameras)
        } catch (e: Exception) {
            Log.e(TAG, "Fatal error getting cameras: ${e.message}", e)
            result.error("CAMERA_ERROR", "Failed to get cameras: ${e.message}", null)
        }
    }
    
    /**
     * Registers a callback to listen for camera availability changes.
     * This helps detect when external USB cameras are connected/disconnected.
     */
    fun registerAvailabilityCallback() {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            
            // Unregister existing callback if any
            unregisterAvailabilityCallback()
            
            val callback = object : CameraManager.AvailabilityCallback() {
                override fun onCameraAvailable(cameraId: String) {
                    Log.d(TAG, "📷 Camera became available: $cameraId")
                    try {
                        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                        val cameraIdInt = cameraId.toIntOrNull() ?: -1
                        val maxInitialId = 3 // Typical max for built-in cameras
                        val isExternal = isExternalCamera(
                            cameraId,
                            characteristics,
                            isInInitialList = false, // New camera, not in initial list
                            maxInitialId = maxInitialId
                        )
                        if (isExternal) {
                            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
                            Log.d(TAG, "✅ External/USB camera connected: $cameraId")
                            Log.d(TAG, "   LENS_FACING: $facing")
                            Log.d(TAG, "   Camera ID: $cameraIdInt (high ID indicates external)")
                            Log.d(TAG, "   This camera is now available for use")
                        } else {
                            Log.d(TAG, "   Internal camera available: $cameraId")
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "Error checking camera characteristics: ${e.message}")
                    }
                }
                
                override fun onCameraUnavailable(cameraId: String) {
                    Log.d(TAG, "📷 Camera became unavailable: $cameraId")
                    try {
                        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
                        val cameraIdInt = cameraId.toIntOrNull() ?: -1
                        val maxInitialId = 3
                        val isExternal = isExternalCamera(
                            cameraId,
                            characteristics,
                            isInInitialList = false,
                            maxInitialId = maxInitialId
                        )
                        if (isExternal) {
                            Log.d(TAG, "⚠️ External/USB camera disconnected: $cameraId")
                        }
                    } catch (e: Exception) {
                        // Camera might already be unavailable, ignore errors
                        Log.d(TAG, "   Camera $cameraId is no longer accessible")
                    }
                }
            }
            
            availabilityCallback = callback
            cameraManager.registerAvailabilityCallback(
                callback,
                Handler(Looper.getMainLooper())
            )
            Log.d(TAG, "✅ Registered camera availability callback")
        } catch (e: Exception) {
            Log.e(TAG, "Error registering camera availability callback: ${e.message}")
        }
    }
    
    /**
     * Unregisters the camera availability callback.
     */
    fun unregisterAvailabilityCallback() {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            availabilityCallback?.let {
                cameraManager.unregisterAvailabilityCallback(it)
                Log.d(TAG, "Unregistered camera availability callback")
            }
            availabilityCallback = null
        } catch (e: Exception) {
            Log.e(TAG, "Error unregistering camera availability callback: ${e.message}")
        }
    }
    
    /**
     * Forces a refresh of the camera list by waiting a bit and re-querying
     * This can help detect cameras that take time to enumerate
     */
    fun refreshCameraList(result: MethodChannel.Result, delayMs: Long = 2000) {
        Log.d(TAG, "🔄 Refreshing camera list (waiting ${delayMs}ms for enumeration)...")
        
        Handler(Looper.getMainLooper()).postDelayed({
            Log.d(TAG, "🔄 Re-querying cameras after delay...")
            getAllAvailableCameras(result)
        }, delayMs)
    }
}

