package com.example.photobooth

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.os.Build
import android.os.Build.VERSION_CODES
import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.photobooth/camera_device_helper"
    private val CAMERA_CONTROL_CHANNEL = "com.photobooth/camera_device"
    private val UVC_CAMERA_CHANNEL = "com.photobooth/uvc_camera"
    private val UVC_EVENT_CHANNEL = "com.photobooth/uvc_camera_events"
    private var uvcEventSink: EventChannel.EventSink? = null
    private lateinit var cameraDeviceHelper: CameraDeviceHelper
    private var androidCameraController: AndroidCameraController? = null
    private var uvcCameraController: UvcCameraController? = null
    private var flutterEngineInstance: FlutterEngine? = null
    private var textureRegistry: TextureRegistry? = null
    private var pendingUvcInit: Pair<Int, Int>? = null // Store vendorId, productId for pending initialization
    private var pendingUvcResult: MethodChannel.Result? = null
    private var isProactivePermissionRequest: Boolean = false // Flag to distinguish proactive permission requests from initialization
    private val ACTION_USB_PERMISSION = "com.example.photobooth.USB_PERMISSION"
    
    // USB permission receiver
    private val usbPermissionReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            Log.d("MainActivity", "📨 BroadcastReceiver.onReceive called: action=${intent.action}")
            if (ACTION_USB_PERMISSION == intent.action) {
                val device: UsbDevice? = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE)
                val permissionGranted = intent.getBooleanExtra(UsbManager.EXTRA_PERMISSION_GRANTED, false)
                Log.d("MainActivity", "   📋 USB permission result: granted=$permissionGranted, device=${device?.deviceName}")
                
                if (permissionGranted) {
                    device?.let {
                        Log.d("MainActivity", "✅ USB permission granted for device: ${it.deviceName}")
                        Log.d("MainActivity", "   Device vendor ID: ${it.vendorId}, product ID: ${it.productId}")
                        // If we have a pending request, handle it
                        pendingUvcInit?.let { (vendorId, productId) ->
                            Log.d("MainActivity", "   Checking pending request: vendor=$vendorId, product=$productId")
                            if (it.vendorId == vendorId && it.productId == productId) {
                                // Check if this is a proactive permission request or initialization
                                if (isProactivePermissionRequest) {
                                    Log.d("MainActivity", "   ✅ Device matches! Permission granted (proactive request)...")
                                    pendingUvcResult?.success(mapOf("success" to true, "alreadyGranted" to false))
                                } else {
                                    Log.d("MainActivity", "   ✅ Device matches! Proceeding with UVC initialization...")
                                    initializeUvcCameraInternal(vendorId, productId, pendingUvcResult)
                                }
                                pendingUvcInit = null
                                pendingUvcResult = null
                                isProactivePermissionRequest = false
                            } else {
                                Log.w("MainActivity", "   ⚠️ Device mismatch: expected vendor=$vendorId, product=$productId, got vendor=${it.vendorId}, product=${it.productId}")
                            }
                        } ?: run {
                            Log.w("MainActivity", "   ⚠️ No pending USB request found")
                        }
                    } ?: run {
                        Log.e("MainActivity", "   ❌ Device is null in permission result")
                        pendingUvcResult?.error("USB_PERMISSION", "USB device is null in permission result", null)
                        pendingUvcInit = null
                        pendingUvcResult = null
                    }
                } else {
                    Log.e("MainActivity", "❌ USB permission denied for device: ${device?.deviceName}")
                    pendingUvcResult?.error("USB_PERMISSION", "USB permission denied by user", null)
                    pendingUvcInit = null
                    pendingUvcResult = null
                }
            } else {
                Log.d("MainActivity", "   ⚠️ Received broadcast with different action: ${intent.action}")
            }
        }
    }

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
        Log.d("MainActivity", "🔧 Registering USB permission BroadcastReceiver...")
        val filter = IntentFilter(ACTION_USB_PERMISSION)
        try {
            if (Build.VERSION.SDK_INT >= VERSION_CODES.TIRAMISU) {
                // Android 13+ (API 33+) requires explicit export flag
                // RECEIVER_NOT_EXPORTED = 0x00000002 (not accessible to other apps)
                registerReceiver(usbPermissionReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
                Log.d("MainActivity", "   ✅ BroadcastReceiver registered (Android 13+)")
            } else {
                registerReceiver(usbPermissionReceiver, filter)
                Log.d("MainActivity", "   ✅ BroadcastReceiver registered (Android < 13)")
            }
        } catch (e: Exception) {
            Log.e("MainActivity", "   ❌ Failed to register BroadcastReceiver: ${e.message}", e)
        }

        // Event channel for UVC camera events (USB disconnection, etc.)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, UVC_EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    Log.d("MainActivity", "📡 UVC event channel listener attached")
                    uvcEventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    Log.d("MainActivity", "📡 UVC event channel listener cancelled")
                    uvcEventSink = null
                }
            }
        )

        // Channel for camera discovery
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getAllAvailableCameras" -> {
                    Log.d("MainActivity", "📸 getAllAvailableCameras called from Flutter")
                    cameraDeviceHelper.getAllAvailableCameras(result)
                }
                "forceCamera2Enumeration" -> {
                    val args = call.arguments as? Map<*, *>
                    val vendorId = args?.get("vendorId") as? Int ?: 0
                    val productId = args?.get("productId") as? Int ?: 0
                    Log.d("MainActivity", "🔄 forceCamera2Enumeration called: vendor=$vendorId, product=$productId")
                    cameraDeviceHelper.forceCamera2Enumeration(vendorId, productId, result)
                }
                "getUsbIdsForCameraId" -> {
                    val args = call.arguments as? Map<*, *>
                    val cameraId = args?.get("cameraId") as? String
                    if (cameraId == null) {
                        result.error("INVALID_ARGS", "cameraId is required", null)
                        return@setMethodCallHandler
                    }
                    Log.d("MainActivity", "🔍 getUsbIdsForCameraId called: cameraId=$cameraId")
                    cameraDeviceHelper.getUsbIdsForCameraId(cameraId, result)
                }
                "getUvcCameras" -> {
                    Log.d("MainActivity", "📸 getUvcCameras called from Flutter")
                    getUvcCameras(result)
                }
                "requestUsbPermission" -> {
                    val vendorId = call.argument<Int>("vendorId")
                    val productId = call.argument<Int>("productId")
                    if (vendorId != null && productId != null) {
                        Log.d("MainActivity", "📋 Requesting USB permission proactively: vendor=$vendorId, product=$productId")
                        requestUsbPermissionProactively(vendorId, productId, result)
                    } else {
                        result.error("INVALID_ARGUMENTS", "Vendor ID or Product ID is null", null)
                    }
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
                else -> {
                    result.notImplemented()
                }
            }
        }

        // Channel for UVC camera control
        Log.d("MainActivity", "🔧 Setting up UVC camera method channel: $UVC_CAMERA_CHANNEL")
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, UVC_CAMERA_CHANNEL).setMethodCallHandler { call, result ->
            Log.d("MainActivity", "📞 UVC method channel called: method=${call.method}")
            when (call.method) {
                "initializeUvcCamera" -> {
                    Log.d("MainActivity", "   📋 Parsing arguments...")
                    val args = call.arguments as? Map<*, *>
                    val vendorId = args?.get("vendorId") as? Int
                    val productId = args?.get("productId") as? Int
                    Log.d("MainActivity", "   📋 Parsed: vendorId=$vendorId, productId=$productId")
                    if (vendorId == null || productId == null) {
                        Log.e("MainActivity", "   ❌ Invalid arguments: vendorId=$vendorId, productId=$productId")
                        result.error("INVALID_ARGS", "vendorId and productId are required", null)
                        return@setMethodCallHandler
                    }
                    Log.d("MainActivity", "   ✅ Calling initializeUvcCamera...")
                    initializeUvcCamera(vendorId, productId, result)
                }
                "startUvcPreview" -> {
                    startUvcPreview(result)
                }
                "captureUvcPhoto" -> {
                    captureUvcPhoto(result)
                }
                "disposeUvcCamera" -> {
                    disposeUvcCamera(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun initializeCamera(deviceId: String, result: MethodChannel.Result) {
        try {
            // Dispose existing controller if any
            androidCameraController?.dispose()
            
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
            
            androidCameraController = AndroidCameraController(this, registry)
            androidCameraController?.initialize(deviceId, result)
        } catch (e: Exception) {
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
    
    /**
     * Get list of UVC cameras via USB enumeration
     */
    private fun getUvcCameras(result: MethodChannel.Result) {
        try {
            val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
            val devices = usbManager.deviceList
            val uvcCameras = mutableListOf<Map<String, Any>>()

            Log.d("MainActivity", "🔍 Enumerating USB devices for UVC cameras...")
            Log.d("MainActivity", "   Found ${devices.size} USB devices")

            for (device in devices.values) {
                if (UvcCameraController.isUvcCamera(device)) {
                    val hasPermission = usbManager.hasPermission(device)
                    Log.d("MainActivity", "   ✅ UVC Camera found: ${device.deviceName}")
                    Log.d("MainActivity", "      Vendor ID: ${device.vendorId}, Product ID: ${device.productId}")
                    Log.d("MainActivity", "      Has permission: $hasPermission")

                    uvcCameras.add(mapOf(
                        "vendorId" to device.vendorId,
                        "productId" to device.productId,
                        "deviceName" to (device.deviceName ?: "Unknown"),
                        "productName" to (device.productName ?: "USB Camera"),
                        "hasPermission" to hasPermission
                    ))
                }
            }

            Log.d("MainActivity", "📸 Found ${uvcCameras.size} UVC camera(s)")
            result.success(uvcCameras)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error getting UVC cameras: ${e.message}", e)
            result.error("UVC_ERROR", "Failed to get UVC cameras: ${e.message}", null)
        }
    }

    /**
     * Request USB permission proactively for a connected camera
     */
    private fun requestUsbPermissionProactively(vendorId: Int, productId: Int, result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "📋 Requesting USB permission proactively: vendor=$vendorId, product=$productId")
            
            val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
            val devices = usbManager.deviceList
            
            // Find the USB device
            var targetDevice: UsbDevice? = null
            for (device in devices.values) {
                if (device.vendorId == vendorId && device.productId == productId) {
                    targetDevice = device
                    break
                }
            }
            
            if (targetDevice == null) {
                result.error("DEVICE_NOT_FOUND", "UVC camera not found (vendor=$vendorId, product=$productId)", null)
                return
            }
            
            // Check if permission is already granted
            if (usbManager.hasPermission(targetDevice)) {
                Log.d("MainActivity", "✅ USB permission already granted")
                result.success(mapOf("success" to true, "alreadyGranted" to true))
                return
            }
            
            // Request permission
            Log.d("MainActivity", "   ⚠️ USB permission not granted, requesting...")
            Log.d("MainActivity", "   📋 Target device: ${targetDevice.deviceName}, vendor=${targetDevice.vendorId}, product=${targetDevice.productId}")
            
            // Store result to return in BroadcastReceiver
            pendingUvcInit = Pair(vendorId, productId)
            pendingUvcResult = result
            isProactivePermissionRequest = true // Mark as proactive permission request
            
            val permissionIntent = PendingIntent.getBroadcast(
                this,
                0,
                Intent(ACTION_USB_PERMISSION).apply {
                    putExtra(UsbManager.EXTRA_DEVICE, targetDevice)
                },
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
            
            Log.d("MainActivity", "   📋 Requesting USB permission via UsbManager...")
            usbManager.requestPermission(targetDevice, permissionIntent)
            Log.d("MainActivity", "   📋 USB permission request sent - dialog should appear now")
            
            // Start a background thread to check permission status after a delay
            // This is a fallback in case the BroadcastReceiver doesn't fire
            Thread {
                Thread.sleep(5000) // Wait 5 seconds for user to interact with dialog
                // Check if permission was granted
                if (usbManager.hasPermission(targetDevice)) {
                    Log.d("MainActivity", "   ✅ USB permission granted (checked after delay)")
                    runOnUiThread {
                        if (pendingUvcInit != null && pendingUvcResult != null) {
                            val (vId, pId) = pendingUvcInit!!
                            if (vId == vendorId && pId == productId) {
                                pendingUvcResult?.success(mapOf("success" to true, "alreadyGranted" to false))
                                pendingUvcInit = null
                                pendingUvcResult = null
                            }
                        }
                    }
                } else {
                    Log.d("MainActivity", "   ❌ USB permission still not granted after 5s fallback.")
                    runOnUiThread {
                        if (pendingUvcInit != null && pendingUvcResult != null) {
                            val (vId, pId) = pendingUvcInit!!
                            if (vId == vendorId && pId == productId) {
                                pendingUvcResult?.error("USB_PERMISSION_TIMEOUT", "USB permission not granted within timeout", null)
                                pendingUvcInit = null
                                pendingUvcResult = null
                            }
                        }
                    }
                }
            }.start()
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error requesting USB permission: ${e.message}", e)
            result.error("USB_ERROR", "Failed to request USB permission: ${e.message}", null)
        }
    }

    /**
     * Initialize UVC camera by vendor and product ID
     */
    private fun initializeUvcCamera(vendorId: Int, productId: Int, result: MethodChannel.Result) {
        try {
            Log.d("MainActivity", "🎥 Initializing UVC camera: vendor=$vendorId, product=$productId")

            val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
            val devices = usbManager.deviceList

            // Find the USB device
            var targetDevice: UsbDevice? = null
            for (device in devices.values) {
                if (device.vendorId == vendorId && device.productId == productId) {
                    targetDevice = device
                    break
                }
            }

            if (targetDevice == null) {
                result.error("DEVICE_NOT_FOUND", "UVC camera not found (vendor=$vendorId, product=$productId)", null)
                return
            }

            // Check permission
            if (!usbManager.hasPermission(targetDevice)) {
                Log.d("MainActivity", "   ⚠️ USB permission not granted, requesting...")
                Log.d("MainActivity", "   📋 Target device: ${targetDevice.deviceName}, vendor=${targetDevice.vendorId}, product=${targetDevice.productId}")
                
                // Request permission
                pendingUvcInit = Pair(vendorId, productId)
                pendingUvcResult = result
                isProactivePermissionRequest = false // This is initialization, not proactive request
                
                val permissionIntent = PendingIntent.getBroadcast(
                    this,
                    0,
                    Intent(ACTION_USB_PERMISSION).apply {
                        putExtra(UsbManager.EXTRA_DEVICE, targetDevice)
                    },
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
                )
                
                Log.d("MainActivity", "   📋 Requesting USB permission via UsbManager...")
                usbManager.requestPermission(targetDevice, permissionIntent)
                Log.d("MainActivity", "   📋 USB permission request sent - dialog should appear now")
                Log.d("MainActivity", "   📋 Note: If permission was already granted, BroadcastReceiver will fire immediately")
                
                // Start a background thread to check permission status after a delay
                // This is a fallback in case the BroadcastReceiver doesn't fire
                Thread {
                    // Wait for user to interact with dialog (if it appears)
                    Thread.sleep(5000) // Wait 5 seconds for user to interact with dialog
                    
                    // Re-check permission status
                    val hasPermission = usbManager.hasPermission(targetDevice)
                    Log.d("MainActivity", "   🔍 Fallback check after 5s: hasPermission=$hasPermission")
                    
                    if (hasPermission) {
                        Log.d("MainActivity", "   ✅ USB permission granted (checked after delay)")
                        // Permission was granted, proceed with initialization
                        runOnUiThread {
                            if (pendingUvcInit != null && pendingUvcResult != null) {
                                val (vId, pId) = pendingUvcInit!!
                                if (vId == vendorId && pId == productId) {
                                    Log.d("MainActivity", "   ✅ Proceeding with UVC initialization after permission grant")
                                    initializeUvcCameraInternal(vendorId, productId, pendingUvcResult)
                                    pendingUvcInit = null
                                    pendingUvcResult = null
                                } else {
                                    Log.w("MainActivity", "   ⚠️ Vendor/Product ID mismatch in fallback check")
                                }
                            } else {
                                Log.w("MainActivity", "   ⚠️ No pending UVC initialization in fallback check")
                            }
                        }
                    } else {
                        Log.d("MainActivity", "   ⚠️ USB permission still not granted after delay")
                        // If permission is still not granted and BroadcastReceiver hasn't fired,
                        // we should error out. But let's wait a bit more for the BroadcastReceiver.
                        // The Dart-side timeout will handle this case.
                    }
                }.start()
                
                // Note: If permission was already granted in a previous session, the dialog won't appear
                // and we need to check again. However, requestPermission should handle this.
                // We'll wait for the BroadcastReceiver to be called.
                return // Will continue in BroadcastReceiver
            } else {
                Log.d("MainActivity", "   ✅ USB permission already granted")
            }

            // Permission already granted, proceed with initialization
            initializeUvcCameraInternal(vendorId, productId, result)
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error initializing UVC camera: ${e.message}", e)
            result.error("INIT_ERROR", "Failed to initialize UVC camera: ${e.message}", null)
        }
    }
    
    /**
     * Internal method to initialize UVC camera (assumes permission is granted)
     */
    private fun initializeUvcCameraInternal(vendorId: Int, productId: Int, result: MethodChannel.Result?) {
        try {
            Log.d("MainActivity", "🎥 Initializing UVC camera (internal): vendor=$vendorId, product=$productId")

            // CRITICAL: Dispose Android camera controller first to avoid surface conflicts
            Log.d("MainActivity", "   🧹 Disposing Android camera controller before UVC initialization...")
            androidCameraController?.dispose()
            androidCameraController = null
            
            // Dispose existing UVC controller
            uvcCameraController?.dispose()
            uvcCameraController = null

            // Longer delay to ensure previous camera resources (especially SurfaceView) are fully released
            // This prevents BLASTBufferQueue conflicts
            Thread.sleep(500)

            val usbManager = getSystemService(Context.USB_SERVICE) as UsbManager
            val devices = usbManager.deviceList

            // Find the USB device
            var targetDevice: UsbDevice? = null
            for (device in devices.values) {
                if (device.vendorId == vendorId && device.productId == productId) {
                    targetDevice = device
                    break
                }
            }

            if (targetDevice == null) {
                result?.error("DEVICE_NOT_FOUND", "UVC camera not found (vendor=$vendorId, product=$productId)", null)
                return
            }

            // Get texture registry
            val registry = textureRegistry ?: run {
                result?.error("TEXTURE_ERROR", "Texture registry not available", null)
                return
            }

            // Create and initialize UVC controller with disconnection callback
            uvcCameraController = UvcCameraController(this, registry) { deviceName ->
                // Callback when USB device is disconnected
                Log.d("MainActivity", "📎 UVC camera disconnected: $deviceName")
                uvcEventSink?.success(mapOf(
                    "event" to "usb_disconnected",
                    "deviceName" to deviceName
                ))
            }
            uvcCameraController?.initialize(targetDevice, result ?: object : MethodChannel.Result {
                override fun success(result: Any?) {}
                override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                    Log.e("MainActivity", "UVC init error: $errorCode - $errorMessage")
                }
                override fun notImplemented() {}
            })
        } catch (e: Exception) {
            Log.e("MainActivity", "❌ Error initializing UVC camera: ${e.message}", e)
            result?.error("INIT_ERROR", "Failed to initialize UVC camera: ${e.message}", null)
        }
    }

    /**
     * Start UVC camera preview
     */
    private fun startUvcPreview(result: MethodChannel.Result) {
        val controller = uvcCameraController
        if (controller == null) {
            result.error("NOT_INITIALIZED", "UVC camera not initialized", null)
            return
        }
        controller.startPreview(result)
    }

    /**
     * Capture photo from UVC camera
     */
    private fun captureUvcPhoto(result: MethodChannel.Result) {
        val controller = uvcCameraController
        if (controller == null) {
            result.error("NOT_INITIALIZED", "UVC camera not initialized", null)
            return
        }
        controller.capturePhoto(result)
    }

    /**
     * Dispose UVC camera
     */
    private fun disposeUvcCamera(result: MethodChannel.Result) {
        uvcCameraController?.dispose()
        uvcCameraController = null
        result.success(mapOf("success" to true))
    }
    
    override fun onDestroy() {
        super.onDestroy()
        // Unregister USB permission receiver
        try {
            unregisterReceiver(usbPermissionReceiver)
        } catch (e: Exception) {
            // Receiver may not be registered
        }
        // Dispose camera controllers
        androidCameraController?.dispose()
        androidCameraController = null
        uvcCameraController?.dispose()
        uvcCameraController = null
    }
}