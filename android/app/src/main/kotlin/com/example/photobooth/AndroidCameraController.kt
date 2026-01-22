package com.example.photobooth

import android.content.Context
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
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.io.FileOutputStream

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

    private val cameraStateCallback =
        object : CameraDevice.StateCallback() {
        override fun onOpened(camera: CameraDevice) {
            Log.d(TAG, "✅ Camera opened: ${camera.id}")
            Log.d(TAG, "   Expected camera ID: $currentCameraId")
            if (camera.id != currentCameraId) {
                Log.e(TAG, "❌ ERROR: Opened camera ID (${camera.id}) does not match requested ID ($currentCameraId)!")
            } else {
                Log.d(TAG, "✅ Camera ID matches requested ID")
            }
            cameraDevice = camera
            createCaptureSession()
        }

        override fun onDisconnected(camera: CameraDevice) {
            Log.d(TAG, "⚠️ Camera disconnected: ${camera.id}")
            closeCamera()
        }

        override fun onError(
            camera: CameraDevice,
            error: Int,
        ) {
            Log.e(TAG, "❌ Camera error: $error")
            val errorMsg =
                when (error) {
                    1 -> "Camera device error" // STATE_ERROR_CAMERA_DEVICE

                    2 -> "Camera disabled" // STATE_ERROR_CAMERA_DISABLED

                    3 -> "Camera in use" // STATE_ERROR_CAMERA_IN_USE

                    4 -> "Max cameras in use" // STATE_ERROR_MAX_CAMERAS_IN_USE

                    else -> "Unknown camera error"
                }
            pendingPhotoResult?.error("CAMERA_ERROR", errorMsg, null)
            pendingPhotoResult = null
            closeCamera()
        }
    }

    private var pendingPreviewResult: MethodChannel.Result? = null

    private val captureStateCallback =
        object : CameraCaptureSession.StateCallback() {
        override fun onConfigured(session: CameraCaptureSession) {
            Log.d(TAG, "✅ Capture session configured")
            captureSession = session

            // If there's a pending preview request, start it now
            pendingPreviewResult?.let { result ->
                Log.d(TAG, "🎬 Starting preview (pending request from before session was ready)")
                startPreviewInternal(result)
                pendingPreviewResult = null
            }
        }

        override fun onConfigureFailed(session: CameraCaptureSession) {
            Log.e(TAG, "❌ Capture session configuration failed")
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
                pendingPhotoResult?.error("CAPTURE_ERROR", "Photo capture failed: ${failure.reason}", null)
                pendingPhotoResult = null
            }
        }

    private val imageAvailableListener =
        ImageReader.OnImageAvailableListener { reader ->
        Log.d(TAG, "📸 imageAvailableListener triggered")
        
        // CRITICAL: Check if camera is still active/initialized
        // Prevents "FlutterJNI not attached" errors when callback fires after disposal
        if (cameraDevice == null || textureEntry == null) {
            Log.w(TAG, "⚠️ imageAvailableListener called but camera already disposed. Ignoring.")
            // Acquire and immediately close any pending image to clear the queue
            try {
                reader.acquireLatestImage()?.close()
            } catch (e: Exception) {
                Log.e(TAG, "Error closing orphaned image: ${e.message}")
            }
            return@OnImageAvailableListener
        }
        
        // Cancel timeout since we received the image
        captureTimeoutRunnable?.let { runnable ->
            captureTimeoutHandler?.removeCallbacks(runnable)
            Log.d(TAG, "   ✅ Cancelled capture timeout")
        }
        
        val image = reader.acquireLatestImage()
        if (image == null) {
            Log.e(TAG, "❌ acquireLatestImage returned null")
            pendingPhotoResult?.error("CAPTURE_ERROR", "Failed to acquire image from reader", null)
            pendingPhotoResult = null
            return@OnImageAvailableListener
        }
        
        try {
            Log.d(TAG, "   Processing captured image...")
            saveImageToFile(image)
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error saving image: ${e.message}", e)
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
            Log.d(TAG, "🎥 Initializing camera: $cameraId")
            Log.d(TAG, "   Camera ID type: ${cameraId::class.java.simpleName}")
            Log.d(TAG, "   Camera ID value: \"$cameraId\"")

            cameraManager = context.getSystemService(Context.CAMERA_SERVICE) as CameraManager

            // Verify camera exists by trying to get its characteristics
            // Note: Some external cameras (like USB cameras) may not be in the initial cameraIdList
            // but can still be accessed directly by their ID
            val cameraIds = cameraManager?.cameraIdList
            Log.d(TAG, "   Available camera IDs in initial list: ${cameraIds?.joinToString(", ") ?: "null"}")

            // Try to get camera characteristics directly
            // This will work even if the camera is not in the initial cameraIdList
            val characteristics = try {
                cameraManager?.getCameraCharacteristics(cameraId)
            } catch (e: IllegalArgumentException) {
                Log.e(TAG, "❌ Camera $cameraId does not exist or cannot be accessed")
                Log.e(TAG, "   Error: ${e.message}")
                Log.e(TAG, "   Available cameras in initial list: ${cameraIds?.joinToString(", ") ?: "none"}")
                result.error(
                    "CAMERA_NOT_FOUND",
                    "Camera $cameraId not found or cannot be accessed. " +
                        "Available cameras: ${cameraIds?.joinToString(", ") ?: "none"}",
                    null,
                )
                return
            } catch (e: CameraAccessException) {
                Log.e(TAG, "❌ Camera access exception for camera $cameraId: ${e.message}")
                result.error("CAMERA_ACCESS_ERROR", "Cannot access camera $cameraId: ${e.message}", null)
                return
            }

            if (characteristics == null) {
                Log.e(TAG, "❌ Camera $cameraId characteristics are null")
                result.error("CAMERA_NOT_FOUND", "Camera $cameraId characteristics are null", null)
                return
            }

            if (cameraIds?.contains(cameraId) == true) {
                Log.d(TAG, "✅ Camera $cameraId found in cameraIdList")
            } else {
                Log.d(TAG, "✅ Camera $cameraId found (not in initial cameraIdList - likely external USB camera)")
            }
            val facing = characteristics?.get(CameraCharacteristics.LENS_FACING)
            val cameraName =
                when (facing) {
                    CameraCharacteristics.LENS_FACING_BACK -> "Back Camera"
                    CameraCharacteristics.LENS_FACING_FRONT -> "Front Camera"
                    CameraCharacteristics.LENS_FACING_EXTERNAL -> "External Camera"
                    else -> "Camera $cameraId"
                }

            Log.d(TAG, "   Camera characteristics:")
            Log.d(TAG, "     LENS_FACING: $facing")
            Log.d(TAG, "     Camera name: $cameraName")

            currentCameraId = cameraId
            Log.d(TAG, "   Stored currentCameraId: $currentCameraId")

            // Start background thread
            startBackgroundThread()

            // Create texture for preview
            try {
                textureEntry = textureRegistry.createSurfaceTexture()
                textureId = textureEntry!!.id()
                Log.d(TAG, "   ✅ Texture created with ID: $textureId")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create texture: ${e.message}")
                result.error(
                    "INIT_ERROR",
                    "Texture registry not available. Please ensure Flutter engine is properly initialized.",
                    null,
                )
                return
            }
            
            val surfaceTexture = textureEntry!!.surfaceTexture()

            // Get available sizes from camera
            val map = characteristics?.get(CameraCharacteristics.SCALER_STREAM_CONFIGURATION_MAP)
            val availablePreviewSizes = map?.getOutputSizes(SurfaceTexture::class.java)?.toList() ?: emptyList()
            val availableCaptureSizes = map?.getOutputSizes(ImageFormat.JPEG)?.toList() ?: emptyList()
            
            // Log available sizes for debugging 4K camera issues
            Log.d(TAG, "   📐 Available preview sizes (${availablePreviewSizes.size}):")
            availablePreviewSizes.take(5).forEach { size ->
                Log.d(TAG, "      - ${size.width}×${size.height}")
            }
            if (availablePreviewSizes.size > 5) {
                Log.d(TAG, "      ... and ${availablePreviewSizes.size - 5} more")
            }
            
            Log.d(TAG, "   📐 Available JPEG capture sizes (${availableCaptureSizes.size}):")
            availableCaptureSizes.take(5).forEach { size ->
                Log.d(TAG, "      - ${size.width}×${size.height}")
            }
            if (availableCaptureSizes.size > 5) {
                Log.d(TAG, "      ... and ${availableCaptureSizes.size - 5} more")
            }
            
            // Set preview size (with hard limit enforcement)
            val previewSize = chooseOptimalSize(availablePreviewSizes)
            Log.d(TAG, "   🎯 Selected preview size: ${previewSize.width}×${previewSize.height}")
            
            try {
                surfaceTexture.setDefaultBufferSize(previewSize.width, previewSize.height)
                Log.d(TAG, "   ✅ Preview buffer size set successfully")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to set preview buffer size: ${e.message}")
                result.error(
                    "INIT_ERROR",
                    "Failed to set preview buffer size: ${e.message}",
                    null,
                )
                return
            }
            
            val surface = Surface(surfaceTexture)

            // Create ImageReader for photo capture (with hard limit enforcement)
            val imageReaderSize = chooseOptimalSize(availableCaptureSizes)
            Log.d(TAG, "   🎯 Selected capture size: ${imageReaderSize.width}×${imageReaderSize.height}")
            
            try {
                imageReader =
                    ImageReader.newInstance(
                        imageReaderSize.width,
                        imageReaderSize.height,
                        ImageFormat.JPEG,
                        1,
                    )
                Log.d(TAG, "   ✅ ImageReader created successfully")
                imageReader?.setOnImageAvailableListener(imageAvailableListener, backgroundHandler)
            } catch (e: Exception) {
                Log.e(TAG, "❌ Failed to create ImageReader: ${e.message}")
                result.error(
                    "INIT_ERROR",
                    "Failed to create ImageReader for photo capture: ${e.message}",
                    null,
                )
                return
            }

            // Open camera
            cameraManager?.openCamera(cameraId, cameraStateCallback, backgroundHandler)

            result.success(
                mapOf(
                    "success" to true,
                    "textureId" to textureId,
                    "localizedName" to cameraName,
                ),
            )
        } catch (e: SecurityException) {
            Log.e(TAG, "Security exception: ${e.message}", e)
            result.error("PERMISSION_ERROR", "Camera permission not granted", null)
        } catch (e: Exception) {
            Log.e(TAG, "Error initializing camera: ${e.message}", e)
            result.error("INIT_ERROR", e.message, null)
        }
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
            Log.d(TAG, "   Active camera device ID: ${device.id}")
            Log.d(TAG, "   Expected camera ID: $currentCameraId")
            if (device.id != currentCameraId) {
                Log.e(TAG, "❌ ERROR: Preview is using wrong camera! Expected $currentCameraId, got ${device.id}")
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
        Log.d(TAG, "📸 takePicture() called")
        Log.d(TAG, "   captureSession: ${captureSession != null}")
        Log.d(TAG, "   imageReader: ${imageReader != null}")
        Log.d(TAG, "   cameraDevice: ${cameraDevice != null}")
        
        if (captureSession == null || imageReader == null) {
            val error = "Camera not initialized - captureSession or imageReader is null"
            Log.e(TAG, "❌ $error")
            result.error("NOT_INITIALIZED", error, null)
            return
        }

        pendingPhotoResult = result

        try {
            val device = cameraDevice ?: run {
                val error = "Camera device not available"
                Log.e(TAG, "❌ $error")
                result.error("NOT_INITIALIZED", error, null)
                return
            }

            Log.d(TAG, "📸 Taking picture")
            Log.d(TAG, "   Active camera device ID: ${device.id}")
            Log.d(TAG, "   Expected camera ID: $currentCameraId")
            if (device.id != currentCameraId) {
                Log.e(TAG, "❌ ERROR: Capture is using wrong camera! Expected $currentCameraId, got ${device.id}")
            }

            val characteristics = cameraManager?.getCameraCharacteristics(device.id)
            val facing = characteristics?.get(CameraCharacteristics.LENS_FACING)
            Log.d(TAG, "   Camera LENS_FACING: $facing")

            val builder = device.createCaptureRequest(CameraDevice.TEMPLATE_STILL_CAPTURE)
            builder.addTarget(imageReader!!.surface)

            // Set auto-focus and auto-exposure
            builder.set(CaptureRequest.CONTROL_AF_MODE, CaptureRequest.CONTROL_AF_MODE_CONTINUOUS_PICTURE)
            builder.set(CaptureRequest.CONTROL_AE_MODE, CaptureRequest.CONTROL_AE_MODE_ON)

            // Set JPEG orientation
            val sensorOrientation = characteristics?.get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 0
            builder.set(CaptureRequest.JPEG_ORIENTATION, sensorOrientation)

            // Set up timeout for capture (8 seconds)
            // If ImageReader doesn't receive the image within this time, we'll return an error
            captureTimeoutHandler = android.os.Handler(android.os.Looper.getMainLooper())
            captureTimeoutRunnable = Runnable {
                Log.e(TAG, "❌ TIMEOUT: Photo capture timed out after 8 seconds")
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
            
            // Capture
            captureSession?.capture(builder.build(), captureCallback, backgroundHandler)
            Log.d(TAG, "📸 Capture request sent to camera")
            Log.d(TAG, "   Waiting for ImageReader callback (timeout: 8s)...")
        } catch (e: CameraAccessException) {
            Log.e(TAG, "❌ Error taking picture: ${e.message}", e)
            
            // Cancel timeout on error
            captureTimeoutRunnable?.let { runnable ->
                captureTimeoutHandler?.removeCallbacks(runnable)
            }
            
            result.error("CAPTURE_ERROR", "Failed to capture photo: ${e.message}", null)
            pendingPhotoResult = null
        } catch (e: Exception) {
            Log.e(TAG, "❌ Unexpected error taking picture: ${e.message}", e)
            
            // Cancel timeout on error
            captureTimeoutRunnable?.let { runnable ->
                captureTimeoutHandler?.removeCallbacks(runnable)
            }
            
            result.error("CAPTURE_ERROR", "Unexpected error: ${e.message}", null)
            pendingPhotoResult = null
        }
    }

    /**
     * Saves the captured image to a file
     */
    private fun saveImageToFile(image: Image) {
        val buffer = image.planes[0].buffer
        val bytes = ByteArray(buffer.remaining())
        buffer.get(bytes)

        val tempDir = File(context.cacheDir, "photos")
        if (!tempDir.exists()) {
            tempDir.mkdirs()
        }

        val fileName = "photo_${System.currentTimeMillis()}.jpg"
        val file = File(tempDir, fileName)

        FileOutputStream(file).use { output ->
            output.write(bytes)
        }

        Log.d(TAG, "✅ Image saved: ${file.absolutePath}")
        pendingPhotoResult?.success(mapOf(
            "success" to true,
            "path" to file.absolutePath
        ))
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
            return selectedSize
        }
        
        // If NO size fits (e.g., 4K camera only reports 3840×2160, 2560×1440, etc.),
        // we MUST enforce our limits to prevent texture registry failures
        Log.w(TAG, "   ⚠️ WARNING: All camera sizes exceed maximum limits!")
        Log.w(TAG, "   Camera appears to be 4K or higher resolution")
        Log.w(TAG, "   Will use maximum supported size: $MAX_PREVIEW_WIDTH×$MAX_PREVIEW_HEIGHT")
        
        // Return our max supported size - the camera will downscale automatically
        return Size(MAX_PREVIEW_WIDTH, MAX_PREVIEW_HEIGHT)
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
        closeCamera()
        stopBackgroundThread()
    }

    /**
     * Closes camera resources
     */
    private fun closeCamera() {
        // Cancel any pending capture timeout
        captureTimeoutRunnable?.let { runnable ->
            captureTimeoutHandler?.removeCallbacks(runnable)
        }
        captureTimeoutHandler = null
        captureTimeoutRunnable = null
        
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
