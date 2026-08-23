package com.srisarani.fotozenai.canoncapture

import android.view.View
import android.widget.Button

internal class CanonTopBarViews(
    val reconnect: View?,
    val selectCamera: View?,
    val rotate: View?,
)

internal class CanonTopBarActions(
    val isCapturing: () -> Boolean,
    val onReconnect: () -> Unit,
    val disabledAlpha: Float,
)

internal class CanonUploadViews(
    val gallery: Button,
    val phoneQr: Button,
)

internal class CanonUploadActions(
    val allowGallery: () -> Boolean,
    val allowPhone: () -> Boolean,
    val beforeFirstShot: () -> Boolean,
    val finishWith: (CaptureSessionContract.Result) -> Unit,
)

/**
 * Capture-screen chrome: top-bar actions and pre-first-shot upload buttons.
 *
 * Extracted from [CanonCaptureActivity] so the Activity stays under Qlty's file-complexity
 * budget. Visibility and disable rules match the previous inline methods.
 */
internal object CanonCaptureChrome {
    /**
     * Wires the top-bar actions that mirror the Flutter capture AppBar.
     *
     * All three are looked up as nullable: the diagnostic layout deliberately has no chrome,
     * and a hard `findViewById` would crash it rather than simply showing nothing.
     *
     * Only *reconnect* has real work to do. On the Flutter screen "select camera" and
     * "rotate" drive CameraX — choosing between a front/back/UVC device, and re-orienting a
     * preview whose sensor rotation the plugin reports. Neither exists here: there is one
     * tethered body, and its live-view frames arrive already upright. They are kept so the
     * two screens look identical, and disabled so they cannot promise something that will
     * not happen. See [LiveViewSurfaceRenderer] if rotation ever becomes real.
     */
    fun bindTopBar(
        views: CanonTopBarViews,
        actions: CanonTopBarActions,
    ) {
        views.reconnect?.setOnClickListener {
            if (actions.isCapturing()) return@setOnClickListener
            actions.onReconnect()
        }
        views.selectCamera?.apply {
            isEnabled = false
            alpha = actions.disabledAlpha
        }
        views.rotate?.apply {
            isEnabled = false
            alpha = actions.disabledAlpha
        }
    }

    /**
     * Offers Gallery / Phone QR when the kiosk allows them, and hands the choice to Dart.
     *
     * Neither upload happens here. Phone QR needs `/api/kiosk/upload-links` and a poll loop,
     * and Gallery is a single `viewModel.selectFromGallery()` on the Dart side — both already
     * exist for the Flutter capture screen. Duplicating them natively would mean two
     * implementations free to drift, so the Activity ends the session with
     * [CaptureSessionContract.STATUS_UPLOAD_REQUESTED] and lets Dart run the code it has.
     *
     * Cost of that choice: leaving the Activity tears down live view, so returning from a
     * cancelled sheet reconnects the camera — a visible blink the Flutter screen does not
     * have. Accepted deliberately; keeping the Activity alive behind a Dart overlay is much
     * more machinery for a transition most guests will not see twice.
     *
     * Visibility is [refreshUploads]' job — they stay up through the first countdown
     * and go once a shot actually lands.
     */
    fun bindUploads(
        views: CanonUploadViews,
        actions: CanonUploadActions,
    ) {
        refreshUploads(views, actions)
        views.gallery.setOnClickListener {
            actions.finishWith(
                CaptureSessionContract.Result.uploadRequested(
                    CaptureSessionContract.UPLOAD_SOURCE_GALLERY,
                ),
            )
        }
        views.phoneQr.setOnClickListener {
            actions.finishWith(
                CaptureSessionContract.Result.uploadRequested(
                    CaptureSessionContract.UPLOAD_SOURCE_PHONE,
                ),
            )
        }
    }

    /**
     * Uploads are offered only until the first shot lands.
     *
     * Mirrors `capturePhotoUploadActionsAllowed`, whose gate is
     * `classicFourShotInProgress = isClassicFourShot && _stripShots.isNotEmpty` — so they
     * *are* offered on a 4-shot strip, but only before shot 1, because "a gallery pick
     * cannot break strip indexing / remount" once the set has started.
     *
     * Keyed on `shots` rather than on the sequence having started, so they stay up through
     * the first countdown exactly as they do on the Flutter screen, and come back if a
     * retake empties the strip again.
     */
    fun refreshUploads(
        views: CanonUploadViews,
        actions: CanonUploadActions,
    ) {
        val beforeFirstShot = actions.beforeFirstShot()
        views.gallery.visibility = uploadVisibility(actions.allowGallery(), beforeFirstShot)
        views.phoneQr.visibility = uploadVisibility(actions.allowPhone(), beforeFirstShot)
    }

    fun uploadVisibility(
        allowed: Boolean,
        beforeFirstShot: Boolean,
    ): Int = if (allowed && beforeFirstShot) View.VISIBLE else View.GONE
}
