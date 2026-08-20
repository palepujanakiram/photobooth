package com.srisarani.fotozenai.canoncapture

import android.content.Intent
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the native capture screen is asked for, and what it hands back.
 *
 * JSON in a single Intent extra rather than a spread of typed extras: the result crosses
 * an Activity boundary and then a method channel, and one payload that survives both
 * unchanged is easier to keep honest than two parallel marshalling paths.
 *
 * **Only paths cross this boundary — never image bytes.** See [DisplayDerivative].
 */
object CaptureSessionContract {

    const val EXTRA_REQUEST = "canon_capture_request"
    const val EXTRA_RESULT = "canon_capture_result"

    /** Terminal outcomes. Dart switches on these. */
    const val STATUS_COMPLETED = "completed"
    const val STATUS_CANCELLED = "cancelled"
    const val STATUS_ERROR = "error"

    /**
     * The guest chose Gallery or Phone QR instead of the shutter.
     *
     * Not an error and not a cancel: the session ends with no shots, but the guest is still
     * mid-flow and Dart should hand them the upload they asked for.
     *
     * The native screen deliberately does **not** implement either upload. Phone QR calls
     * `/api/kiosk/upload-links` and polls for the result, which lives in `ApiService`, and
     * Gallery is one `viewModel.selectFromGallery()` away on the Dart side. Reimplementing
     * them in Kotlin would duplicate backend and polling logic that already exists and would
     * be free to drift from the Flutter capture screen. So the Activity reports the intent
     * and gets out of the way — see [UPLOAD_SOURCE_GALLERY] / [UPLOAD_SOURCE_PHONE].
     */
    const val STATUS_UPLOAD_REQUESTED = "upload_requested"

    const val UPLOAD_SOURCE_GALLERY = "gallery"
    const val UPLOAD_SOURCE_PHONE = "phone"

    // Error codes, kept distinct so each maps to a different operator action.
    const val ERROR_NO_DEVICE = "no_device"
    const val ERROR_PERMISSION_DENIED = "permission_denied"
    const val ERROR_CONNECT_FAILED = "connect_failed"
    const val ERROR_CAPTURE_FAILED = "capture_failed"
    const val ERROR_DOWNLOAD_FAILED = "download_failed"
    const val ERROR_CAMERA_BUSY = "camera_busy"

    /**
     * A card is now a hard requirement because capture destination is BOTH — the body
     * writes to the card and streams to the host. Its own code because "put a card in the
     * camera" is a ten-second operator fix that must not be buried inside a generic
     * capture failure.
     */
    const val ERROR_CARD_UNAVAILABLE = "card_unavailable"

    data class Request(
        /** Shots to take. 1 for AI, 4 for a Classic strip. */
        val shotCount: Int = 1,
        /**
         * Seconds a guest gets to pose before each shot.
         *
         * Passed in rather than hardcoded so `AppConstants` stays the single source of
         * truth — the booth currently uses 10s for Classic poses.
         */
        val countdownSeconds: Int = 10,
        /**
         * Seconds between shots in a strip, for guests to rearrange.
         *
         * `AppConstants.kFlashbackBetweenShotRearrangeDuration` — 8s today.
         */
        val betweenShotSeconds: Int = 8,
        /** Long edge of the display derivative handed back to Dart. */
        val displayMaxLongEdge: Int = DisplayDerivative.DEFAULT_MAX_LONG_EDGE,
        val displayJpegQuality: Int = DisplayDerivative.DEFAULT_JPEG_QUALITY,
        /** Abandons the session so a walk-away cannot strand the booth. */
        val idleTimeoutSeconds: Int = 180,
        /**
         * Start the countdown as soon as the camera is ready, with no button press.
         *
         * True for a fresh pose: a guest walking up to the booth should not have to find and
         * press anything.
         *
         * Dart passes **false on a retake**. Coming back from the look picker put the guest
         * straight into a countdown they did not ask for and had no warning of — they had
         * pressed "back" to change something, not to be photographed again. There the
         * shutter button is the trigger, and pressing it starts the countdown.
         */
        val autoStart: Boolean = true,
        /**
         * How long the just-taken still is shown, with Retake and the primary action, before
         * the session moves on by itself. **0 waits indefinitely for a tap.**
         *
         * Dart owns this because only Dart knows the flow, and the three cases genuinely
         * differ (see `flashbackShotReviewHoldDuration` / `shouldScheduleFlashbackAutoAccept`):
         *
         * - FotoZen single shot — **0**. Flutter never auto-accepts here; the guest reviews
         *   for as long as they like and taps Continue or Retake.
         * - Classic strip, mid-strip — 8000ms, the rearrange window.
         * - Classic single 6×4 — 600ms, effectively a flash of the still.
         */
        val reviewHoldMs: Int = 0,
        /** Review hold for the **final** shot of a strip; Flutter uses 2s. */
        val finalReviewHoldMs: Int = 0,
        /**
         * Whether to offer Gallery / Phone QR alongside the shutter.
         *
         * Both are gated on `settings.photoUploadAllowed` on the Flutter capture screen, so
         * they are passed in rather than assumed: a booth with uploads switched off must not
         * grow the buttons just because it moved to the native screen.
         */
        val allowGalleryUpload: Boolean = false,
        val allowPhoneUpload: Boolean = false,
        /**
         * Show the "Be ready for photo" headline over the countdown.
         *
         * FotoZen only, mirroring `showAiIntro` in _buildCountdownOverlay. Passed rather
         * than inferred from shotCount: a Classic 1-shot also has shotCount == 1, so
         * inferring showed it a headline Flutter deliberately withholds.
         */
        val showCountdownHeadline: Boolean = false,
        /** Copy is passed in so AppStrings stays the single source of truth. */
        val titleText: String? = null,
        val subtitleText: String? = null,
        val shutterText: String? = null,
        val cancelText: String? = null,
    ) {
        fun toJson(): String = JSONObject().apply {
            put("shotCount", shotCount)
            put("countdownSeconds", countdownSeconds)
            put("betweenShotSeconds", betweenShotSeconds)
            put("displayMaxLongEdge", displayMaxLongEdge)
            put("displayJpegQuality", displayJpegQuality)
            put("idleTimeoutSeconds", idleTimeoutSeconds)
            put("autoStart", autoStart)
            put("reviewHoldMs", reviewHoldMs)
            put("finalReviewHoldMs", finalReviewHoldMs)
            put("allowGalleryUpload", allowGalleryUpload)
            put("allowPhoneUpload", allowPhoneUpload)
            put("showCountdownHeadline", showCountdownHeadline)
            put("titleText", titleText ?: JSONObject.NULL)
            put("subtitleText", subtitleText ?: JSONObject.NULL)
            put("shutterText", shutterText ?: JSONObject.NULL)
            put("cancelText", cancelText ?: JSONObject.NULL)
        }.toString()

        companion object {
            fun fromJson(raw: String?): Request {
                if (raw.isNullOrBlank()) return Request()
                return runCatching {
                    val json = JSONObject(raw)
                    Request(
                        shotCount = json.optInt("shotCount", 1).coerceIn(1, 12),
                        countdownSeconds = json.optInt("countdownSeconds", 10).coerceIn(0, 60),
                        betweenShotSeconds = json.optInt("betweenShotSeconds", 8)
                            .coerceIn(0, 60),
                        displayMaxLongEdge = json
                            .optInt("displayMaxLongEdge", DisplayDerivative.DEFAULT_MAX_LONG_EDGE)
                            .coerceIn(320, 8000),
                        displayJpegQuality = json
                            .optInt("displayJpegQuality", DisplayDerivative.DEFAULT_JPEG_QUALITY)
                            .coerceIn(1, 100),
                        idleTimeoutSeconds = json
                            .optInt("idleTimeoutSeconds", 180)
                            .coerceIn(10, 3600),
                        autoStart = json.optBoolean("autoStart", true),
                        reviewHoldMs = json.optInt("reviewHoldMs", 0),
                        finalReviewHoldMs = json.optInt("finalReviewHoldMs", 0),
                        allowGalleryUpload = json.optBoolean("allowGalleryUpload", false),
                        allowPhoneUpload = json.optBoolean("allowPhoneUpload", false),
                        showCountdownHeadline =
                            json.optBoolean("showCountdownHeadline", false),
                        titleText = json.optNullableString("titleText"),
                        subtitleText = json.optNullableString("subtitleText"),
                        shutterText = json.optNullableString("shutterText"),
                        cancelText = json.optNullableString("cancelText"),
                    )
                }.getOrDefault(Request())
            }

            fun fromMap(args: Map<*, *>?): Request {
                if (args == null) return Request()
                val defaults = Request()
                return Request(
                    shotCount = (args["shotCount"] as? Int ?: defaults.shotCount)
                        .coerceIn(1, 12),
                    countdownSeconds = (
                        args["countdownSeconds"] as? Int ?: defaults.countdownSeconds
                        ).coerceIn(0, 60),
                    betweenShotSeconds = (
                        args["betweenShotSeconds"] as? Int ?: defaults.betweenShotSeconds
                        ).coerceIn(0, 60),
                    displayMaxLongEdge = (
                        args["displayMaxLongEdge"] as? Int ?: defaults.displayMaxLongEdge
                        ).coerceIn(320, 8000),
                    displayJpegQuality = (
                        args["displayJpegQuality"] as? Int ?: defaults.displayJpegQuality
                        ).coerceIn(1, 100),
                    idleTimeoutSeconds = (
                        args["idleTimeoutSeconds"] as? Int ?: defaults.idleTimeoutSeconds
                        ).coerceIn(10, 3600),
                    autoStart = args["autoStart"] as? Boolean ?: defaults.autoStart,
                    reviewHoldMs = (
                        args["reviewHoldMs"] as? Int ?: defaults.reviewHoldMs
                        ).coerceIn(0, 120_000),
                    finalReviewHoldMs = (
                        args["finalReviewHoldMs"] as? Int ?: defaults.finalReviewHoldMs
                        ).coerceIn(0, 120_000),
                    allowGalleryUpload = args["allowGalleryUpload"] as? Boolean
                        ?: defaults.allowGalleryUpload,
                    showCountdownHeadline = args["showCountdownHeadline"] as? Boolean
                        ?: defaults.showCountdownHeadline,
                    allowPhoneUpload = args["allowPhoneUpload"] as? Boolean
                        ?: defaults.allowPhoneUpload,
                    titleText = args["titleText"] as? String,
                    subtitleText = args["subtitleText"] as? String,
                    shutterText = args["shutterText"] as? String,
                    cancelText = args["cancelText"] as? String,
                )
            }
        }
    }

    data class Shot(
        /** Untouched camera JPEG. This is what gets printed. */
        val originalPath: String,
        /** Downscaled copy for review and upload; null if the derivative failed. */
        val displayPath: String?,
        val widthPx: Int,
        val heightPx: Int,
        val bytes: Long,
        val capturedAtMs: Long,
    ) {
        fun toJson(): JSONObject = JSONObject().apply {
            put("originalPath", originalPath)
            put("displayPath", displayPath ?: JSONObject.NULL)
            put("widthPx", widthPx)
            put("heightPx", heightPx)
            put("bytes", bytes)
            put("capturedAtMs", capturedAtMs)
        }
    }

    data class Result(
        val status: String,
        val shots: List<Shot> = emptyList(),
        val errorCode: String? = null,
        val errorMessage: String? = null,
        /** Which upload the guest asked for; only set with [STATUS_UPLOAD_REQUESTED]. */
        val uploadSource: String? = null,
    ) {
        fun toJson(): String = JSONObject().apply {
            put("status", status)
            put("shots", JSONArray().also { array -> shots.forEach { array.put(it.toJson()) } })
            put("errorCode", errorCode ?: JSONObject.NULL)
            put("errorMessage", errorMessage ?: JSONObject.NULL)
            put("uploadSource", uploadSource ?: JSONObject.NULL)
        }.toString()

        fun toIntent(): Intent = Intent().putExtra(EXTRA_RESULT, toJson())

        /** Flat map for the method channel. Mirrors [toJson]. */
        fun toMap(): Map<String, Any?> = mapOf(
            "status" to status,
            "shots" to shots.map {
                mapOf(
                    "originalPath" to it.originalPath,
                    "displayPath" to it.displayPath,
                    "widthPx" to it.widthPx,
                    "heightPx" to it.heightPx,
                    "bytes" to it.bytes,
                    "capturedAtMs" to it.capturedAtMs,
                )
            },
            "errorCode" to errorCode,
            "errorMessage" to errorMessage,
            "uploadSource" to uploadSource,
        )

        companion object {
            fun cancelled(reason: String) =
                Result(STATUS_CANCELLED, errorMessage = reason)

            fun uploadRequested(source: String) =
                Result(STATUS_UPLOAD_REQUESTED, uploadSource = source)

            fun error(code: String, message: String) =
                Result(STATUS_ERROR, errorCode = code, errorMessage = message)

            /**
             * Reads a result back off an Intent.
             *
             * A missing or unparseable payload is reported as cancelled, not as success
             * with zero shots: a caller that gets `completed` with an empty list has no way
             * to tell "the user backed out" from "something ate the result".
             */
            fun fromIntent(intent: Intent?): Result {
                val raw = intent?.getStringExtra(EXTRA_RESULT)
                    ?: return cancelled("No result returned from capture screen")
                return runCatching {
                    val json = JSONObject(raw)
                    val array = json.optJSONArray("shots") ?: JSONArray()
                    val shots = (0 until array.length()).map { i ->
                        val s = array.getJSONObject(i)
                        Shot(
                            originalPath = s.getString("originalPath"),
                            displayPath = s.optNullableString("displayPath"),
                            widthPx = s.optInt("widthPx"),
                            heightPx = s.optInt("heightPx"),
                            bytes = s.optLong("bytes"),
                            capturedAtMs = s.optLong("capturedAtMs"),
                        )
                    }
                    Result(
                        status = json.optString("status", STATUS_CANCELLED),
                        shots = shots,
                        errorCode = json.optNullableString("errorCode"),
                        errorMessage = json.optNullableString("errorMessage"),
                        uploadSource = json.optNullableString("uploadSource"),
                    )
                }.getOrElse { cancelled("Malformed capture result: ${it.message}") }
            }
        }
    }
}

/** `optString` returns the literal "null" for JSON nulls; this returns a real null. */
private fun JSONObject.optNullableString(key: String): String? =
    if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
