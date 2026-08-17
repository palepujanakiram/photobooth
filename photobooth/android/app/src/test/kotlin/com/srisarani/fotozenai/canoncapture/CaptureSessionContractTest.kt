package com.srisarani.fotozenai.canoncapture

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * The launch request and result payload.
 *
 * These cross an Activity boundary and then a method channel, so they have to survive a
 * round trip through JSON without quietly changing meaning.
 */
@RunWith(RobolectricTestRunner::class)
class CaptureSessionContractTest {

    @Test
    fun `a request survives a json round trip`() {
        val original = CaptureSessionContract.Request(
            shotCount = 4,
            displayMaxLongEdge = 1600,
            displayJpegQuality = 85,
            idleTimeoutSeconds = 90,
            titleText = "Get ready",
            shutterText = "Snap",
            cancelText = "Back",
        )
        val restored = CaptureSessionContract.Request.fromJson(original.toJson())
        assertThat(restored).isEqualTo(original)
    }

    @Test
    fun `absent copy stays null rather than becoming the string null`() {
        // JSONObject.optString returns the literal "null" for a JSON null, which would put
        // the word "null" on a guest-facing button.
        val restored = CaptureSessionContract.Request
            .fromJson(CaptureSessionContract.Request().toJson())
        assertThat(restored.titleText).isNull()
        assertThat(restored.shutterText).isNull()
        assertThat(restored.cancelText).isNull()
    }

    @Test
    fun `malformed request json falls back to defaults instead of throwing`() {
        // Launch arguments are not worth crashing a capture over.
        val restored = CaptureSessionContract.Request.fromJson("{not json")
        assertThat(restored).isEqualTo(CaptureSessionContract.Request())
    }

    @Test
    fun `request values are clamped to sane ranges`() {
        val restored = CaptureSessionContract.Request.fromJson(
            """{"shotCount":9999,"displayMaxLongEdge":5,"displayJpegQuality":900,
               "idleTimeoutSeconds":0}""",
        )
        assertThat(restored.shotCount).isAtMost(12)
        assertThat(restored.displayMaxLongEdge).isAtLeast(320)
        assertThat(restored.displayJpegQuality).isAtMost(100)
        assertThat(restored.idleTimeoutSeconds).isAtLeast(10)
    }

    @Test
    fun `fromMap reads method channel arguments`() {
        val request = CaptureSessionContract.Request.fromMap(
            mapOf(
                "shotCount" to 4,
                "displayMaxLongEdge" to 1920,
                "titleText" to "Pose",
            ),
        )
        assertThat(request.shotCount).isEqualTo(4)
        assertThat(request.displayMaxLongEdge).isEqualTo(1920)
        assertThat(request.titleText).isEqualTo("Pose")
    }

    @Test
    fun `fromMap tolerates a null argument map`() {
        assertThat(CaptureSessionContract.Request.fromMap(null))
            .isEqualTo(CaptureSessionContract.Request())
    }

    @Test
    fun `a completed result survives a json round trip with every shot`() {
        val result = CaptureSessionContract.Result(
            status = CaptureSessionContract.STATUS_COMPLETED,
            shots = listOf(
                CaptureSessionContract.Shot(
                    originalPath = "/data/0001_IMG_3001.JPG",
                    displayPath = "/data/0001_IMG_3001.display.jpg",
                    widthPx = 6000,
                    heightPx = 4000,
                    bytes = 6_542_638,
                    capturedAtMs = 1_755_400_000_000,
                ),
                CaptureSessionContract.Shot(
                    originalPath = "/data/0002_IMG_3002.JPG",
                    displayPath = null,
                    widthPx = 6000,
                    heightPx = 4000,
                    bytes = 6_100_000,
                    capturedAtMs = 1_755_400_010_000,
                ),
            ),
        )

        val restored = CaptureSessionContract.Result
            .fromIntent(result.toIntent())

        assertThat(restored.status).isEqualTo(CaptureSessionContract.STATUS_COMPLETED)
        assertThat(restored.shots).hasSize(2)
        assertThat(restored.shots[0].originalPath).isEqualTo("/data/0001_IMG_3001.JPG")
        assertThat(restored.shots[0].bytes).isEqualTo(6_542_638)
        // A failed derivative must come back as a real null, not the string "null".
        assertThat(restored.shots[1].displayPath).isNull()
    }

    @Test
    fun `a missing intent reads as cancelled, never as an empty success`() {
        // A caller handed "completed with zero shots" cannot tell a user who backed out
        // from a result that got lost on the way home.
        val restored = CaptureSessionContract.Result.fromIntent(null)
        assertThat(restored.status).isEqualTo(CaptureSessionContract.STATUS_CANCELLED)
    }

    @Test
    fun `an error result keeps its code through the round trip`() {
        val restored = CaptureSessionContract.Result.fromIntent(
            CaptureSessionContract.Result
                .error(CaptureSessionContract.ERROR_CARD_UNAVAILABLE, "No card")
                .toIntent(),
        )
        assertThat(restored.status).isEqualTo(CaptureSessionContract.STATUS_ERROR)
        assertThat(restored.errorCode)
            .isEqualTo(CaptureSessionContract.ERROR_CARD_UNAVAILABLE)
    }

    @Test
    fun `toMap mirrors the json shape for the method channel`() {
        val map = CaptureSessionContract.Result(
            status = CaptureSessionContract.STATUS_COMPLETED,
            shots = listOf(
                CaptureSessionContract.Shot(
                    originalPath = "/o.JPG",
                    displayPath = "/o.display.jpg",
                    widthPx = 6000,
                    heightPx = 4000,
                    bytes = 1,
                    capturedAtMs = 2,
                ),
            ),
        ).toMap()

        assertThat(map["status"]).isEqualTo(CaptureSessionContract.STATUS_COMPLETED)
        @Suppress("UNCHECKED_CAST")
        val shots = map["shots"] as List<Map<String, Any?>>
        assertThat(shots).hasSize(1)
        assertThat(shots[0]["originalPath"]).isEqualTo("/o.JPG")
        assertThat(shots[0]["widthPx"]).isEqualTo(6000)
    }
}
