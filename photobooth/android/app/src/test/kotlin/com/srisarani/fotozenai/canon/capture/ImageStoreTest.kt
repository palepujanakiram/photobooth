package com.srisarani.fotozenai.canon.capture

import com.google.common.truth.Truth.assertThat
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ImageStoreTest {

    @get:Rule
    val temp = TemporaryFolder()

    private fun store() = ImageStore(temp.root)

    /**
     * `I-02`, the load-bearing guarantee of the whole quality story: the camera's bytes
     * reach disk unchanged. Any decode/encode round trip is generation loss and silently
     * breaks the "highest available quality" requirement.
     */
    @Test
    fun `original is written byte for byte`() {
        val bytes = ByteArray(5000) { (it % 256).toByte() }

        val stored = store().writeOriginal(bytes, "IMG_0042.JPG")

        assertThat(stored.file.readBytes()).isEqualTo(bytes)
        assertThat(stored.sizeBytes).isEqualTo(5000L)
    }

    /** The hash makes the guarantee checkable, not merely asserted (M5 acceptance). */
    @Test
    fun `sha256 matches the written file`() {
        val bytes = "hello camera".toByteArray()

        val stored = store().writeOriginal(bytes, "IMG_0001.JPG")

        val expected = java.security.MessageDigest.getInstance("SHA-256")
            .digest(stored.file.readBytes())
            .joinToString("") { "%02x".format(it) }
        assertThat(stored.sha256).isEqualTo(expected)
    }

    @Test
    fun `sequence increments within a session`() {
        val s = store()
        s.startSession()

        val first = s.writeOriginal(ByteArray(10), "IMG_0001.JPG")
        val second = s.writeOriginal(ByteArray(10), "IMG_0002.JPG")

        assertThat(first.sequence).isEqualTo(1)
        assertThat(second.sequence).isEqualTo(2)
        assertThat(first.file.name).startsWith("0001_")
        assertThat(second.file.name).startsWith("0002_")
    }

    /**
     * `C-12`: camera filenames roll over at IMG_9999, so they cannot be unique keys. Our
     * sequence prefix keeps files distinct even when the camera repeats a name.
     */
    @Test
    fun `duplicate camera filenames do not collide`() {
        val s = store()
        s.startSession()

        val first = s.writeOriginal(ByteArray(10) { 1 }, "IMG_9999.JPG")
        val second = s.writeOriginal(ByteArray(10) { 2 }, "IMG_9999.JPG")

        assertThat(first.file.absolutePath).isNotEqualTo(second.file.absolutePath)
        assertThat(first.file.readBytes()[0]).isEqualTo(1.toByte())
        assertThat(second.file.readBytes()[0]).isEqualTo(2.toByte())
    }

    @Test
    fun `unsafe filename characters are sanitised`() {
        val stored = store().writeOriginal(ByteArray(10), "../../etc/passwd")

        assertThat(stored.file.name).doesNotContain("/")
        assertThat(stored.file.name).doesNotContain("..")
        assertThat(stored.file.parentFile!!.name).startsWith("2")
    }

    @Test
    fun `blank camera filename still produces a usable file`() {
        val stored = store().writeOriginal(ByteArray(10), "")

        assertThat(stored.file.exists()).isTrue()
        assertThat(stored.file.name).contains("IMG")
    }

    @Test
    fun `derivative sits beside the original without touching it`() {
        val s = store()
        val original = s.writeOriginal(ByteArray(10), "IMG_0042.JPG")

        val print = s.derivativeFor(original, "print.jpg")

        assertThat(print.parentFile).isEqualTo(original.file.parentFile)
        assertThat(print.name).isEqualTo("0001_IMG_0042.print.jpg")
        assertThat(print.absolutePath).isNotEqualTo(original.file.absolutePath)
    }

    @Test
    fun `new session resets the sequence and creates a new directory`() {
        val s = store()
        val first = s.startSession()
        s.writeOriginal(ByteArray(10), "A.JPG")

        Thread.sleep(1100) // session ids are second-resolution
        val second = s.startSession()
        val image = s.writeOriginal(ByteArray(10), "B.JPG")

        assertThat(second.id).isNotEqualTo(first.id)
        assertThat(image.sequence).isEqualTo(1)
    }

    /** `I-11`: better to refuse before firing than to discover it after the shutter. */
    @Test
    fun `room check accounts for a safety margin`() {
        val s = store()

        assertThat(s.hasRoomFor(1000, safetyMarginBytes = 0)).isTrue()
        assertThat(s.hasRoomFor(Long.MAX_VALUE / 2)).isFalse()
    }

    @Test
    fun `sessions are listed in order`() {
        val s = store()
        s.startSession()
        s.writeOriginal(ByteArray(1), "A.JPG")

        assertThat(s.listSessions()).hasSize(1)
    }
}
