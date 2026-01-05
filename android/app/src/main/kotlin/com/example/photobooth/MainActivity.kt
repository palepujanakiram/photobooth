package com.example.photobooth

import android.os.Bundle
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.photobooth/camera_device_helper"
    private val CAMERA_CONTROL_CHANNEL = "com.photobooth/camera_device"
    private lateinit var cameraDeviceHelper: CameraDeviceHelper
    private var androidCameraController: AndroidCameraController? = null
    private var flutterEngineInstance: FlutterEngine? = null
    private var textureRegistry: TextureRegistry? = null

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
    
    override fun onDestroy() {
        super.onDestroy()
        // Dispose camera controller
        androidCameraController?.dispose()
        androidCameraController = null
    }
}