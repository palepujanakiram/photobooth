package com.example.photobooth

import android.content.Context
import android.util.Log
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.widget.FrameLayout
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

private const val TAG = "CameraPreviewSurfaceView"

/**
 * View that wraps a SurfaceView for camera preview.
 * When the surface is ready, calls the callback so the camera controller can use it.
 * Rotation is applied via View.setRotation() for reliable orientation on Android TV.
 */
class CameraPreviewSurfaceView(
    context: Context,
    private val rotationDegrees: Int,
    private val onSurfaceReady: (surface: android.view.Surface, rotationDegrees: Int) -> Unit,
) : FrameLayout(context) {

    private val surfaceView: SurfaceView = SurfaceView(context).apply {
        layoutParams = LayoutParams(LayoutParams.MATCH_PARENT, LayoutParams.MATCH_PARENT)
    }

    @Volatile
    private var surfaceReadyNotified = false

    init {
        addView(surfaceView)
        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                // Don't notify here: surface may have 0x0 size; Camera2 createCaptureSession fails with zero-sized surface.
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
                if (surfaceReadyNotified) return
                if (width <= 0 || height <= 0) return
                val surface = holder.surface
                if (surface != null && surface.isValid) {
                    surfaceReadyNotified = true
                    Log.d(TAG, "Surface ready, rotation=$rotationDegrees, size=${width}x${height}")
                    setRotation(rotationDegrees.toFloat())
                    onSurfaceReady(surface, rotationDegrees)
                }
            }

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                Log.d(TAG, "Surface destroyed")
                surfaceReadyNotified = false
            }
        })
    }
}

/**
 * PlatformView that holds CameraPreviewSurfaceView for embedding in Flutter.
 */
class CameraPreviewPlatformView(
    private val context: Context,
    private val viewId: Int,
    private val creationParams: Map<String, Any>?,
    private val onSurfaceReady: (surface: android.view.Surface) -> Unit,
) : PlatformView {

    private val rootView = CameraPreviewSurfaceView(
        context = context,
        rotationDegrees = (creationParams?.get("rotation") as? Number)?.toInt() ?: 90,
        onSurfaceReady = { surface, _ -> onSurfaceReady(surface) },
    )

    override fun getView(): android.view.View = rootView

    override fun dispose() {}
}

/**
 * Factory for creating the camera preview SurfaceView platform view.
 */
class CameraPreviewSurfaceViewFactory(
    private val onSurfaceReady: (surface: android.view.Surface) -> Unit,
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {

    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        @Suppress("UNCHECKED_CAST")
        val params = args as? Map<String, Any>
        return CameraPreviewPlatformView(context, viewId, params, onSurfaceReady)
    }
}
