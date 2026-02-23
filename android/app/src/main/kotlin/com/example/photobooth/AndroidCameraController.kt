package com.example.photobooth

import android.app.ActivityManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.SurfaceTexture
import android.hardware.camera2.CameraCaptureSession
import android.hardware.camera2.CameraDevice
import android.hardware.camera2.CameraManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraAccessException
import android.hardware.camera2.CaptureRequest
import android.hardware.camera2.CaptureFailure
import android.hardware.camera2.TotalCaptureResult
import android.hardware.camera2.params.StreamConfigurationMap
import android.media.Image
import android.media.ImageReader
import android.os.Handler
import android.os.HandlerThread
import android.util.Log
import android.util.Size
import android.view.Surface
import android.app.Activity
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import com.bugsnag.android.Bugsnag
import java.io.File
import java.io.FileOutputStream
import java.lang.reflect.Method

/**
 * Native Android camera controller using Camera2 API
 * Similar to iOS CustomCameraController, provides direct camera control
 * for external cameras that Flutter's camera package can't access
 */
class AndroidCameraController(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
) {
    // TextureRegistry is provided via constructor
    companion object {
        private const val TAG = "AndroidCameraController"
        private const val MAX_PREVIEW_WIDTH = 1920
        private const val MAX_PREVIEW_HEIGHT = 1080
        // Cap still-capture resolution to avoid OOM on low-RAM devices (e.g. Android TV 2GB with 4K webcam)
        private const val MAX_CAPTURE_WIDTH = 1920
        private const val MAX_CAPTURE_HEIGHT = 1080
        // On low-memory devices use smaller capture to reduce ImageReader + save buffer pressure
        private const val LOW_MEMORY_CAPTURE_WIDTH = 1280
        private const val LOW_MEMORY_CAPTURE_HEIGHT = 720
        private const val LOW_MEMORY_CLASS_MB = 128 // Use smaller capture on devices with ≤128MB heap (e.g. many 2GB RAM / Android TV)
        private const val SAVE_CHUNK_SIZE = 64 * 1024 // 64KB - avoid allocating full image in memory
        // App standard capture format (same for all cameras): JPEG, max 1920px, 85% quality.
        // Normalization at capture so saved file is identical regardless of 4K vs webcam.
        private const val MAX_SAVED_DIMENSION = 1920
        private const val SAVED_JPEG_QUALITY = 85
    }

    private var cameraManager: CameraManager? = null
    private var cameraDevice: CameraDevice? = null
    private var captureSession: CameraCaptureSession? = null
    private var imageReader: ImageReader? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var previewSurface: Surface? = null // Store preview surface to reuse
    private var backgroundThread: HandlerThread? = null
    private var backgroundHandler: Handler? = null
    private var currentCameraId: String? = null
    private var textureId: Long = -1
    private var pendingPhotoResult: MethodChannel.Result? = null
    private var captureTimeoutHandler: android.os.Handler? = null
    private var captureTimeoutRunnable: Runnable? = null
    private var isDisposing: Boolean = false

    private val cameraStateCallback =
        object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            handleCameraOpened(camera)
        }

        override fun onDisconnected(camera: CameraDevice) {
            handleCameraDisconnected(camera)
        }

        override fun onError(camera: CameraDevice, error: Int) {
            handleCameraError(error)
        }
    }

    private fun handleCameraOpened(camera: CameraDevice) {
        Log.d(TAG, "✅ Camera opened: ${camera.id}")
        Bugsnag.leaveBreadcrumb("Camera opened successfully: ${camera.id}")
        Log.d(TAG, "   Expected camera ID: $currentCameraId")
        if (camera.id != currentCameraId) {
            Log.e(TAG, "❌ ERROR: Opened camera ID (${camera.id}) does not match requested ID ($currentCameraId)!")
            Bugsnag.leaveBreadcrumb("Camera ID mismatch: expected $currentCameraId, got ${camera.id}")
        } else {
            Log.d(TAG, "✅ Camera ID matches requested ID")
        }
        cameraDevice = camera
        createCaptureSession()
    }

    private fun handleCameraDisconnected(camera: CameraDevice) {
        Log.d(TAG, "⚠️ Camera disconnected: ${camera.id}")
        Bugsnag.leaveBreadcrumb("Camera disconnected: ${camera.id}")
        closeCamera()
    }

    private fun handleCameraError(error: Int) {
        Log.e(TAG, "❌ Camera error: $error")
        val errorMsg = getCameraErrorMessage(error)
        Bugsnag.leaveBreadcrumb("Camera error: $errorMsg (code: $error)")
        pendingPhotoResult?.error("CAMERA_ERROR", errorMsg, null)
        pendingPhotoResult = null
        closeCamera()
    }

    private fun getCameraErrorMessage(error: Int): String = when (error) {
        CameraDevice.StateCallback.ERROR_CAMERA_DEVICE -> "Camera device error"
        CameraDevice.StateCallback.ERROR_CAMERA_DISABLED -> "Camera disabled"
        CameraDevice.StateCallback.ERROR_CAMERA_IN_USE -> "Camera in use"
        CameraDevice.StateCallback.ERROR_MAX_CAMERAS_IN_USE -> "Max cameras in use"
        else -> "Unknown camera error"
    }

    private var pendingPreviewResult: MethodChannel.Result? = null

    private val captureStateCallback =
        object : CameraCaptureSession.StateCallback() {
        override fun onConfigured(session: CameraCaptureSession) {
            Log.d(TAG, "✅ Capture session configured")
            Bugsnag.leaveBreadcrumb("Capture session configured successfully")
            captureSession = session

            // If there's a pending preview request, start it now
            pendingPreviewResult?.let { result ->
                Log.d(TAG, "🎬 Starting preview (pending request from before session was ready)")
                Bugsnag.leaveBreadcrumb("Starting preview from pending request")
                startPreviewInternal(result)
                pendingPreviewResult = null
            }
        }

        override fun onConfigureFailed(session: CameraCaptureSession) {
            Log.e(TAG, "❌ Capture session configuration failed")
            Bugsnag.leaveBreadcrumb("Capture session configuration failed")
            pendingPhotoResult?.error("SESSION_ERROR", "Failed to configure capture session", null)
            pendingPhotoResult = null
            pendingPreviewResult?.error("SESSION_ERROR", "Failed to configure capture session", null)
            pendingPreviewResult = null
        }
    }

    private val captureCallback =
        object : CameraCaptureSession.CaptureCallback() {
            override fun onCaptureCompleted(
                session: CameraCaptureSession,
                request: CaptureRequest,
                result: TotalCaptureResult,
            ) {
            // This is called for both preview frames and photo captures
            // Only log occasionally to avoid spam
            if (System.currentTimeMillis() % 1000 < 100) {
                Log.d(TAG, "✅ Frame captured (preview or photo)")
            }
        }

            override fun onCaptureFailed(
                session: CameraCaptureSession,
                request: CaptureRequest,
                failure: CaptureFailure,
            ) {
                Log.e(TAG, "❌ Photo capture failed: ${failure.reason}")
                Bugsnag.leaveBreadcrumb("Photo capture failed: ${failure.reason}")
                pendingPhotoResult?.error("CAPTURE_ERROR", "Photo capture failed: ${failure.reason}", null)
                pendingPhotoResult = null
            }
        }

    private val imageAvailableListener =
        ImageReader.OnImageAvailableListener { reader ->
        Log.d(TAG, "📸 imageAvailableListener triggered")
        Bugsnag.leaveBreadcrumb("Image data received from camera")
        
        // CRITICAL: Check if camera is still active/initialized
        // Prevents "FlutterJNI not attached" errors when callback fires after disposal
        if (cameraDevice == null || textureEntry == null) {
            Log.w(TAG, "⚠️ imageAvailableListener called but camera already disposed. Ignoring.")
            Bugsnag.leaveBreadcrumb("Image received but camera already disposed")
            // Acquire/close any pending image to clear the queue
            try {
                reader.acquireLatestImage()?.close()
            } catch (e: Exception) {
                Log.e(TAG, "Error closing orphaned image: ${e.message}")
            }
            return@OnImageAvailableListener
        }
        
        // Cancel timeout since we received the image
        cancelCaptureTimeout()
        Log.d(TAG, "   ✅ Cancelled capture timeout")
        
        val image = reader.acquireLatestImage()
        if (image == null) {
            Log.e(TAG, "❌ acquireLatestImage returned null")
            Bugsnag.leaveBreadcrumb("Failed to acquire image from ImageReader")
            pendingPhotoResult?.error("CAPTURE_ERROR", "Failed to acquire image from reader", null)
            pendingPhotoResult = null
            return@OnImageAvailableListener
        }
        
        try {
            Log.d(TAG, "   Processing captured image...")
            saveImageToFile(image)
            Bugsnag.leaveBreadcrumb("Photo captured and saved successfully")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving image: ${e.message}", e)
            Bugsnag.leaveBreadcrumb("Failed to save image: ${e.message}")
            pendingPhotoResult?.error("SAVE_ERROR", "Failed to save image: ${e.message}", null)
            pendingPhotoResult = null
        } finally {
            image.close()
            Log.d(TAG, "   Image closed")
        }
    }

    /**
     * Initializes the camera with a specific camera ID
     */
    fun initialize(cameraId: String, result: MethodChannel.Result) {
        try {
            logInitializationStart(cameraId)
            cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

            val characteristics = getCameraCharacteristics(cameraId, result) ?: return
            val cameraName = getCameraName(characteristics, cameraId)
            logCameraDetails(characteristics, cameraName)

            currentCameraId = cameraId
            startBackgroundThread()

            if (!setupTextureEntry(result)) return
            if (!setupPreviewSurface(characteristics, result)) return
            if (!setupImageReader(characteristics, result)) return

            cameraManager?.openCamera(cameraId, cameraStateCallback, backgroundHandler)
            returnInitializationSuccess(cameraName, result)
        } catch (e: SecurityException) {
            handleInitializationError(e, "PERMISSION_ERROR", "Camera permission not granted", result)
        } catch (e: Exception) {
            handleInitializationError(e, "INIT_ERROR", e.message, result)
        }
    }

    private fun logInitializationStart(cameraId: String) {
        Log.d(TAG, "🎥 Initializing camera: $cameraId")
        Bugsnag.leaveBreadcrumb("Camera initialization started: $cameraId")
        Log.d(TAG, "   Camera ID type: ${cameraId::class.java.simpleName}")
        Log.d(TAG, "   Camera ID value: \"$cameraId\"")
    }

    private fun getCameraCharacteristics(cameraId: String, result: MethodChannel.Result): CameraCharacteristics? {
        val cameraIds = cameraManager?.cameraIdList
        Log.d(TAG, "   Available camera IDs in initial list: ${cameraIds?.joinToString(", ") ?: "null"}")

        val characteristics = try {
            cameraManager?.getCameraCharacteristics(cameraId)
        } catch (e: IllegalArgumentException) {
            Log.e(TAG, "❌ Camera $cameraId does not exist or cannot be accessed")
            Bugsnag.leaveBreadcrumb("Camera not found: $cameraId")
            result.error(
                "CAMERA_NOT_FOUND",
                "Camera $cameraId not found or cannot be accessed. Available cameras: ${cameraIds?.joinToString(", ") ?: "none"}",
                null,
            )
            return null
        } catch (e: CameraAccessException) {
            Log.e(TAG, "❌ Camera access exception for camera $cameraId: ${e.message}")
            result.error("CAMERA_ACCESS_ERROR", "Cannot access camera $cameraId: ${e.message}", null)
            return null
        }

        if (characteristics == null) {
            Log.e(TAG, "❌ Camera $cameraId characteristics are null")
            result.error("CAMERA_NOT_FOUND", "Camera $cameraId characteristics are null", null)
            return null
        }

        logCameraFoundStatus(cameraId, cameraIds)
        return characteristics
    }

    private fun logCameraFoundStatus(cameraId: String, cameraIds: Array<String>?) {
        if (cameraIds?.contains(cameraId) == true) {
            Log.d(TAG, "✅ Camera $cameraId found in cameraIdList")
        } else {
            Log.d(TAG, "✅ Camera $cameraId found (not in initial cameraIdList - likely external USB camera)")
        }
    }

    private fun getCameraName(characteristics: CameraCharacteristics, cameraId: String): String {
        val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
        return when (facing) {
            CameraCharacteristics.LENS_FACING_BACK -> "Back Camera"
            CameraCharacteristics.LENS_FACING_FRONT -> "Front Camera"
            CameraCharacteristics.LENS_FACING_EXTERNAL -> "External Camera"
            else -> "Camera $cameraId"
        }
    }

    private fun logCameraDetails(characteristics: CameraCharacteristics, cameraName: String) {
        val facing = characteristics.get(CameraCharacteristics.LENS_FACING)
        Log.d(TAG, "   Camera characteristics:")
        Log.d(TAG, "     LENS_FACING: $facing")
        Log.d(TAG, "     Camera name: $cameraName")
        Log.d(TAG, "   Stored currentCameraId: $currentCameraId")
    }

    private fun setupTextureEntry(result: MethodChannel.Result): Boolean {
        return try {
            textureEntry = textureRegistry.createSurfaceTexture()
            textureId = textureEntry!!.id()
            Log.d(TAG, "   ✅ Texture created with ID: $textureId")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to create texture: ${e.message}")
            result.error("INIT_ERROR", "Texture registry not available. Please ensure Flutter engine is properly initialized.", null)
            false
        }
    }

    private fun setupPreviewSurface(characteristics: CameraCharacteristics, result: MethodChannel.Result): Boolean {
        val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val availablePreviewSizes = map?.getOutputSizes(SurfaceTexture::class.java)?.toList() ?: emptyList()
        logAvailableSizes("preview", availablePreviewSizes)

        val previewSize = chooseOptimalSize(availablePreviewSizes)
        Log.d(TAG, "   🎯 Selected preview size: ${previewSize.width}×${previewSize.height}")

        return try {
            val surfaceTexture = textureEntry!!.surfaceTexture()
            surfaceTexture.setDefaultBufferSize(previewSize.width, previewSize.height)
            Log.d(TAG, "   ✅ Preview buffer size set successfully")
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to set preview buffer size: ${e.message}")
            result.error("INIT_ERROR", "Failed to set preview buffer size: ${e.message}", null)
            false
        }
    }

    private fun setupImageReader(characteristics: CameraCharacteristics, result: MethodChannel.Result): Boolean {
        val map = characteristics.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
        val availableCaptureSizes = map?.getOutputSizes(ImageFormat.JPEG)?.toList() ?: emptyList()
        logAvailableSizes("JPEG capture", availableCaptureSizes)

        val imageReaderSize = chooseOptimalCaptureSize(availableCaptureSizes)
        Log.d(TAG, "   🎯 Selected capture size: ${imageReaderSize.width}×${imageReaderSize.height}")

        return try {
            imageReader = ImageReader.newInstance(imageReaderSize.width, imageReaderSize.height, ImageFormat.JPEG, 1)
            Log.d(TAG, "   ✅ ImageReader created successfully")
            imageReader?.setOnImageAvailableListener(imageAvailableListener, backgroundHandler)
            true
        } catch (e: Exception) {
            Log.e(TAG, "❌ Failed to create ImageReader: ${e.message}")
            result.error("INIT_ERROR", "Failed to create ImageReader for photo capture: ${e.message}", null)
            false
        }
    }

    private fun logAvailableSizes(type: String, sizes: List<Size>) {
        Log.d(TAG, "   📐 Available $type sizes (${sizes.size}):")
        sizes.take(5).forEach { size -> Log.d(TAG, "      - ${size.width}×${size.height}") }
        if (sizes.size > 5) {
            Log.d(TAG, "      ... and ${sizes.size - 5} more")
        }
    }

    private fun returnInitializationSuccess(cameraName: String, result: MethodChannel.Result) {
        Bugsnag.leaveBreadcrumb("Camera initialization completed: $cameraName (ID: $currentCameraId)")
        result.success(mapOf("success" to true, "textureId" to textureId, "localizedName" to cameraName))
    }

    private fun handleInitializationError(e: Exception, code: String, message: String?, result: MethodChannel.Result) {
        Log.e(TAG, "Error initializing camera: ${e.message}", e)
        Bugsnag.leaveBreadcrumb("Camera initialization failed: ${e.javaClass.simpleName}")
        result.error(code, message, null)
    }

    /**
     * Creates the capture session with preview and photo outputs
     */
    private fun createCaptureSession() {
        val device = cameraDevice ?: return
        val textureEntry = textureEntry ?: return
        val imageReader = imageReader ?: return

        try {
            val surfaceTexture = textureEntry.surfaceTexture()
            // Buffer size was already set during initialization, but ensure it's set correctly
            // Use optimal preview size instead of hardcoded 1920x1080
            val map =
                cameraManager
                    ?.getCameraCharacteristics(currentCameraId ?: "")
                    ?.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val previewSizes = map?.getOutputSizes(SurfaceTexture::class.java)?.toList() ?: emptyList()
            val optimalSize = chooseOptimalSize(previewSizes)
            surfaceTexture.setDefaultBufferSize(optimalSize.width, optimalSize.height)
            Log.d(TAG, "   Preview buffer size set to: ${optimalSize.width}x${optimalSize.height}")

            // Apply preview orientation so the feed matches display (e.g. landscape TV)
            applyPreviewOrientation(surfaceTexture as android.graphics.SurfaceTexture)

            // Create Surface from the SurfaceTexture - this is the preview surface
            // Store it so we can reuse the same instance in startPreviewInternal
            previewSurface = Surface(surfaceTexture)
            val imageSurface = imageReader.surface

            val surfaces = listOf(previewSurface!!, imageSurface)
            Log.d(TAG, "   Creating capture session with ${surfaces.size} surfaces (preview + image)")

            device.createCaptureSession(
                surfaces,
                captureStateCallback,
                backgroundHandler,
            )
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Error creating capture session: ${e.message}", e)
            pendingPhotoResult?.error("SESSION_ERROR", "Failed to create capture session: ${e.message}", null)
            pendingPhotoResult = null
        }
    }

    /**
     * Starts the camera preview
     * Handles race condition where preview might be requested before capture session is ready
     */
    fun startPreview(result: MethodChannel.Result) {
        if (captureSession != null) {
            // Session is ready, start preview immediately
            startPreviewInternal(result)
        } else {
            // Session not ready yet, store the result and start when session is configured
            Log.d(TAG, "⏳ Capture session not ready yet, storing preview request")
            if (pendingPreviewResult != null) {
                // Already have a pending request, cancel it
                pendingPreviewResult?.error("CANCELLED", "New preview request received", null)
            }
            pendingPreviewResult = result
        }
    }

    /**
     * Internal method to actually start the preview
     * Called either immediately if session is ready, or from onConfigured callback
     */
    private fun startPreviewInternal(result: MethodChannel.Result) {
        if (captureSession == null) {
            result.error("NOT_INITIALIZED", "Camera not initialized", null)
            return
        }

        try {
            val device = cameraDevice ?: run {
                result.error("NOT_INITIALIZED", "Camera device not available", null)
                return
            }

            Log.d(TAG, "🎬 Starting preview")
            Bugsnag.leaveBreadcrumb("Preview start requested for camera ${device.id}")
            Log.d(TAG, "   Active camera device ID: ${device.id}")
            Log.d(TAG, "   Expected camera ID: $currentCameraId")
            if (device.id != currentCameraId) {
                Log.e(TAG, "❌ ERROR: Preview is using wrong camera! Expected $currentCameraId, got ${device.id}")
                Bugsnag.leaveBreadcrumb("Preview camera ID mismatch: expected $currentCameraId, got ${device.id}")
            }

            val characteristics = cameraManager?.getCameraCharacteristics(device.id)
            val facing = characteristics?.get(CameraCharacteristics.LENS_FACING)
            Log.d(TAG, "   Camera LENS_FACING: $facing")

            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_PREVIEW)

            // Add preview surface - MUST use the same Surface instance that was added to capture session
            previewSurface?.let { surface ->
                builder.addTarget(surface)
                Log.d(TAG, "   ✅ Preview surface added to capture request")
                Log.d(TAG, "   Using stored preview surface: $surface")
            } ?: run {
                Log.e(TAG, "❌ ERROR: Preview surface is null, cannot add to capture request")
                result.error("PREVIEW_ERROR", "Preview surface is null", null)
                return
            }

            // Set auto-focus and auto-exposure
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)

            // Set repeating request for preview
            captureSession?.setRepeatingRequest(builder.build(), captureCallback, backgroundHandler)

            result.success(mapOf("success" to true))
            Bugsnag.leaveBreadcrumb("Preview started successfully")
            Log.d(TAG, "✅ Preview started successfully")
        } catch (e: CameraAccessException) {
            Log.e(TAG, "Error starting preview: ${e.message}", e)
            result.error("PREVIEW_ERROR", "Failed to start preview: ${e.message}", null)
        } catch (e: Exception) {
            Log.e(TAG, "Unexpected error starting preview: ${e.message}", e)
            result.error("PREVIEW_ERROR", "Unexpected error: ${e.message}", null)
        }
    }

    /**
     * Takes a picture
     */
    fun takePicture(result: MethodChannel.Result) {
        logTakePictureState()
        
        if (!validateCaptureState(result)) return

        pendingPhotoResult = result
        Bugsnag.leaveBreadcrumb("Photo capture started")

        try {
            val device = cameraDevice ?: run {
                result.error("NOT_INITIALIZED", "Camera device not available", null)
                return
            }

            logCaptureDeviceInfo(device)
            val characteristics = cameraManager?.getCameraCharacteristics(device.id)
            val builder = createCaptureRequest(device, characteristics)
            
            setupCaptureTimeout()
            captureSession?.capture(builder.build(), captureCallback, backgroundHandler)
            
            Log.d(TAG, "📸 Capture request sent to camera")
            Log.d(TAG, "   Waiting for ImageReader callback (timeout: 8s)...")
        } catch (e: CameraAccessException) {
            handleCaptureError(e, "CameraAccessException", result)
        } catch (e: Exception) {
            handleCaptureError(e, e.javaClass.simpleName, result)
        }
    }

    private fun logTakePictureState() {
        Log.d(TAG, "📸 takePicture() called")
        Bugsnag.leaveBreadcrumb("Photo capture requested")
        Log.d(TAG, "   captureSession: ${captureSession != null}")
        Log.d(TAG, "   imageReader: ${imageReader != null}")
        Log.d(TAG, "   cameraDevice: ${cameraDevice != null}")
        Log.d(TAG, "   pendingPhotoResult: ${pendingPhotoResult != null}")
        Log.d(TAG, "   isDisposing: $isDisposing")
    }

    private fun validateCaptureState(result: MethodChannel.Result): Boolean {
        if (isDisposing) {
            logAndReportError("CAMERA_CLOSING", "Camera is being disposed, cannot capture photo", "camera disposing", result)
            return false
        }
        
        if (pendingPhotoResult != null) {
            logAndReportError("CAPTURE_IN_PROGRESS", "Another photo capture is already in progress", "capture already in progress", result)
            return false
        }
        
        if (captureSession == null || imageReader == null) {
            logAndReportError("NOT_INITIALIZED", "Camera not initialized - captureSession or imageReader is null", "camera not initialized", result)
            return false
        }
        
        return true
    }

    private fun logAndReportError(code: String, message: String, breadcrumbSuffix: String, result: MethodChannel.Result) {
        Log.e(TAG, "❌ $message")
        Bugsnag.leaveBreadcrumb("Capture blocked: $breadcrumbSuffix")
        result.error(code, message, null)
    }

    private fun logCaptureDeviceInfo(device: CameraDevice) {
        Log.d(TAG, "📸 Taking picture")
        Log.d(TAG, "   Active camera device ID: ${device.id}")
        Log.d(TAG, "   Expected camera ID: $currentCameraId")
        if (device.id != currentCameraId) {
            Log.e(TAG, "❌ ERROR: Capture is using wrong camera! Expected $currentCameraId, got ${device.id}")
        }
        val characteristics = cameraManager?.getCameraCharacteristics(device.id)
        val facing = characteristics?.get(CameraCharacteristics.LENS_FACING)
        Log.d(TAG, "   Camera LENS_FACING: $facing")
    }

    private fun createCaptureRequest(device: CameraDevice, characteristics: CameraCharacteristics?): CaptureRequest.Builder {
        val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
        builder.addTarget(imageReader!!.surface)
        builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
        builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)
        
        // JPEG_ORIENTATION = rotation (0/90/180/270) so the image appears upright on the current display.
        // - sensorOrientation: fixed angle the sensor is mounted (e.g. 90 for typical back camera).
        // - displayRotationDegrees: current device rotation (0/90/180/270 from getDisplayRotationDegrees()).
        // Back/external: jpeg = (sensor - display + 360) % 360  (compensate so top-of-image = top-of-screen).
        // Front:         jpeg = (sensor + display) % 360       (mirror-consistent).
        val sensorOrientation = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
        val displayRotationDegrees = getDisplayRotationDegrees()
        val facing = characteristics?.get(CameraCharacteristics.LENS_FACING)
        val jpegOrientation = when (facing) {
            CameraCharacteristics.LENS_FACING_FRONT -> (sensorOrientation + displayRotationDegrees) % 360
            else -> (sensorOrientation - displayRotationDegrees + 360) % 360 // back or external
        }
        builder.set(CaptureRequest.JPEG_ORIENTATION, jpegOrientation)
        Log.d(TAG, "   JPEG_ORIENTATION: $jpegOrientation (sensor=$sensorOrientation, display=$displayRotationDegrees°)")
        return builder
    }

    /**
     * How much the device/screen is rotated (from Android TV Settings / system).
     * 0=portrait, 90/270=landscape, 180=upside-down.
     */
    private fun getDisplayRotationDegrees(): Int {
        val activity = context as? Activity ?: return 0
        return when (activity.windowManager.defaultDisplay.rotation) {
            Surface.ROTATION_0 -> 0
            Surface.ROTATION_90 -> 90
            Surface.ROTATION_180 -> 180
            Surface.ROTATION_270 -> 270
            else -> 0
        }
    }

    /**
     * Preview rotation matrices for SurfaceTexture (4x4, column-major, 16 floats).
     * Used so the camera image appears upright on screen (e.g. landscape TV).
     */
    private fun getPreviewRotationMatrix(degrees: Int): FloatArray {
        return when (degrees) {
            90 -> floatArrayOf(0f, 1f, 0f, 0f, -1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 1f, 0f, 0f, 1f)
            180 -> floatArrayOf(-1f, 0f, 0f, 0f, 0f, -1f, 0f, 0f, 0f, 0f, 1f, 0f, 1f, 1f, 0f, 1f)
            270 -> floatArrayOf(0f, -1f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 1f, 0f, 1f)
            else -> floatArrayOf(1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 0f, 1f) // 0° = no rotation
        }
    }

    /**
     * Rotates the preview so it matches the device orientation (respects Android TV Settings).
     * Without this, external USB cameras often show the feed rotated 90° on landscape TVs.
     */
    private fun applyPreviewOrientation(surfaceTexture: android.graphics.SurfaceTexture) {
        try {
            val characteristics = cameraManager?.getCameraCharacteristics(currentCameraId ?: "") ?: return
            val sensorDegrees = characteristics.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            val displayDegrees = getDisplayRotationDegrees()

            // Angle to rotate preview so "up" in the image matches "up" on screen.
            // Use (sensor + display) % 360 for correct orientation on Android TV / external USB cameras.
            val rotationDegrees = (sensorDegrees + displayDegrees) % 360
            val matrix = getPreviewRotationMatrix(rotationDegrees)
            // Use reflection: SurfaceTexture.setTransform(float[]) may not resolve in some Flutter/Kotlin setups
            val setTransformMethod: Method = surfaceTexture.javaClass.getMethod("setTransform", FloatArray::class.java)
            setTransformMethod.invoke(surfaceTexture, matrix)

            Log.d(TAG, "   Preview orientation: sensor=$sensorDegrees°, display=$displayDegrees° -> apply $rotationDegrees°")
        } catch (e: Exception) {
            Log.w(TAG, "   Could not apply preview orientation: ${e.message}")
        }
    }

    private fun setupCaptureTimeout() {
        captureTimeoutHandler = android.os.Handler(android.os.Looper.getMainLooper())
        captureTimeoutRunnable = Runnable {
            Log.e(TAG, "❌ TIMEOUT: Photo capture timed out after 8 seconds")
            Bugsnag.leaveBreadcrumb("Photo capture timeout after 8 seconds")
            Log.e(TAG, "   ImageReader never received the image data")
            Log.e(TAG, "   This may indicate the external camera doesn't support JPEG capture properly")
            
            pendingPhotoResult?.error(
                "CAPTURE_TIMEOUT",
                "Photo capture timed out after 8 seconds. The camera may not support still image capture or is not responding.",
                null
            )
            pendingPhotoResult = null
        }
        captureTimeoutHandler?.postDelayed(captureTimeoutRunnable!!, 8000)
    }

    private fun cancelCaptureTimeout() {
        captureTimeoutRunnable?.let { runnable ->
            captureTimeoutHandler?.removeCallbacks(runnable)
        }
    }

    private fun handleCaptureError(e: Exception, errorType: String, result: MethodChannel.Result) {
        Log.e(TAG, "❌ Error taking picture: ${e.message}", e)
        Bugsnag.leaveBreadcrumb("Capture error: $errorType - ${e.message}")
        cancelCaptureTimeout()
        result.error("CAPTURE_ERROR", "Failed to capture photo: ${e.message}", null)
        pendingPhotoResult = null
    }

    /**
     * Saves the captured image to a file, scaling down if needed so the saved JPEG
     * fits within MAX_SAVED_DIMENSION. This keeps memory and disk usage low on
     * 4K cameras and 2GB/4GB RAM devices:
     * - Raw JPEG is written to a temp file in 64KB chunks (no full-image allocation).
     * - Decode uses BitmapFactory with inSampleSize so we never load a full 4K bitmap.
     * - Final file is scaled JPEG at ~1024px and 85% quality, ready for upload.
     */
    private fun saveImageToFile(image: Image) {
        val buffer = image.planes[0].buffer
        val totalSize = buffer.remaining()
        Log.d(TAG, "   Saving image: $totalSize bytes (chunked write, then scale-at-save)")

        val tempDir = File(context.cacheDir, "photos")
        if (!tempDir.exists()) {
            tempDir.mkdirs()
        }

        val timestamp = System.currentTimeMillis()
        val rawFile = File(tempDir, "photo_${timestamp}_raw.jpg")
        val finalFile = File(tempDir, "photo_$timestamp.jpg")

        // 1) Write raw JPEG to temp file in chunks (avoids holding full image in memory)
        val chunk = ByteArray(SAVE_CHUNK_SIZE.coerceAtMost(totalSize))
        FileOutputStream(rawFile).use { output ->
            var remaining = totalSize
            while (remaining > 0) {
                val toRead = minOf(chunk.size, remaining)
                buffer.get(chunk, 0, toRead)
                output.write(chunk, 0, toRead)
                remaining -= toRead
            }
        }

        // 2) Decode with inSampleSize so we never load full 4K bitmap (low-memory)
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeFile(rawFile.absolutePath, bounds)
        val w = bounds.outWidth
        val h = bounds.outHeight
        val sampleSize = when {
            w <= 0 || h <= 0 -> 1
            else -> minOf(w, h).let { minDim ->
                var s = 1
                while (minDim / s > MAX_SAVED_DIMENSION) s *= 2
                s
            }
        }
        Log.d(TAG, "   Decoding at inSampleSize=$sampleSize (original ${w}x${h})")

        val opts = BitmapFactory.Options().apply { inSampleSize = sampleSize }
        val bitmap = BitmapFactory.decodeFile(rawFile.absolutePath, opts)
        rawFile.delete()

        if (bitmap == null) {
            Log.e(TAG, "❌ Failed to decode image for scaling")
            pendingPhotoResult?.error("SAVE_ERROR", "Failed to decode image", null)
            pendingPhotoResult = null
            return
        }

        try {
            // 3) Optionally scale down further if inSampleSize still left us above MAX_SAVED_DIMENSION
            val targetBitmap = if (bitmap.width <= MAX_SAVED_DIMENSION && bitmap.height <= MAX_SAVED_DIMENSION) {
                bitmap
            } else {
                val scale = minOf(MAX_SAVED_DIMENSION.toFloat() / bitmap.width, MAX_SAVED_DIMENSION.toFloat() / bitmap.height)
                val nw = (bitmap.width * scale).toInt().coerceAtLeast(1)
                val nh = (bitmap.height * scale).toInt().coerceAtLeast(1)
                Bitmap.createScaledBitmap(bitmap, nw, nh, true).also { if (it != bitmap) bitmap.recycle() }
            }

            FileOutputStream(finalFile).use { out ->
                targetBitmap.compress(Bitmap.CompressFormat.JPEG, SAVED_JPEG_QUALITY, out)
            }
            if (targetBitmap !== bitmap) targetBitmap.recycle() else bitmap.recycle()

            Log.d(TAG, "✅ Image saved (scaled): ${finalFile.absolutePath}")
            pendingPhotoResult?.success(mapOf(
                "success" to true,
                "path" to finalFile.absolutePath
            ))
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error scaling/saving image: ${e.message}", e)
            bitmap.recycle()
            rawFile.delete()
            finalFile.delete()
            pendingPhotoResult?.error("SAVE_ERROR", "Failed to save image: ${e.message}", null)
        }
        pendingPhotoResult = null
    }

    /**
     * Chooses optimal size from available sizes
     * CRITICAL: Ensures size never exceeds MAX_PREVIEW_WIDTH x MAX_PREVIEW_HEIGHT
     * This prevents texture registry failures with 4K cameras
     */
    private fun chooseOptimalSize(choices: List<Size>): Size {
        if (choices.isEmpty()) {
            Log.d(TAG, "⚠️ No camera sizes available, using fallback: 1920×1080")
            return Size(1920, 1080)
        }
        
        // Log all available sizes for debugging
        Log.d(TAG, "   Available sizes: ${choices.size} options")
        
        // First, try to find the largest size that fits within our max limits
        // Sort by resolution (descending) and find first that fits
        val sizesWithinLimits = choices
            .filter { size ->
                size.width <= MAX_PREVIEW_WIDTH && size.height <= MAX_PREVIEW_HEIGHT
            }
            .sortedByDescending { it.width * it.height }
        
        if (sizesWithinLimits.isNotEmpty()) {
            val selectedSize = sizesWithinLimits.first()
            Log.d(TAG, "   ✅ Selected size within limits: ${selectedSize.width}×${selectedSize.height}")
            Bugsnag.leaveBreadcrumb("Camera resolution selected: ${selectedSize.width}×${selectedSize.height}")
            return selectedSize
        }
        
        // If NO size fits (e.g., 4K camera only reports 3840×2160, 2560×1440, etc.),
        // we MUST enforce our limits to prevent texture registry failures
        Log.w(TAG, "   ⚠️ WARNING: All camera sizes exceed maximum limits!")
        Log.w(TAG, "   Camera appears to be 4K or higher resolution")
        Log.w(TAG, "   Will use maximum supported size: $MAX_PREVIEW_WIDTH×$MAX_PREVIEW_HEIGHT")
        Bugsnag.leaveBreadcrumb("Camera resolution capped: using $MAX_PREVIEW_WIDTH×$MAX_PREVIEW_HEIGHT (hardware downscale)")
        
        // Return our max supported size - the camera will downscale automatically
        return Size(MAX_PREVIEW_WIDTH, MAX_PREVIEW_HEIGHT)
    }

    /**
     * Chooses capture size for ImageReader. Uses lower cap on low-RAM devices (e.g. Android TV 2GB)
     * to avoid OOM/hang when capturing from 4K webcams.
     */
    private fun chooseOptimalCaptureSize(choices: List<Size>): Size {
        val (maxW, maxH) = if (isLowMemoryDevice()) {
            Log.d(TAG, "   📱 Low-memory device: capping capture at ${LOW_MEMORY_CAPTURE_WIDTH}×${LOW_MEMORY_CAPTURE_HEIGHT}")
            Bugsnag.leaveBreadcrumb("Low-memory device: using ${LOW_MEMORY_CAPTURE_WIDTH}x${LOW_MEMORY_CAPTURE_HEIGHT} capture")
            LOW_MEMORY_CAPTURE_WIDTH to LOW_MEMORY_CAPTURE_HEIGHT
        } else {
            MAX_CAPTURE_WIDTH to MAX_CAPTURE_HEIGHT
        }
        if (choices.isEmpty()) {
            Log.d(TAG, "⚠️ No JPEG capture sizes available, using fallback: ${maxW}×${maxH}")
            return Size(maxW, maxH)
        }
        val sizesWithinLimits = choices
            .filter { it.width <= maxW && it.height <= maxH }
            .sortedByDescending { it.width * it.height }
        if (sizesWithinLimits.isNotEmpty()) {
            val selected = sizesWithinLimits.first()
            Log.d(TAG, "   ✅ Capture size within limits: ${selected.width}×${selected.height}")
            return selected
        }
        Log.w(TAG, "   ⚠️ All JPEG sizes exceed limit; using ${maxW}×${maxH} (e.g. 4K webcam on low-RAM)")
        Bugsnag.leaveBreadcrumb("Capture capped to ${maxW}x${maxH} for memory")
        return Size(maxW, maxH)
    }

    private fun isLowMemoryDevice(): Boolean {
        return try {
            val am = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager ?: return false
            am.memoryClass <= LOW_MEMORY_CLASS_MB
        } catch (e: Exception) {
            Log.w(TAG, "Could not get memory class: ${e.message}")
            false
        }
    }

    /**
     * Starts background thread for camera operations
     */
    private fun startBackgroundThread() {
        backgroundThread = HandlerThread("CameraBackground").also { it.start() }
        backgroundHandler = Handler(backgroundThread?.looper!!)
    }

    /**
     * Stops background thread
     */
    private fun stopBackgroundThread() {
        backgroundThread?.quitSafely()
        try {
            backgroundThread?.join()
            backgroundThread = null
            backgroundHandler = null
        } catch (e: InterruptedException) {
            Log.e(TAG, "Error stopping background thread: ${e.message}")
        }
    }

    /**
     * Closes the camera and releases resources
     */
    fun dispose() {
        Log.d(TAG, "🔄 Disposing camera controller")
        Bugsnag.leaveBreadcrumb("Camera disposal started")
        Log.d(TAG, "   pendingPhotoResult: ${pendingPhotoResult != null}")
        
        // Set disposing flag to prevent new captures
        isDisposing = true
        
        // Wait for any in-progress capture to complete (max 2 seconds)
        if (pendingPhotoResult != null) {
            Log.w(TAG, "⚠️ Capture in progress, waiting up to 2 seconds for it to complete...")
            Bugsnag.leaveBreadcrumb("Waiting for in-progress capture before disposal")
            var waitTime = 0
            while (pendingPhotoResult != null && waitTime < 2000) {
                try {
                    Thread.sleep(100)
                    waitTime += 100
                } catch (e: InterruptedException) {
                    Log.e(TAG, "Wait interrupted: ${e.message}")
                    break
                }
            }
            
            if (pendingPhotoResult != null) {
                Log.e(TAG, "❌ Capture still in progress after 2 seconds, forcing disposal")
                Bugsnag.leaveBreadcrumb("Forced disposal: capture still in progress after 2s")
                Log.e(TAG, "   Capture may fail with 'Camera is closed' error")
            } else {
                Log.d(TAG, "   ✅ Capture completed, safe to dispose")
                Bugsnag.leaveBreadcrumb("Capture completed, proceeding with disposal")
            }
        }
        
        closeCamera()
        stopBackgroundThread()
        
        // Reset flag
        isDisposing = false
        Bugsnag.leaveBreadcrumb("Camera disposal completed")
    }

    /**
     * Closes camera resources
     */
    private fun closeCamera() {
        // Cancel any pending capture timeout
        cancelCaptureTimeout()
        captureTimeoutHandler = null
        captureTimeoutRunnable = null
        
        // Cancel any pending photo capture
        if (pendingPhotoResult != null) {
            Log.w(TAG, "   ⚠️ Cancelling pending photo capture due to camera closure")
            pendingPhotoResult?.error("CANCELLED", "Camera closed during capture", null)
            pendingPhotoResult = null
        }
        
        // Clean up preview surface
        previewSurface?.release()
        previewSurface = null
        // Cancel any pending preview requests
        pendingPreviewResult?.error("CANCELLED", "Camera closed", null)
        pendingPreviewResult = null

        captureSession?.close()
        captureSession = null

        cameraDevice?.close()
        cameraDevice = null

        // CRITICAL: Remove ImageReader listener BEFORE closing to prevent callbacks
        // on detached Flutter engine (FlutterJNI not attached error)
        imageReader?.setOnImageAvailableListener(null, null)
        imageReader?.close()
        imageReader = null

        textureEntry?.release()
        textureEntry = null

        currentCameraId = null
        textureId = -1
    }

    /**
     * Gets the current texture ID for Flutter preview
     */
    fun getTextureId(): Long = textureId

    /**
     * Checks if camera is initialized
     */
    fun isInitialized(): Boolean = cameraDevice != null && captureSession != null
}
