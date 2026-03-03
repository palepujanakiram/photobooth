package com.example.photobooth

import android.util.Log
import android.view.Surface
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformViewFactory
import io.flutter.view.TextureRegistry

class MainActivity : FlutterActivity() {

    fun getAndroidCameraController(): AndroidCameraController? = androidCameraController
    private val channel = "com.example.photobooth/camera_device_helper"
    private val cameraControlChannel = "com.photobooth/camera_device"
    private lateinit var cameraDeviceHelper: CameraDeviceHelper
    private var androidCameraController: AndroidCameraController? = null
    private var flutterEngineInstance: FlutterEngine? = null
    private var textureRegistry: TextureRegistry? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngineInstance = flutterEngine

        // Get TextureRegistry - try multiple approaches
        obtainTextureRegistry(flutterEngine)

        if (textureRegistry == null) {
            logTextureRegistryWarning()
        }

        cameraDeviceHelper = CameraDeviceHelper(this)
        cameraDeviceHelper.logDeviceCapabilities()

        setupCameraDiscoveryChannel(flutterEngine)
        setupCameraControlChannel(flutterEngine)
        registerCameraPreviewSurfaceView(flutterEngine)
    }

    private fun registerCameraPreviewSurfaceView(flutterEngine: FlutterEngine) {
        val viewTypeId = "com.example.photobooth/camera_preview_surface"
        val factory: PlatformViewFactory = CameraPreviewSurfaceViewFactory { surface: Surface ->
            getAndroidCameraController()?.onSurfaceReady(surface)
        }
        try {
            // Use public API first (Flutter embedding v2)
            val controller = flutterEngine.platformViewsController
            val registry = controller.registry
            registry.registerViewFactory(viewTypeId, factory)
            Log.d("MainActivity", "✅ Registered camera preview SurfaceView platform view (public API)")
        } catch (e: Exception) {
            Log.w("MainActivity", "Public API failed, trying reflection: ${e.message}")
            try {
                val getController = flutterEngine.javaClass.getMethod("getPlatformViewsController")
                val platformViewsController = getController.invoke(flutterEngine)
                val getRegistry = platformViewsController?.javaClass?.getMethod("getRegistry")
                val registry = getRegistry?.invoke(platformViewsController)
                val registerFactory = registry?.javaClass?.getMethod(
                    "registerViewFactory",
                    String::class.java,
                    PlatformViewFactory::class.java,
                )
                registerFactory?.invoke(registry, viewTypeId, factory)
                Log.d("MainActivity", "✅ Registered camera preview SurfaceView (reflection)")
            } catch (e2: Exception) {
                Log.e("MainActivity", "Failed to register camera preview SurfaceView: ${e2.message}", e2)
            }
        }
    }

    private fun obtainTextureRegistry(flutterEngine: FlutterEngine) {
        // Approach 1: Try via platformViewsController (recommended way)
        tryGetTextureRegistryViaPlatformViews(flutterEngine)

        // Approach 2: Try via getRenderer() -> access textureRegistry field in renderer
        if (textureRegistry == null) {
            tryGetTextureRegistryViaRenderer(flutterEngine)
        }
    }

    private fun tryGetTextureRegistryViaPlatformViews(flutterEngine: FlutterEngine) {
        try {
            val platformViewsControllerMethod = flutterEngine.javaClass.getMethod("getPlatformViewsController")
            val platformViewsController = platformViewsControllerMethod.invoke(flutterEngine)
            if (platformViewsController != null) {
                tryGetTextureRegistryFromController(platformViewsController)
            }
        } catch (e: Exception) {
            Log.d("MainActivity", "platformViewsController approach failed: ${e.message}")
        }
    }

    private fun tryGetTextureRegistryFromController(platformViewsController: Any) {
        try {
            val textureRegistryMethod = platformViewsController.javaClass.getMethod("getTextureRegistry")
            @Suppress("UNCHECKED_CAST")
            textureRegistry = textureRegistryMethod.invoke(platformViewsController) as? TextureRegistry
            if (textureRegistry != null) {
                Log.d(
                    "MainActivity",
                    "✅ Successfully obtained TextureRegistry via platformViewsController.getTextureRegistry()"
                )
                return
            }
        } catch (e: Exception) {
            Log.d("MainActivity", "platformViewsController.getTextureRegistry() failed: ${e.message}")
        }

        // Try as a field
        tryGetTextureRegistryFieldFromController(platformViewsController)
    }

    private fun tryGetTextureRegistryFieldFromController(platformViewsController: Any) {
        try {
            val field = platformViewsController.javaClass.getDeclaredField("textureRegistry")
            field.isAccessible = true
            @Suppress("UNCHECKED_CAST")
            textureRegistry = field.get(platformViewsController) as? TextureRegistry
            if (textureRegistry != null) {
                Log.d(
                    "MainActivity",
                    "✅ Successfully obtained TextureRegistry via platformViewsController.textureRegistry field"
                )
            }
        } catch (e: Exception) {
            Log.d("MainActivity", "platformViewsController.textureRegistry field failed: ${e.message}")
        }
    }

    private fun tryGetTextureRegistryViaRenderer(flutterEngine: FlutterEngine) {
        try {
            val rendererMethod = flutterEngine.javaClass.getMethod("getRenderer")
            val renderer = rendererMethod.invoke(flutterEngine)
            if (renderer != null) {
                tryGetTextureRegistryFromRendererFields(renderer)
            }
        } catch (e: Exception) {
            Log.d("MainActivity", "getRenderer() approach failed: ${e.message}")
        }
    }

    private fun tryGetTextureRegistryFromRendererFields(renderer: Any) {
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

    private fun logTextureRegistryWarning() {
        Log.w("MainActivity", "⚠️ Could not obtain TextureRegistry - external cameras may not work")
        Log.w("MainActivity", "   This means native camera controller cannot be used")
        Log.w("MainActivity", "   External cameras will fall back to standard CameraController (may not work)")
    }

    private fun setupCameraDiscoveryChannel(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel).setMethodCallHandler { call, result ->
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

                "resolveUsbToCamera2Id" -> {
                    val args = call.arguments as? Map<*, *>
                    val vendorId = (args?.get("vendorId") as? Number)?.toInt()
                    val productId = (args?.get("productId") as? Number)?.toInt()
                    if (vendorId == null || productId == null) {
                        result.success(null)
                    } else {
                        cameraDeviceHelper.resolveUsbToCamera2Id(vendorId, productId, result)
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }

    private fun setupCameraControlChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            cameraControlChannel
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "initializeCamera" -> handleInitializeCamera(call, result)
                "startPreview" -> startPreview(result)
                "takePicture" -> takePicture(result)
                "disposeCamera" -> disposeCamera(result)
                else -> result.notImplemented()
            }
        }
    }

    private fun handleInitializeCamera(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val deviceId = args?.get("deviceId") as? String
        if (deviceId == null) {
            result.error("INVALID_ARGS", "deviceId is required", null)
            return
        }
        val useSurfaceView = (args?.get("useSurfaceView") as? Boolean) == true
        val rotation = (args?.get("rotation") as? Number)?.toInt() ?: 90
        if (useSurfaceView) {
            initializeCameraWithSurfaceView(deviceId, rotation, result)
        } else {
            initializeCamera(deviceId, result)
        }
    }

    private fun initializeCameraWithSurfaceView(deviceId: String, rotation: Int, result: MethodChannel.Result) {
        try {
            val existing = androidCameraController
            if (existing != null && existing.isPreparedForSurfaceView() && existing.getCurrentCameraId() == deviceId) {
                result.success(mapOf("success" to true, "useSurfaceView" to true, "localizedName" to "Camera"))
                return
            }
            androidCameraController?.dispose()
            androidCameraController = AndroidCameraController(this, null)
            androidCameraController?.prepareForSurfaceView(deviceId, rotation, result)
        } catch (e: Exception) {
            result.error("INIT_ERROR", "Failed to prepare camera for SurfaceView: ${e.message}", null)
        }
    }

    private fun initializeCamera(deviceId: String, result: MethodChannel.Result) {
        try {
            androidCameraController?.dispose()
            val registry = getTextureRegistryForCamera(result) ?: return
            androidCameraController = AndroidCameraController(this, registry)
            androidCameraController?.initialize(deviceId, result)
        } catch (e: Exception) {
            result.error("INIT_ERROR", "Failed to initialize camera: ${e.message}", null)
        }
    }

    private fun getTextureRegistryForCamera(result: MethodChannel.Result): TextureRegistry? {
        val registry = textureRegistry ?: tryGetTextureRegistryViaReflection()

        if (registry == null) {
            result.error(
                "INIT_ERROR",
                "Texture registry not available. Please ensure Flutter engine is properly initialized.",
                null
            )
        }

        return registry
    }

    private fun tryGetTextureRegistryViaReflection(): TextureRegistry? {
        val engine = flutterEngineInstance ?: flutterEngine ?: return null

        // Method 1: Try to get it via getRenderer() -> getTextureRegistry()
        tryGetTextureRegistryViaRendererMethod(engine)?.let { return it }

        // Method 2: Try direct field access with different possible field names
        return tryGetTextureRegistryViaFieldAccess(engine)
    }

    private fun tryGetTextureRegistryViaRendererMethod(engine: FlutterEngine): TextureRegistry? {
        try {
            val rendererMethod = engine.javaClass.getMethod("getRenderer")
            val renderer = rendererMethod.invoke(engine) ?: return null

            val textureRegistryMethod = renderer.javaClass.getMethod("getTextureRegistry")
            @Suppress("UNCHECKED_CAST")
            val reg = textureRegistryMethod.invoke(renderer) as? TextureRegistry
            if (reg != null) {
                Log.d(
                    "MainActivity",
                    "✅ Successfully accessed textureRegistry via getRenderer().getTextureRegistry()"
                )
                return reg
            }
        } catch (e: Exception) {
            Log.d("MainActivity", "Method 1 (getRenderer) failed: ${e.message}")
        }
        return null
    }

    private fun tryGetTextureRegistryViaFieldAccess(engine: FlutterEngine): TextureRegistry? {
        val fieldNames = listOf("textureRegistry", "mTextureRegistry", "_textureRegistry")
        for (fieldName in fieldNames) {
            try {
                val field = engine.javaClass.getDeclaredField(fieldName)
                field.isAccessible = true
                @Suppress("UNCHECKED_CAST")
                val reg = field.get(engine) as? TextureRegistry
                if (reg != null) {
                    Log.d("MainActivity", "✅ Successfully accessed textureRegistry via field: $fieldName")
                    return reg
                }
            } catch (e: Exception) {
                Log.d("MainActivity", "Field $fieldName not found: ${e.message}")
            }
        }
        return null
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
