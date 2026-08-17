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
        /** Long edge of the display derivative handed back to Dart. */
        val displayMaxLongEdge: Int = DisplayDerivative.DEFAULT_MAX_LONG_EDGE,
        val displayJpegQuality: Int = DisplayDerivative.DEFAULT_JPEG_QUALITY,
        /** Abandons the session so a walk-away cannot strand the booth. */
        val idleTimeoutSeconds: Int = 180,
        /** Copy is passed in so AppStrings stays the single source of truth. */
        val titleText: String? = null,
        val shutterText: String? = null,
        val cancelText: String? = null,
    ) {
        fun toJson(): String = JSONObject().apply {
            put("shotCount", shotCount)
            put("displayMaxLongEdge", displayMaxLongEdge)
            put("displayJpegQuality", displayJpegQuality)
            put("idleTimeoutSeconds", idleTimeoutSeconds)
            put("titleText", titleText ?: JSONObject.NULL)
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
                        displayMaxLongEdge = json
                            .optInt("displayMaxLongEdge", DisplayDerivative.DEFAULT_MAX_LONG_EDGE)
                            .coerceIn(320, 8000),
                        displayJpegQuality = json
                            .optInt("displayJpegQuality", DisplayDerivative.DEFAULT_JPEG_QUALITY)
                            .coerceIn(1, 100),
                        idleTimeoutSeconds = json
                            .optInt("idleTimeoutSeconds", 180)
                            .coerceIn(10, 3600),
                        titleText = json.optNullableString("titleText"),
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
                    displayMaxLongEdge = (
                        args["displayMaxLongEdge"] as? Int ?: defaults.displayMaxLongEdge
                        ).coerceIn(320, 8000),
                    displayJpegQuality = (
                        args["displayJpegQuality"] as? Int ?: defaults.displayJpegQuality
                        ).coerceIn(1, 100),
                    idleTimeoutSeconds = (
                        args["idleTimeoutSeconds"] as? Int ?: defaults.idleTimeoutSeconds
                        ).coerceIn(10, 3600),
                    titleText = args["titleText"] as? String,
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
    ) {
        fun toJson(): String = JSONObject().apply {
            put("status", status)
            put("shots", JSONArray().also { array -> shots.forEach { array.put(it.toJson()) } })
            put("errorCode", errorCode ?: JSONObject.NULL)
            put("errorMessage", errorMessage ?: JSONObject.NULL)
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
        )

        companion object {
            fun cancelled(reason: String) =
                Result(STATUS_CANCELLED, errorMessage = reason)

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
                    )
                }.getOrElse { cancelled("Malformed capture result: ${it.message}") }
            }
        }
    }
}

/** `optString` returns the literal "null" for JSON nulls; this returns a real null. */
private fun JSONObject.optNullableString(key: String): String? =
    if (isNull(key)) null else optString(key).takeIf { it.isNotEmpty() }
