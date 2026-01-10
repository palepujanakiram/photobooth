package com.example.photobooth

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.camera2.CameraManager
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.annotation.RequiresApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.photobooth/camera_device_helper"
    private val CAMERA_CONTROL_CHANNEL = "com.photobooth/camera_device"
    private val USB_PERMISSION_ACTION = "com.example.photobooth.USB_PERMISSION"
    private lateinit var cameraDeviceHelper: CameraDeviceHelper
    private var androidCameraController: AndroidCameraController? = null
    private var flutterEngineInstance: FlutterEngine? = null
    private var textureRegistry: TextureRegistry? = null
    private var usbPermissionResult: MethodChannel.Result? = null
    private val usbPermissionLock = Any() // Lock object for USB permission synchronization

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngineInstance = flutterEngine
        
        // Get TextureRegistry - try multiple approaches
        // Approach 1: Try via platformViewsController (recommended way)
        try {
            val platformViewsControllerMethod = flutterEngine.javaClass.getMethod("getPlatformViewsController")
            val platformViewsController = platformViewsControllerMethod.invoke(flutterEngine)
            if (platformViewsController != null) {
                try {
                    val textureRegistryMethod = platformViewsController.javaClass.getMethod("getTextureRegistry")
                    @Suppress("UNCHECKED_CAST")
                    textureRegistry = textureRegistryMethod.invoke(platformViewsController) as? TextureRegistry
                    if (textureRegistry != null) {
                        Log.d("MainActivity", "✅ Successfully obtained TextureRegistry via platformViewsController.getTextureRegistry()")
                    }
                } catch (e: Exception) {
                    Log.d("MainActivity", "platformViewsController.getTextureRegistry() failed: ${e.message}")
                    // Try as a field
                    try {
                        val field = platformViewsController.javaClass.getDeclaredField("textureRegistry")
                        field.isAccessible = true
                        @Suppress("UNCHECKED_CAST")
                        textureRegistry = field.get(platformViewsController) as? TextureRegistry
                        if (textureRegistry != null) {
                            Log.d("MainActivity", "✅ Successfully obtained TextureRegistry via platformViewsController.textureRegistry field")
                        }
                    } catch (e2: Exception) {
                        Log.d("MainActivity", "platformViewsController.textureRegistry field failed: ${e2.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.d("MainActivity", "platformViewsController approach failed: ${e.message}")
        }
        
        // Approach 2: Try via getRenderer() -> access textureRegistry field in renderer
        if (textureRegistry == null) {
            try {
                val rendererMethod = flutterEngine.javaClass.getMethod("getRenderer")
                val renderer = rendererMethod.invoke(flutterEngine)
                if (renderer != null) {
                    // Try accessing textureRegistry as a field in the renderer
                    val rendererFieldNames = listOf("textureRegistry", "mTextureRegistry", "_textureRegistry")
                    for (fieldName in rendererFieldNames) {
                        try {
                            val field = renderer.javaClass.getDeclaredField(fieldName)
                            field.isAccessible = true
                            @Suppress("UNCHECKED_CAST")
                            textureRegistry = field.get(renderer) as? TextureRegistry
                            if (textureRegistry != null) {
                                Log.d("MainActivity", "✅ Successfully obtained TextureRegistry via renderer.$fieldName")
                                break
                            }
                        } catch (e: Exception) {
                            Log.d("MainActivity", "renderer.$fieldName field not found: ${e.message}")
                        }
                    }
                }
            } catch (e: Exception) {
                Log.d("MainActivity", "getRenderer() approach failed: ${e.message}")
            }
        }
        
        if (textureRegistry == null) {
            Log.w("MainActivity", "⚠️ Could not obtain TextureRegistry - external cameras may not work")
            Log.w("MainActivity", "   This means native camera controller cannot be used")
            Log.w("MainActivity", "   External cameras will fall back to standard CameraController (may not work)")
        }
        
        cameraDeviceHelper = CameraDeviceHelper(this)

        // Log device capabilities on startup for debugging
        cameraDeviceHelper.logDeviceCapabilities()
        
        // Register USB permission receiver
        val filter = IntentFilter(USB_PERMISSION_ACTION)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Android 13+ requires explicit export flag
            registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(usbPermissionReceiver, filter)
        }

        // Channel for camera discovery
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllAvailableCameras" -> {
                    Log.d("MainActivity", "📸 getAllAvailableCameras called from Flutter")
                    cameraDeviceHelper.getAllAvailableCameras(result)
                }
                "logDiagnostics" -> {
                    Log.d("MainActivity", "🔍 Logging diagnostics")
                    cameraDeviceHelper.logDeviceCapabilities()
                    result.success(mapOf("success" to true))
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Channel for camera control (same as iOS for consistency)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CAMERA_CONTROL_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeCamera" -> {
                    val args = call.arguments as? Map<*, *>
                    val deviceId = args?.get("deviceId") as? String
                    if (deviceId == null) {
                        result.error("INVALID_ARGS", "deviceId is required", null)
                        return@setMethodCallHandler
                    }
                    initializeCamera(deviceId, result)
                }
                "startPreview" -> {
                    startPreview(result)
                }
                "takePicture" -> {
                    takePicture(result)
                }
                "disposeCamera" -> {
                    disposeCamera(result)
                }
                "requestUsbPermission" -> {
                    val args = call.arguments as? Map<*, *>
                    val vendorId = args?.get("vendorId") as? Int
                    val productId = args?.get("productId") as? Int
                    if (vendorId == null || productId == null) {
                        result.error("INVALID_ARGS", "vendorId and productId are required", null)
                        return@setMethodCallHandler
                    }
                    requestUsbPermission(vendorId, productId, result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            try {
                if (USB_PERMISSION_ACTION == intent.action) {
                    Log.d("MainActivity", "📨 USB permission BroadcastReceiver triggered")
                    synchronized(usbPermissionLock) {
                        try {
                            val device: UsbDevice? = try {
                                intent.getParcelableExtra(UsbManager.EXTRA_DEVICE, UsbDevice::class.java)
                            } catch (e: Exception) {
                                Log.w("MainActivity", "⚠️ Error getting device from intent: ${e.message}")
                                null
                            }
                            val permissionGranted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                            
                            Log.d("MainActivity", "   Permission granted: $permissionGranted")
                            Log.d("MainActivity", "   Device: ${device?.deviceName ?: "null"}")
                            Log.d("MainActivity", "   Result callback available: ${usbPermissionResult != null}")
                            
                            // Get the result callback and clear it immediately to prevent double calls
                            val resultToCall = usbPermissionResult
                            usbPermissionResult = null
                            
                            if (resultToCall == null) {
                                Log.w("MainActivity", "⚠️ USB permission result received but no callback available")
                                Log.w("MainActivity", "   This may happen if the callback was already called or cleared")
                                return@synchronized
                            }
                    
                    if (permissionGranted) {
                        // Try to get device from intent first
                        var targetDevice: UsbDevice? = device
                        var deviceName: String? = device?.deviceName
                        
                        // If device is null in intent, try to find it by vendor/product ID
                        if (targetDevice == null) {
                            Log.w("MainActivity", "⚠️ Device is null in intent, trying to find by vendor/product ID")
                            val vendorId = intent.getIntExtra("vendorId", -1)
                            val productId = intent.getIntExtra("productId", -1)
                            if (vendorId != -1 && productId != -1) {
                                val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
                                targetDevice = usbManager.deviceList.values.find {
                                    it.vendorId == vendorId && it.productId == productId
                                }
                                if (targetDevice != null) {
                                    deviceName = targetDevice.deviceName
                                    Log.d("MainActivity", "✅ Found device by vendor/product ID: $deviceName")
                                } else {
                                    Log.w("MainActivity", "⚠️ Device not found in deviceList by vendor/product ID")
                                }
                            } else {
                                Log.w("MainActivity", "⚠️ No vendor/product ID in intent to find device")
                            }
                        }
                        
                        // If we have a device, verify permission and open it
                        if (targetDevice != null) {
                            try {
                                val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
                                // Double-check permission
                                if (usbManager.hasPermission(targetDevice)) {
                                    Log.d("MainActivity", "✅ USB permission confirmed for device: ${targetDevice.deviceName}")
                                    // Try to open the device to ensure it's accessible
                                    // This helps the plugin access the device
                                    try {
                                        val usbConnection = usbManager.openDevice(targetDevice)
                                        if (usbConnection != null) {
                                            Log.d("MainActivity", "✅ USB device opened successfully after permission grant")
                                            usbConnection.close() // Close immediately - plugin will open it when needed
                                        }
                                    } catch (e: Exception) {
                                        Log.w("MainActivity", "⚠️ Could not open USB device (may be normal): ${e.message}")
                                    }
                                    try {
                                        resultToCall.success(mapOf("granted" to true, "deviceName" to (deviceName ?: targetDevice.deviceName)))
                                        Log.d("MainActivity", "   ✅ Result sent to Flutter (permission granted)")
                                    } catch (e: Exception) {
                                        Log.e("MainActivity", "❌ Error calling result.success(): ${e.message}", e)
                                    }
                                } else {
                                    Log.e("MainActivity", "❌ Permission reported as granted but hasPermission() returns false")
                                    try {
                                        resultToCall.error("USB_ERROR", "Permission verification failed", null)
                                    } catch (e: Exception) {
                                        Log.e("MainActivity", "❌ Error calling result.error(): ${e.message}", e)
                                    }
                                }
                            } catch (e: Exception) {
                                Log.e("MainActivity", "❌ Exception verifying USB permission: ${e.message}", e)
                                try {
                                    resultToCall.error("USB_ERROR", "Exception verifying permission: ${e.message}", null)
                                } catch (callbackError: Exception) {
                                    Log.e("MainActivity", "❌ Error calling result.error(): ${callbackError.message}")
                                }
                            }
                        } else {
                            // Device is null and we couldn't find it - but permission was granted
                            // This might happen if the device was disconnected or the system didn't include it
                            Log.w("MainActivity", "⚠️ USB permission granted but device is null and could not be found")
                            Log.w("MainActivity", "   This may happen if device was disconnected or system didn't include device in intent")
                            // Still report success since permission was granted - the plugin will handle device detection
                            try {
                                resultToCall.success(mapOf("granted" to true, "deviceName" to "unknown"))
                                Log.d("MainActivity", "   ✅ Result sent to Flutter (permission granted, device unknown)")
                            } catch (e: Exception) {
                                Log.e("MainActivity", "❌ Error calling result.success(): ${e.message}", e)
                            }
                        }
                    } else {
                        // Permission denied or dialog dismissed
                        val vendorId = intent.getIntExtra("vendorId", -1)
                        val productId = intent.getIntExtra("productId", -1)
                        val deviceName = if (device != null) {
                            device.deviceName
                        } else if (vendorId != -1 && productId != -1) {
                            // Try to find device by vendor/product ID
                            val usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager
                            val matchingDevice = usbManager.deviceList.values.find {
                                it.vendorId == vendorId && it.productId == productId
                            }
                            matchingDevice?.deviceName ?: "unknown"
                        } else {
                            "unknown"
                        }
                        
                        // Check if dialog was dismissed (device is null and permission is false)
                        val wasDismissed = (device == null && vendorId != -1 && productId != -1)
                        
                        if (wasDismissed) {
                            Log.e("MainActivity", "❌ USB permission dialog was dismissed (not denied) for device: $deviceName")
                            Log.e("MainActivity", "   ⚠️ The permission dialog was closed without selecting 'Allow' or 'Deny'")
                            Log.e("MainActivity", "   💡 This happens when:")
                            Log.e("MainActivity", "      - You pressed the back button")
                            Log.e("MainActivity", "      - You tapped outside the dialog")
                            Log.e("MainActivity", "      - The dialog was closed by the system")
                            Log.e("MainActivity", "   💡 To fix this:")
                            Log.e("MainActivity", "      1. Select the external camera again")
                            Log.e("MainActivity", "      2. When the permission dialog appears, tap 'OK' or 'Allow'")
                            Log.e("MainActivity", "      3. Do NOT dismiss the dialog - you must explicitly grant permission")
                            val errorMessage = "USB permission dialog was dismissed. " +
                                    "Please select the external camera again and tap 'OK' or 'Allow' when the permission dialog appears. " +
                                    "Do not dismiss the dialog - you must explicitly grant permission."
                            try {
                                resultToCall.error("USB_PERMISSION_DISMISSED", errorMessage, null)
                                Log.d("MainActivity", "   ✅ Result sent to Flutter (dialog dismissed)")
                            } catch (e: Exception) {
                                Log.e("MainActivity", "❌ Error calling result.error(): ${e.message}", e)
                            }
                        } else {
                            Log.e("MainActivity", "❌ USB permission denied for device: $deviceName")
                            Log.e("MainActivity", "   💡 The USB permission dialog was explicitly denied")
                            Log.e("MainActivity", "   💡 To fix this:")
                            Log.e("MainActivity", "      1. Unplug the USB camera")
                            Log.e("MainActivity", "      2. Replug the USB camera")
                            Log.e("MainActivity", "      3. When the permission dialog appears, tap 'OK' or 'Allow'")
                            Log.e("MainActivity", "      4. Or go to: Settings → Apps → Photo Booth → Permissions → USB")
                            val errorMessage = "USB permission denied for the external camera. " +
                                    "Please unplug and replug the USB camera, then grant permission when the dialog appears. " +
                                    "Alternatively, go to Settings → Apps → Photo Booth → Permissions → USB to grant permission."
                            try {
                                resultToCall.error("USB_PERMISSION_DENIED", errorMessage, null)
                                Log.d("MainActivity", "   ✅ Result sent to Flutter (permission denied)")
                            } catch (e: Exception) {
                                Log.e("MainActivity", "❌ Error calling result.error(): ${e.message}", e)
                            }
                        }
                    }
                        } catch (e: Exception) {
                            Log.e("MainActivity", "❌ Exception in USB permission BroadcastReceiver: ${e.message}", e)
                            // Try to send error to callback if available
                            val resultToCall = usbPermissionResult
                            usbPermissionResult = null
                            try {
                                resultToCall?.error("USB_ERROR", "Exception handling USB permission: ${e.message}", null)
                            } catch (callbackError: Exception) {
                                Log.e("MainActivity", "❌ Error calling result.error(): ${callbackError.message}")
                            }
                        }
                    }
                } else {
                    Log.d("MainActivity", "📨 BroadcastReceiver received intent with different action: ${intent.action}")
                }
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Exception in USB permission BroadcastReceiver (outer): ${e.message}", e)
            }
        }
    }
    
    private fun requestUsbPermission(vendorId: Int, productId: Int, result: MethodChannel.Result) {
        try {
            val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
            val usbDevices = usbManager.deviceList
            
            // Log all connected USB devices for debugging
            Log.d("MainActivity", "📋 Connected USB devices:")
            for (device in usbDevices.values) {
                Log.d("MainActivity", "   - ${device.deviceName} (vendor=${device.vendorId}, product=${device.productId})")
            }
            
            // Find matching USB device
            val matchingDevice = usbDevices.values.find { 
                it.vendorId == vendorId && it.productId == productId 
            }
            
            if (matchingDevice == null) {
                Log.e("MainActivity", "❌ USB device not found (vendor=$vendorId, product=$productId)")
                Log.e("MainActivity", "   💡 Please ensure the USB camera is connected")
                Log.e("MainActivity", "   💡 Try unplugging and replugging the USB camera")
                result.error("USB_DEVICE_NOT_FOUND", "USB device not found. Please ensure the USB camera is connected and try unplugging and replugging it.", null)
                return
            }
            
            Log.d("MainActivity", "✅ Found USB device: ${matchingDevice.deviceName}")
            Log.d("MainActivity", "   Device class: ${matchingDevice.deviceClass}")
            Log.d("MainActivity", "   Device subclass: ${matchingDevice.deviceSubclass}")
            Log.d("MainActivity", "   Device protocol: ${matchingDevice.deviceProtocol}")
            
            // Check if permission is already granted
            if (usbManager.hasPermission(matchingDevice)) {
                Log.d("MainActivity", "✅ USB permission already granted for device: ${matchingDevice.deviceName}")
                // Try to open the device to ensure it's accessible
                // This helps the plugin access the device
                // Note: We open and immediately close to verify accessibility
                // The plugin will open it again when needed
                try {
                    val usbConnection = usbManager.openDevice(matchingDevice)
                    if (usbConnection != null) {
                        Log.d("MainActivity", "✅ USB device opened successfully")
                        // Keep connection open briefly to ensure plugin can detect it
                        // Then close it - the plugin will open it when needed
                        Thread.sleep(100) // Brief delay to ensure device is ready
                        usbConnection.close()
                        Log.d("MainActivity", "✅ USB device connection closed (plugin will reopen)")
                    } else {
                        Log.w("MainActivity", "⚠️ Could not open USB device (connection is null)")
                    }
                } catch (e: Exception) {
                    Log.w("MainActivity", "⚠️ Could not open USB device: ${e.message}")
                    // Even if opening fails, permission is granted, so return success
                }
                result.success(mapOf("granted" to true, "deviceName" to matchingDevice.deviceName))
                return
            }
            
            // Request permission
            Log.d("MainActivity", "🔐 Requesting USB permission for device: ${matchingDevice.deviceName}")
            Log.d("MainActivity", "   Device info:")
            Log.d("MainActivity", "     - Vendor ID: ${matchingDevice.vendorId}")
            Log.d("MainActivity", "     - Product ID: ${matchingDevice.productId}")
            Log.d("MainActivity", "     - Device Class: ${matchingDevice.deviceClass}")
            Log.d("MainActivity", "     - Device Subclass: ${matchingDevice.deviceSubclass}")
            Log.d("MainActivity", "     - Device Protocol: ${matchingDevice.deviceProtocol}")
            
            // Ensure activity is in the foreground so the permission dialog is visible
            // This is important because the dialog needs the activity to be active
            runOnUiThread {
                if (!isFinishing && !isDestroyed) {
                    // Check if activity has window focus - if not, log a warning
                    if (!hasWindowFocus()) {
                        Log.w("MainActivity", "   ⚠️ Activity may not be in focus - permission dialog may not be visible")
                        Log.w("MainActivity", "   💡 Please ensure the app is in the foreground when requesting USB permission")
                    } else {
                        Log.d("MainActivity", "   ✅ Activity is in focus - permission dialog should be visible")
                    }
                }
            }
            
            Log.d("MainActivity", "   💡 A USB permission dialog will appear - please tap 'OK' or 'Allow'")
            Log.d("MainActivity", "   ⚠️ IMPORTANT: Do not dismiss the dialog - you must tap 'OK' or 'Allow' to grant permission")
            
            // Store the result callback - it will be called by the BroadcastReceiver
            synchronized(usbPermissionLock) {
                // Clear any previous pending result to avoid conflicts
                val previousResult = usbPermissionResult
                if (previousResult != null) {
                    Log.w("MainActivity", "⚠️ Previous USB permission request still pending - cancelling it")
                    try {
                        previousResult.error("USB_ERROR", "New permission request initiated", null)
                    } catch (e: Exception) {
                        Log.w("MainActivity", "⚠️ Error cancelling previous result: ${e.message}")
                    }
                }
                usbPermissionResult = result
                Log.d("MainActivity", "   📝 Stored result callback for USB permission request")
            }
            
            // Use unique request code based on vendor/product ID to ensure unique PendingIntent
            val requestCode = (vendorId shl 16) or productId
            val permissionIntent = PendingIntent.getBroadcast(
                this, requestCode, Intent(USB_PERMISSION_ACTION).apply {
                    putExtra("vendorId", vendorId)
                    putExtra("productId", productId)
                },
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            
            try {
                // requestPermission() is a void method - it will trigger the BroadcastReceiver when user responds
                // The dialog will appear if permission is not already granted
                // IMPORTANT: The dialog must be shown and the user must respond (Allow or Deny)
                // If the dialog is dismissed (back button, outside tap), permission will be denied
                Log.d("MainActivity", "   📤 Calling usbManager.requestPermission()...")
                Log.d("MainActivity", "   💡 This will show a system dialog - the activity must be in the foreground")
                Log.d("MainActivity", "   ⏳ Waiting for user to respond to the permission dialog...")
                Log.d("MainActivity", "   ⚠️ The dialog will appear shortly - please tap 'OK' or 'Allow' to grant permission")
                
                usbManager.requestPermission(matchingDevice, permissionIntent)
                
                Log.d("MainActivity", "   ✅ Permission request sent successfully")
                Log.d("MainActivity", "   ⏳ Waiting for user response via BroadcastReceiver...")
                Log.d("MainActivity", "   💡 The BroadcastReceiver will be triggered when user responds to the dialog")
                Log.d("MainActivity", "   ⚠️ If you dismiss the dialog (back button or outside tap), permission will be denied")
                // Note: The result will be sent asynchronously via usbPermissionReceiver
                // Do NOT call result.success() or result.error() here - let the receiver handle it
            } catch (e: Exception) {
                Log.e("MainActivity", "❌ Exception calling requestPermission: ${e.message}", e)
                Log.e("MainActivity", "   Stack trace: ${e.stackTraceToString()}")
                synchronized(usbPermissionLock) {
                    val resultToCall = usbPermissionResult
                    usbPermissionResult = null
                    try {
                        resultToCall?.error("USB_ERROR", "Exception requesting USB permission: ${e.message}", null)
                    } catch (callbackError: Exception) {
                        Log.e("MainActivity", "❌ Error calling result callback: ${callbackError.message}")
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error requesting USB permission: ${e.message}", e)
            result.error("USB_ERROR", "Failed to request USB permission: ${e.message}", null)
        }
    }

    private fun initializeCamera(deviceId: String, result: MethodChannel.Result) {
        try {
            // Dispose existing controller if any
            androidCameraController?.dispose()
            
            // Check if deviceId is in USB format (usb_vendorId_productId)
            var actualCameraId = deviceId
            if (deviceId.startsWith("usb_")) {
                Log.d("MainActivity", "🔌 USB camera ID detected: $deviceId")
                // Extract vendor and product IDs
                val parts = deviceId.removePrefix("usb_").split("_")
                if (parts.size == 2) {
                    val vendorId = parts[0].toIntOrNull()
                    val productId = parts[1].toIntOrNull()
                    
                    if (vendorId != null && productId != null) {
                        Log.d("MainActivity", "   Vendor ID: $vendorId, Product ID: $productId")
                        
                        // Try to find the USB device and get its Camera2 ID
                        val usbManager = getSystemService(Context.USB_SERVICE) as android.hardware.usb.UsbManager
                        val usbDevices = usbManager.deviceList
                        
                        // Find matching USB device
                        val matchingUsbDevice = usbDevices.values.find { 
                            it.vendorId == vendorId && it.productId == productId 
                        }
                        
                        if (matchingUsbDevice != null) {
                            Log.d("MainActivity", "   ✅ Found matching USB device: ${matchingUsbDevice.deviceName}")
                            
                            // Try to find Camera2 ID for this USB device
                            val cameraManager = getSystemService(Context.CAMERA_SERVICE) as android.hardware.camera2.CameraManager
                            val knownCamera2Ids = cameraManager.cameraIdList.toSet()
                            
                            // Use CameraDeviceHelper's probe method to find Camera2 ID
                            val camera2Id = cameraDeviceHelper.probeForCamera2Id(matchingUsbDevice, knownCamera2Ids, cameraManager)
                            
                            if (camera2Id != null) {
                                Log.d("MainActivity", "   ✅ Found Camera2 ID for USB camera: $camera2Id")
                                actualCameraId = camera2Id
                            } else {
                                Log.e("MainActivity", "   ❌ No Camera2 ID found for USB camera")
                                result.error(
                                    "USB_CAMERA_NO_CAMERA2_ID",
                                    "USB camera (vendor=$vendorId, product=$productId) does not have a Camera2 API ID. " +
                                    "The camera may need time to enumerate, or it may require UVC (USB Video Class) support.",
                                    null
                                )
                                return
                            }
                        } else {
                            Log.e("MainActivity", "   ❌ USB device not found (vendor=$vendorId, product=$productId)")
                            result.error(
                                "USB_DEVICE_NOT_FOUND",
                                "USB device (vendor=$vendorId, product=$productId) not found. Please ensure the device is connected.",
                                null
                            )
                            return
                        }
                    } else {
                        Log.e("MainActivity", "   ❌ Invalid USB ID format: $deviceId")
                        result.error("INVALID_USB_ID", "Invalid USB camera ID format: $deviceId. Expected format: usb_vendorId_productId", null)
                        return
                    }
                } else {
                    Log.e("MainActivity", "   ❌ Invalid USB ID format: $deviceId")
                    result.error("INVALID_USB_ID", "Invalid USB camera ID format: $deviceId. Expected format: usb_vendorId_productId", null)
                    return
                }
            }
            
            // Use stored TextureRegistry or try to get it via reflection as fallback
            val registry = textureRegistry ?: run {
                val engine = flutterEngineInstance ?: flutterEngine
                if (engine == null) {
                    result.error("INIT_ERROR", "Flutter engine not available", null)
                    return
                }
                
                // Fallback: Try reflection if stored approach didn't work
                // Method 1: Try to get it via getRenderer() -> getTextureRegistry()
                try {
                    val rendererMethod = engine.javaClass.getMethod("getRenderer")
                    val renderer = rendererMethod.invoke(engine)
                    if (renderer != null) {
                        val textureRegistryMethod = renderer.javaClass.getMethod("getTextureRegistry")
                        @Suppress("UNCHECKED_CAST")
                        val reg = textureRegistryMethod.invoke(renderer) as? TextureRegistry
                        if (reg != null) {
                            Log.d("MainActivity", "✅ Successfully accessed textureRegistry via getRenderer().getTextureRegistry()")
                            return@run reg
                        }
                    }
                } catch (e: Exception) {
                    Log.d("MainActivity", "Method 1 (getRenderer) failed: ${e.message}")
                }
                
                // Method 2: Try direct field access with different possible field names
                val fieldNames = listOf("textureRegistry", "mTextureRegistry", "_textureRegistry")
                for (fieldName in fieldNames) {
                    try {
                        val field = engine.javaClass.getDeclaredField(fieldName)
                        field.isAccessible = true
                        @Suppress("UNCHECKED_CAST")
                        val reg = field.get(engine) as? TextureRegistry
                        if (reg != null) {
                            Log.d("MainActivity", "✅ Successfully accessed textureRegistry via field: $fieldName")
                            return@run reg
                        }
                    } catch (e: Exception) {
                        // Continue to next field name
                        Log.d("MainActivity", "Field $fieldName not found: ${e.message}")
                    }
                }
                
                null
            }
            
            if (registry == null) {
                result.error("INIT_ERROR", "Texture registry not available. Please ensure Flutter engine is properly initialized.", null)
                return
            }
            
            Log.d("MainActivity", "🎥 Initializing camera with ID: $actualCameraId (original: $deviceId)")
            androidCameraController = AndroidCameraController(this, registry)
            androidCameraController?.initialize(actualCameraId, result)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error initializing camera: ${e.message}", e)
            result.error("INIT_ERROR", "Failed to initialize camera: ${e.message}", null)
        }
    }

    private fun startPreview(result: MethodChannel.Result) {
        val controller = androidCameraController
        if (controller == null) {
            result.error("NOT_INITIALIZED", "Camera not initialized", null)
            return
        }
        controller.startPreview(result)
    }

    private fun takePicture(result: MethodChannel.Result) {
        val controller = androidCameraController
        if (controller == null) {
            result.error("NOT_INITIALIZED", "Camera not initialized", null)
            return
        }
        controller.takePicture(result)
    }

    private fun disposeCamera(result: MethodChannel.Result) {
        androidCameraController?.dispose()
        androidCameraController = null
        result.success(mapOf("success" to true))
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Unregister USB permission receiver
        try {
            unregisterReceiver(usbPermissionReceiver)
        } catch (e: Exception) {
            // Receiver might not be registered
        }
        // Dispose camera controller
        androidCameraController?.dispose()
        androidCameraController = null
    }
}