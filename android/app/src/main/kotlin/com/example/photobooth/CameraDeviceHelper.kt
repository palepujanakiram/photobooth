package com.example.photobooth

import android.content.Context
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

            // Use Camera2 list only when non-empty (includes external USB cams on Android TV).
            val camera2Cameras = getCamera2Cameras()
            cameras.addAll(camera2Cameras)
            if (camera2Cameras.isEmpty()) {
                val usbCameras = getUsbCameras(emptyList())
                cameras.addAll(usbCameras)
            } else {
                // Replace "External Camera" with actual USB product name (e.g. "HP 4K Streaming Webcam") when we can match.
                applyUsbProductNamesToCameraList(cameras)
            }

            Log.d(TAG, "📸 Total cameras returned: ${cameras.size}")
            result.success(cameras)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to list cameras", e)
            result.error("CAMERA_ERROR", e.message, null)
        }
    }

    /**
     * Built-in cameras (Camera2) + external cameras
     */
    private fun getCamera2Cameras(): List<Map<String, Any>> {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
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
                val cameraInfo = buildCameraInfo(cameraManager, cameraId, maxInitialId)
                if (cameraInfo != null) {
                    result.add(cameraInfo)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Skipping camera $cameraId", e)
            }
        }

        Log.d(TAG, "Total Camera2 cameras found: ${result.size}")
        return result
    }

    private fun buildCameraInfo(
        cameraManager: CameraManager,
        cameraId: String,
        maxInitialId: Int
    ): Map<String, Any>? {
        val characteristics = cameraManager.getCameraCharacteristics(cameraId)
        val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
        val name = determineCameraName(facing, cameraId, maxInitialId)

        Log.d(TAG, "Camera2 → ID=$cameraId, Name=$name, LENS_FACING=$facing")

        return mapOf(
            "uniqueID" to cameraId,
            "localizedName" to name,
            "source" to "camera2"
        )
    }

    private fun determineCameraName(facing: Int?, cameraId: String, maxInitialId: Int): String {
        val cameraIdInt = cameraId.toIntOrNull() ?: -1
        return when {
            facing == CameraCharacteristics.LENS_FACING_EXTERNAL -> "External Camera"
            facing == CameraCharacteristics.LENS_FACING_FRONT -> "Front Camera"
            facing == CameraCharacteristics.LENS_FACING_BACK -> "Back Camera"
            cameraIdInt > maxInitialId -> "External USB Camera"
            else -> "Camera $cameraId"
        }
    }

    /**
     * For each Camera2 external camera in the list, if we can match a USB device (by probing),
     * replace the generic "External Camera" name with the USB product name (e.g. "HP 4K Streaming Webcam").
     */
    private fun applyUsbProductNamesToCameraList(cameras: MutableList<Map<String, Any>>) {
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as? CameraManager ?: return
        val usbManager = context.getSystemService(Context.USB_SERVICE) as? UsbManager ?: return
        val matchedIds = mutableSetOf<String>() // avoid matching same Camera2 ID to multiple USB devices
        for (device in usbManager.deviceList.values) {
            if (!isUsbCamera(device)) continue
            val camera2Id = probeForCamera2Id(device, matchedIds, cameraManager) ?: continue
            matchedIds.add(camera2Id)
            val productName = device.productName?.takeIf { it.isNotBlank() } ?: continue
            val index = cameras.indexOfFirst { it["uniqueID"] == camera2Id }
            if (index >= 0) {
                cameras[index] = (cameras[index].toMutableMap()).apply { put("localizedName", productName) }
                Log.d(TAG, "   📝 Updated camera $camera2Id name to: $productName")
            }
        }
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
        val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
        val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        val result = mutableListOf<Map<String, Any>>()

        val devices = usbManager.deviceList.values
        Log.d(TAG, "USB devices connected: ${devices.size}")

        // Get list of Camera2 IDs that are already known
        val knownCamera2Ids = knownCamera2Cameras.mapNotNull { it["uniqueID"] as? String }.toSet()
        Log.d(TAG, "Known Camera2 IDs: ${knownCamera2Ids.joinToString()}")

        for (device in devices) {
            if (isUsbCamera(device)) {
                processUsbCamera(device, knownCamera2Ids, cameraManager, result)
            }
        }

        if (result.isNotEmpty()) {
            Log.d(TAG, "Found ${result.size} USB cameras")
        }

        return result
    }

    private fun processUsbCamera(
        device: UsbDevice,
        knownCamera2Ids: Set<String>,
        cameraManager: CameraManager,
        result: MutableList<Map<String, Any>>
    ) {
        Log.d(
            TAG,
            "USB Camera detected → vendor=${device.vendorId}, product=${device.productId}, name=${device.deviceName}"
        )

        // Try to find corresponding Camera2 ID
        val camera2Id = probeForCamera2Id(device, knownCamera2Ids, cameraManager)

        if (camera2Id != null) {
            // Camera already in list from getCamera2Cameras() as "External Camera". Do not add again.
            Log.d(TAG, "   ⏭️ USB camera already listed as Camera2 ID $camera2Id - skipping duplicate")
        } else {
            addUsbOnlyCamera(device, result)
        }
    }

    private fun addCamera2UsbCamera(device: UsbDevice, camera2Id: String, result: MutableList<Map<String, Any>>) {
        Log.d(TAG, "   ✅ Found Camera2 ID for USB camera: $camera2Id")
        result.add(
            mapOf(
                "uniqueID" to camera2Id,
                "localizedName" to (device.productName ?: "External USB Camera"),
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "deviceName" to device.deviceName,
                "source" to "camera2",
                "usbVendorId" to device.vendorId,
                "usbProductId" to device.productId
            )
        )
    }

    private fun addUsbOnlyCamera(device: UsbDevice, result: MutableList<Map<String, Any>>) {
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
            val cameraIds = cameraManager.cameraIdList
            val maxKnownId = knownCamera2Ids.mapNotNull { it.toIntOrNull() }.maxOrNull() ?: 1

            logProbeStart(usbDevice, knownCamera2Ids, cameraIds)

            // Check cameras in the official list that aren't in our known list
            val officialListResult = checkOfficialCameraList(cameraIds, knownCamera2Ids, cameraManager)
            if (officialListResult != null) return officialListResult

            // If not found in official list, probe additional IDs
            val probeResult = probeAdditionalCameraIds(maxKnownId, knownCamera2Ids, cameraIds, cameraManager)
            if (probeResult != null) return probeResult

            logNoCamera2IdFound()
            return null
        } catch (e: Exception) {
            Log.e(TAG, "   ❌ Error probing for Camera2 ID: ${e.message}")
            return null
        }
    }

    private fun logProbeStart(usbDevice: UsbDevice, knownCamera2Ids: Set<String>, cameraIds: Array<String>) {
        Log.d(
            TAG,
            "   🔍 Probing for Camera2 ID for USB camera (vendor=${usbDevice.vendorId}, " +
                "product=${usbDevice.productId})"
        )
        Log.d(TAG, "   📋 Known Camera2 IDs: ${knownCamera2Ids.joinToString()}")
        Log.d(TAG, "   📋 All Camera2 IDs in list: ${cameraIds.joinToString()}")
    }

    private fun checkOfficialCameraList(
        cameraIds: Array<String>,
        knownCamera2Ids: Set<String>,
        cameraManager: CameraManager
    ): String? {
        for (cameraId in cameraIds) {
            if (knownCamera2Ids.contains(cameraId)) {
                continue // Already accounted for
            }

            val result = checkIfExternalCamera(cameraId, cameraManager)
            if (result != null) return result
        }
        return null
    }

    private fun checkIfExternalCamera(cameraId: String, cameraManager: CameraManager): String? {
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
        return null
    }

    private fun probeAdditionalCameraIds(
        maxKnownId: Int,
        knownCamera2Ids: Set<String>,
        cameraIds: Array<String>,
        cameraManager: CameraManager
    ): String? {
        Log.d(TAG, "   🔍 Probing additional Camera2 IDs beyond official list...")
        val probeStart = maxKnownId + 1
        val probeEnd = maxKnownId + 10 // Probe up to 10 additional IDs

        for (testId in probeStart..probeEnd) {
            val testIdStr = testId.toString()

            // Skip if already in known list or official list
            if (knownCamera2Ids.contains(testIdStr) || cameraIds.contains(testIdStr)) {
                continue
            }

            val result = tryProbeCamera(testIdStr, cameraManager)
            if (result != null) return result
        }
        return null
    }

    private fun tryProbeCamera(testIdStr: String, cameraManager: CameraManager): String? {
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
            // Access denied - might need permissions, but continue
            Log.d(TAG, "   ⚠️ Access denied for camera $testIdStr: ${e.message}")
        } catch (e: Exception) {
            // Other error - continue
            Log.d(TAG, "   ⚠️ Error probing camera $testIdStr: ${e.message}")
        }
        return null
    }

    private fun logNoCamera2IdFound() {
        Log.d(TAG, "   ❌ No Camera2 ID found with LENS_FACING_EXTERNAL for USB camera")
        Log.d(TAG, "   💡 USB camera will use UVC path (usb_vendorId_productId format)")
        Log.d(TAG, "   ❌ No Camera2 ID found for USB camera")
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
        Log.d(TAG, "=== Device Camera Capabilities ===")
        logPackageManagerFeatures()
        logCameraList()
        logUsbDevices()
        Log.d(TAG, "=================================")
    }

    private fun logPackageManagerFeatures() {
        val pm = context.packageManager
        Log.d(TAG, "FEATURE_CAMERA = " + pm.hasSystemFeature(PackageManager.FEATURE_CAMERA))
        Log.d(TAG, "FEATURE_CAMERA_ANY = " + pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_ANY))
        Log.d(TAG, "FEATURE_CAMERA_EXTERNAL = " + pm.hasSystemFeature(PackageManager.FEATURE_CAMERA_EXTERNAL))
        Log.d(TAG, "FEATURE_USB_HOST = " + pm.hasSystemFeature(PackageManager.FEATURE_USB_HOST))
    }

    private fun logCameraList() {
        try {
            val cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager
            val cameraIds = cameraManager.cameraIdList
            Log.d(TAG, "Camera IDs in cameraIdList: ${cameraIds.joinToString()}")
            
            for (cameraId in cameraIds) {
                logCameraCharacteristics(cameraManager, cameraId)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error listing cameras: ${e.message}")
        }
    }

    private fun logCameraCharacteristics(cameraManager: CameraManager, cameraId: String) {
        try {
            val characteristics = cameraManager.getCameraCharacteristics(cameraId)
            val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
            val facingStr = getFacingString(facing)
            Log.d(TAG, "  Camera $cameraId: LENS_FACING=$facingStr")
        } catch (e: Exception) {
            Log.e(TAG, "  Camera $cameraId: Error getting characteristics - ${e.message}")
        }
    }

    private fun getFacingString(facing: Int?): String = when (facing) {
        CameraCharacteristics.LENS_FACING_FRONT -> "FRONT"
        CameraCharacteristics.LENS_FACING_BACK -> "BACK"
        CameraCharacteristics.LENS_FACING_EXTERNAL -> "EXTERNAL"
        else -> "UNKNOWN($facing)"
    }

    private fun logUsbDevices() {
        try {
            val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
            val devices = usbManager.deviceList.values
            Log.d(TAG, "USB Devices: ${devices.size}")
            for (device in devices) {
                logUsbDevice(device)
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error listing USB devices: ${e.message}")
        }
    }

    private fun logUsbDevice(device: UsbDevice) {
        Log.d(TAG, "  USB: ${device.deviceName}, vendor=${device.vendorId}, product=${device.productId}")
        for (i in 0 until device.interfaceCount) {
            val intf = device.getInterface(i)
            Log.d(TAG, "    Interface $i: class=${intf.interfaceClass}, subclass=${intf.interfaceSubclass}")
        }
    }
}