package com.example.photobooth

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.graphics.SurfaceTexture
import android.hardware.usb.UsbDevice
import android.hardware.usb.UsbManager
import android.util.Log
import android.view.Surface
// UVCCamera library imports
import com.serenegiant.usb.USBMonitor
import com.serenegiant.usb.UVCCamera
import com.serenegiant.usb.IFrameCallback
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.nio.BufferUnderflowException
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference
import kotlin.concurrent.thread

/**
 * UVC Camera Controller using UVCCamera library
 * This provides full UVC camera support including video streaming and photo capture
 */
class UvcCameraController(
    private val context: Context,
    private val textureRegistry: TextureRegistry?,
    private val onUsbDisconnected: ((String) -> Unit)? = null
) {
    companion object {
        private const val TAG = "UvcCameraController"
        private const val PREVIEW_WIDTH = 1280
        private const val PREVIEW_HEIGHT = 720
        // UVCCamera constant
        private const val PREVIEW_FORMAT = UVCCamera.FRAME_FORMAT_MJPEG
        
        /**
         * Check if a USB device is a UVC camera
         */
        fun isUvcCamera(device: UsbDevice): Boolean {
            for (i in 0 until device.interfaceCount) {
                val intf = device.getInterface(i)
                if (intf.interfaceClass == 14) { // USB_VIDEO_CLASS
                    return true
                }
            }
            return false
        }
    }

    private var usbManager: UsbManager? = null
    private var usbDevice: UsbDevice? = null
    // UVCCamera types
    private var usbMonitor: USBMonitor? = null
    private var uvcCamera: UVCCamera? = null
    private var usbControlBlock: USBMonitor.UsbControlBlock? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surfaceTexture: SurfaceTexture? = null
    private var surface: Surface? = null
    private var isInitialized = false
    private var isPreviewActive = false
    
    // Frame capture state - synchronized to prevent race conditions
    @Volatile
    private var captureLatch: CountDownLatch? = null
    private val captureLock = Any()
    private val latestFrame = AtomicReference<ByteArray?>(null)
    private val frameCallback: IFrameCallback = object : IFrameCallback {
        override fun onFrame(frame: ByteBuffer) {
            // Use synchronized block to safely access captureLatch
            synchronized(captureLock) {
                val latch = captureLatch
                if (latch != null) {
                    try {
                        // Validate ByteBuffer is not null and is valid
                        if (frame == null || !frame.isDirect) {
                            Log.w(TAG, "⚠️ Invalid frame buffer received")
                            captureLatch = null
                            latch.countDown()
                            return
                        }
                        
                        // Copy frame data from ByteBuffer immediately
                        // The ByteBuffer is a direct buffer from native code and may be reused
                        // We must copy the data synchronously in this callback
                        val frameSize = frame.remaining()
                        if (frameSize > 0 && frameSize <= 10 * 1024 * 1024) { // Max 10MB sanity check
                            // Create a new byte array and copy data directly
                            val frameArray = ByteArray(frameSize)
                            
                            // Copy data directly - don't modify the original buffer
                            val originalPosition = frame.position()
                            try {
                                frame.get(frameArray)
                                // Restore position (though native library may not need it)
                                frame.position(originalPosition)
                                
                                // Store the copied frame data
                                latestFrame.set(frameArray)
                                captureLatch = null // Clear the latch reference
                                latch.countDown() // Signal that frame is captured
                                Log.d(TAG, "✅ Frame captured for photo: ${frameArray.size} bytes")
                            } catch (e: BufferUnderflowException) {
                                Log.e(TAG, "❌ Buffer underflow - frame may have been invalidated: ${e.message}")
                                captureLatch = null
                                latch.countDown()
                            }
                        } else {
                            Log.w(TAG, "⚠️ Frame buffer is empty or invalid size: $frameSize")
                            captureLatch = null
                            latch.countDown() // Signal even if empty
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error capturing frame: ${e.message}", e)
                        captureLatch = null
                        latch.countDown() // Signal even on error to unblock
                    }
                }
            }
        }
    }

    /**
     * Initialize UVC camera with USB device
     */
    fun initialize(usbDevice: UsbDevice, result: MethodChannel.Result) {
        try {
            Log.d(TAG, "🎥 Initializing UVC camera: ${usbDevice.deviceName}")
            Log.d(TAG, "   Vendor ID: ${usbDevice.vendorId}, Product ID: ${usbDevice.productId}")

            this.usbDevice = usbDevice
            usbManager = context.getSystemService(Context.USB_SERVICE) as UsbManager

            // Check if we have permission
            if (!usbManager!!.hasPermission(usbDevice)) {
                Log.e(TAG, "❌ No USB permission for device")
                result.error("USB_PERMISSION", "USB permission not granted for device", null)
                return
            }

            // Create texture entry for preview
            textureEntry = textureRegistry?.createSurfaceTexture()
            if (textureEntry == null) {
                Log.e(TAG, "❌ Failed to create texture entry")
                result.error("TEXTURE_ERROR", "Failed to create texture entry", null)
                return
            }

            // Initialize USBMonitor but DON'T call register() to avoid scanning all USB devices
            // This prevents SecurityException when accessing devices we don't have permission for
            usbMonitor = USBMonitor(context, onDeviceConnectListener)
            // usbMonitor?.register() // DON'T register - this scans all devices and causes crashes
            
            // Get control block directly using openDevice (which doesn't require register())
            // This requires permission which we already have
            try {
                Log.d(TAG, "   📋 Getting USB control block directly...")
                usbControlBlock = usbMonitor?.openDevice(usbDevice)
                if (usbControlBlock == null) {
                    Log.e(TAG, "❌ Failed to get USB control block")
                    result.error("USB_ERROR", "Failed to get USB control block. Device may need to be reconnected.", null)
                    return
                }
                Log.d(TAG, "✅ USB control block obtained")
            } catch (e: SecurityException) {
                Log.e(TAG, "❌ SecurityException getting control block: ${e.message}", e)
                result.error("USB_PERMISSION", "USB permission error: ${e.message}", null)
                return
            } catch (e: Exception) {
                Log.e(TAG, "❌ Exception getting control block: ${e.message}", e)
                result.error("USB_ERROR", "Failed to get USB control block: ${e.message}", null)
                return
            }

            // Create and open camera
            try {
                uvcCamera = UVCCamera()
                uvcCamera?.open(usbControlBlock!!)
                Log.d(TAG, "✅ UVCCamera opened successfully")
                
                // CRITICAL: Wait for USB event thread to fully initialize
                // The USB event thread is started when the camera is opened
                // We need to give it time to set up USB context and transfer buffers
                // before proceeding with surface setup
                // Increased delay to reduce race conditions in USB event handling
                Thread.sleep(1000) // Increased from 500ms to 1000ms
                Log.d(TAG, "   USB event thread initialization delay completed")
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error opening UVCCamera: ${e.message}", e)
                result.error("UVC_ERROR", "Failed to open UVCCamera: ${e.message}", null)
                return
            }

            // Set up surface texture
            // Use the SurfaceTexture provided by the texture entry (same as AndroidCameraController)
            surfaceTexture = textureEntry!!.surfaceTexture()
            if (surfaceTexture == null) {
                Log.e(TAG, "❌ SurfaceTexture is null from texture entry")
                result.error("TEXTURE_ERROR", "Failed to get SurfaceTexture from texture entry", null)
                return
            }
            
            // Set buffer size BEFORE creating Surface to ensure proper initialization
            surfaceTexture?.setDefaultBufferSize(PREVIEW_WIDTH, PREVIEW_HEIGHT)
            
            // Create Surface from SurfaceTexture (needed for fallback, but we'll use setPreviewTexture)
            surface = Surface(surfaceTexture)
            
            // Verify texture ID matches
            val textureId = textureEntry!!.id()
            Log.d(TAG, "   SurfaceTexture ready: ${surfaceTexture != null}")
            Log.d(TAG, "   Texture ID: $textureId")
            Log.d(TAG, "   Buffer size set: ${PREVIEW_WIDTH}x${PREVIEW_HEIGHT}")

            isInitialized = true
            Log.d(TAG, "✅ UVC camera initialized successfully")
            Log.d(TAG, "   Texture ID: $textureId")

            result.success(mapOf(
                "success" to true,
                "textureId" to textureEntry!!.id(),
                "deviceName" to (usbDevice.deviceName ?: "Unknown")
            ))
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error initializing UVC camera: ${e.message}", e)
            result.error("INIT_ERROR", "Failed to initialize UVC camera: ${e.message}", null)
        }
    }


    /**
     * USBMonitor device connect listener
     */
    private val onDeviceConnectListener = object : USBMonitor.OnDeviceConnectListener {
        override fun onAttach(device: UsbDevice) {
            Log.d(TAG, "📎 USB device attached: ${device.deviceName}")
        }

        override fun onDettach(device: UsbDevice) {
            Log.d(TAG, "📎 USB device detached: ${device.deviceName}")
            if (device == usbDevice) {
                val deviceName = device.deviceName ?: "Unknown"
                dispose()
                // Notify callback about USB disconnection
                onUsbDisconnected?.invoke(deviceName)
            }
        }

        override fun onConnect(
            device: UsbDevice,
            ctrlBlock: USBMonitor.UsbControlBlock,
            createNew: Boolean
        ) {
            Log.d(TAG, "✅ USB device connected: ${device.deviceName}")
            if (device == usbDevice) {
                usbControlBlock = ctrlBlock
                // If camera is not yet initialized, we can open it now
                if (!isInitialized && uvcCamera == null) {
                    try {
                        uvcCamera = UVCCamera()
                        uvcCamera?.open(ctrlBlock)
                        Log.d(TAG, "✅ UVCCamera opened via onConnect callback")
                    } catch (e: Exception) {
                        Log.e(TAG, "❌ Error opening camera in onConnect: ${e.message}", e)
                    }
                }
            }
        }

        override fun onDisconnect(device: UsbDevice, ctrlBlock: USBMonitor.UsbControlBlock) {
            Log.d(TAG, "📎 USB device disconnected: ${device.deviceName}")
            if (device == usbDevice) {
                val deviceName = device.deviceName ?: "Unknown"
                dispose()
                // Notify callback about USB disconnection
                onUsbDisconnected?.invoke(deviceName)
            }
        }

        override fun onCancel(device: UsbDevice) {
            Log.d(TAG, "❌ USB device permission cancelled: ${device.deviceName}")
        }
    }

    /**
     * Start preview
     */
    fun startPreview(result: MethodChannel.Result) {
        if (!isInitialized || uvcCamera == null) {
            result.error("NOT_INITIALIZED", "Camera not initialized", null)
            return
        }

        try {
            Log.d(TAG, "🎬 Starting UVC camera preview...")
            Log.d(TAG, "   Resolution: ${PREVIEW_WIDTH}x${PREVIEW_HEIGHT}")
            Log.d(TAG, "   Format: MJPEG")

            // Set preview size and format FIRST, before setting display
            // This ensures the camera knows what format to use
            uvcCamera?.setPreviewSize(PREVIEW_WIDTH, PREVIEW_HEIGHT, PREVIEW_FORMAT)
            
            // Small delay to let the camera process the size change
            Thread.sleep(100)

            // Set preview display using SurfaceTexture directly
            // This ensures the SurfaceTexture is properly attached to the texture ID
            if (surfaceTexture != null) {
                // Use setPreviewTexture which internally creates a Surface from the SurfaceTexture
                // This ensures proper attachment to the texture ID
                uvcCamera?.setPreviewTexture(surfaceTexture)
                Log.d(TAG, "   Preview texture set: ${surfaceTexture != null}")
                // Small delay to let the surface attach
                Thread.sleep(200)
            } else if (surface != null) {
                // Fallback to Surface if SurfaceTexture is not available
                uvcCamera?.setPreviewDisplay(surface)
                Log.d(TAG, "   Preview surface set (fallback): ${surface != null}")
                Thread.sleep(200)
            } else {
                Log.e(TAG, "❌ Both SurfaceTexture and Surface are null")
                result.error("SURFACE_ERROR", "Surface not available", null)
                return
            }

            // Start preview
            uvcCamera?.startPreview()
            
            // CRITICAL: Wait much longer after starting preview to ensure USB transfers are properly set up
            // The USB event thread needs significant time to:
            // 1. Initialize all transfer buffers
            // 2. Start the USB event processing loop
            // 3. Set up the frame processing pipeline
            // The crash happens in usbi_handle_transfer_completion when accessing transfer buffers
            // that may not be fully initialized. A longer delay reduces the chance of this race condition.
            Thread.sleep(1500) // Increased from 800ms to 1500ms
            
            // Don't set up frame callback here - we'll enable it only when capturing
            // This avoids interfering with the USB event thread during normal preview
            Log.d(TAG, "   Preview started - frame callback will be enabled on capture")

            isPreviewActive = true
            Log.d(TAG, "✅ UVC preview started successfully")
            Log.d(TAG, "   Texture ID: ${textureEntry?.id()}")
            Log.d(TAG, "   Surface: ${surface != null}")
            Log.d(TAG, "   SurfaceTexture: ${surfaceTexture != null}")
            result.success(mapOf("success" to true))
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error starting preview: ${e.message}", e)
            result.error("PREVIEW_ERROR", "Failed to start preview: ${e.message}", null)
        }
    }

    /**
     * Capture photo
     */
    fun capturePhoto(result: MethodChannel.Result) {
        if (!isInitialized || !isPreviewActive || uvcCamera == null) {
            result.error("NOT_READY", "Camera not ready for capture", null)
            return
        }

        // Process capture on background thread to avoid blocking
        thread {
            try {
                Log.d(TAG, "📸 Capturing photo from UVC camera...")
                
                // Clear previous frame
                latestFrame.set(null)
                
                // Synchronize callback setup to prevent race conditions
                val latch: CountDownLatch
                synchronized(captureLock) {
                    // Enable frame callback for capture
                    // Use NV21 format (YUV420SP) which is efficient and can be converted to JPEG
                    uvcCamera?.setFrameCallback(frameCallback, UVCCamera.PIXEL_FORMAT_NV21)
                    Log.d(TAG, "   Frame callback enabled for capture")
                    
                    // Small delay to ensure callback is set up
                    Thread.sleep(100)
                    
                    // Create a latch to wait for frame
                    latch = CountDownLatch(1)
                    captureLatch = latch
                }
                
                // Wait for frame (max 3 seconds) - wait outside synchronized block to avoid deadlock
                val frameReceived = latch.await(3, TimeUnit.SECONDS)
                
                // Disable frame callback after capture
                synchronized(captureLock) {
                    uvcCamera?.setFrameCallback(null, 0)
                    Log.d(TAG, "   Frame callback disabled after capture")
                    
                    if (!frameReceived) {
                        Log.e(TAG, "❌ No frame captured after waiting 3 seconds")
                        captureLatch = null
                        result.error("CAPTURE_TIMEOUT", "Failed to capture frame - timeout", null)
                        return@thread
                    }
                }
                
                val frameData = latestFrame.get()
                if (frameData == null) {
                    Log.e(TAG, "❌ Frame data is null after capture")
                    result.error("CAPTURE_ERROR", "Frame data is null", null)
                    return@thread
                }
                
                Log.d(TAG, "   Frame data received: ${frameData.size} bytes")
                
                // Validate frame size for NV21 format
                // NV21: Y plane (width * height) + UV plane (width * height / 2) = width * height * 3 / 2
                val expectedSize = PREVIEW_WIDTH * PREVIEW_HEIGHT * 3 / 2
                if (frameData.size != expectedSize) {
                    Log.w(TAG, "   ⚠️ Frame size mismatch: expected $expectedSize, got ${frameData.size}")
                    // Try to continue anyway - might still work
                }
                
                // Convert NV21 (YUV420SP) to JPEG
                val photoFile = File(context.getExternalFilesDir(null), "uvc_capture_${System.currentTimeMillis()}.jpg")
                photoFile.parentFile?.mkdirs()
                
                // NV21 format: Y plane + interleaved VU plane
                // Width and height from preview settings
                val yuvImage = YuvImage(
                    frameData,
                    ImageFormat.NV21,
                    PREVIEW_WIDTH,
                    PREVIEW_HEIGHT,
                    null
                )
                
                val outputStream = FileOutputStream(photoFile)
                yuvImage.compressToJpeg(
                    Rect(0, 0, PREVIEW_WIDTH, PREVIEW_HEIGHT),
                    90, // JPEG quality
                    outputStream
                )
                outputStream.close()
                
                if (photoFile.exists() && photoFile.length() > 0) {
                    Log.d(TAG, "✅ Photo captured successfully: ${photoFile.absolutePath}")
                    Log.d(TAG, "   File size: ${photoFile.length()} bytes")
                    result.success(mapOf(
                        "success" to true,
                        "photoPath" to photoFile.absolutePath
                    ))
                } else {
                    Log.e(TAG, "❌ Photo file not created or empty")
                    result.error("CAPTURE_ERROR", "Photo capture failed - file not created", null)
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ Error capturing photo: ${e.message}", e)
                captureLatch = null
                // Disable frame callback on error
                try {
                    uvcCamera?.setFrameCallback(null, 0)
                } catch (ex: Exception) {
                    Log.e(TAG, "   Error disabling frame callback: ${ex.message}")
                }
                result.error("CAPTURE_ERROR", "Failed to capture photo: ${e.message}", null)
            }
        }
    }

    /**
     * Dispose camera resources
     */
    fun dispose() {
        Log.d(TAG, "🧹 Disposing UVC camera controller...")

        try {
            // Clear frame callback if it was enabled - do this first to stop any active callbacks
            synchronized(captureLock) {
                try {
                    uvcCamera?.setFrameCallback(null, 0)
                    captureLatch = null
                    latestFrame.set(null)
                } catch (e: Exception) {
                    Log.w(TAG, "   Warning: Error clearing frame callback: ${e.message}")
                }
            }
            
            // Stop preview - this stops the USB event thread from processing frames
            if (isPreviewActive) {
                try {
                    uvcCamera?.stopPreview()
                    isPreviewActive = false
                    // Longer delay to let the preview thread and USB event handlers finish
                    // The USB event thread needs time to complete any pending transfers
                    Thread.sleep(500)
                } catch (e: Exception) {
                    Log.w(TAG, "   Warning: Error stopping preview: ${e.message}")
                }
            }
            
            // Clear capture state
            synchronized(captureLock) {
                captureLatch?.countDown() // Unblock any waiting capture
                captureLatch = null
                latestFrame.set(null)
            }

            // Close camera - this should stop the USB event thread
            // But we need to ensure all USB transfers are complete first
            try {
                // Set camera to null first to prevent any new operations
                val cameraToClose = uvcCamera
                uvcCamera = null
                
                // Then close it - this will stop the USB event thread
                cameraToClose?.close()
                
                // Wait longer for the USB event thread to fully terminate
                // The crash happens in usbi_handle_transfer_completion, so we need
                // to ensure all pending USB transfers are completed
                Thread.sleep(1000)
            } catch (e: Exception) {
                Log.w(TAG, "   Warning: Error closing camera: ${e.message}")
            }

            // Release surface
            try {
                surface?.release()
            } catch (e: Exception) {
                Log.w(TAG, "   Warning: Error releasing surface: ${e.message}")
            }
            surface = null

            // Release surface texture
            try {
                surfaceTexture?.release()
            } catch (e: Exception) {
                Log.w(TAG, "   Warning: Error releasing surface texture: ${e.message}")
            }
            surfaceTexture = null

            // Unregister USB monitor BEFORE releasing texture
            // This ensures no new USB events are processed while we're cleaning up
            try {
                usbMonitor?.unregister()
                // Wait a bit for USB event handlers to finish
                Thread.sleep(200)
            } catch (e: Exception) {
                Log.w(TAG, "   Warning: Error unregistering USB monitor: ${e.message}")
            }
            usbMonitor = null

            // Release texture entry
            try {
                textureEntry?.release()
            } catch (e: Exception) {
                Log.w(TAG, "   Warning: Error releasing texture entry: ${e.message}")
            }
            textureEntry = null

            isInitialized = false
            usbDevice = null
            usbControlBlock = null

            Log.d(TAG, "✅ UVC camera controller disposed")
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error disposing UVC camera: ${e.message}", e)
        }
    }

}
