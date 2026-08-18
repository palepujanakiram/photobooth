package com.srisarani.fotozenai.canon.capture

import com.srisarani.fotozenai.canon.CanonLog
import java.io.File
import java.security.MessageDigest
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

/**
 * On-disk layout for captured images.
 *
 * ## The one rule
 *
 * **The camera's bytes go to disk verbatim.** No decode, no re-encode, no metadata
 * rewriting on the original (plan §2, `I-02`). Every derived image - the print crop, the
 * API result - is a separate file. A decode/encode round trip is generation loss, and it
 * silently violates the "highest available quality" requirement that the whole format
 * decision was built around.
 *
 * ## Layout
 *
 * ```
 * <files>/captures/<sessionId>/
 *   0001_IMG_0042.JPG          original, byte-identical to the camera
 *   0001_IMG_0042.print.jpg    derived crop for print (M5)
 *   0001_IMG_0042.result.jpg   transformed image from the API (M8)
 * ```
 *
 * Camera filenames are **not** used as unique keys: they roll over at IMG_9999 (`C-12`).
 * The sequence prefix is ours and is monotonic within a session.
 */
class ImageStore(private val rootDir: File) {

    /** A capture session groups the images from one sitting. */
    data class Session(val id: String, val directory: File)

    @Volatile
    private var currentSession: Session? = null
    private var sequence = 0

    fun startSession(): Session {
        val id = SESSION_FORMAT.format(Date())
        val dir = File(rootDir, "captures/$id")
        dir.mkdirs()
        sequence = 0
        val session = Session(id, dir)
        currentSession = session
        CanonLog.i("Capture session %s at %s", id, dir.absolutePath)
        return session
    }

    fun currentOrStartSession(): Session = currentSession ?: startSession()

    /**
     * Writes the original exactly as received.
     *
     * @param cameraFilename used only for a human-readable suffix, never as a key.
     */
    fun writeOriginal(bytes: ByteArray, cameraFilename: String): StoredImage {
        val session = currentOrStartSession()
        val seq = ++sequence
        val safeName = sanitiseFilename(cameraFilename)
        val file = File(session.directory, "%04d_%s".format(seq, safeName))

        file.writeBytes(bytes)

        val stored = StoredImage(
            file = file,
            sessionId = session.id,
            sequence = seq,
            cameraFilename = cameraFilename,
            sizeBytes = bytes.size.toLong(),
            sha256 = sha256(bytes),
        )
        CanonLog.i("Stored %s (%,d bytes, sha256=%s)", file.name, bytes.size, stored.sha256.take(16))
        return stored
    }

    /** Path for a derivative alongside its original. Never overwrites the original. */
    fun derivativeFor(original: StoredImage, suffix: String): File {
        val base = original.file.name.substringBeforeLast('.')
        return File(original.file.parentFile, "$base.$suffix")
    }

    /** Where captures land. Logged at startup so a misconfigured root is visible (`I-11`). */
    fun rootPath(): String = "${rootDir.absolutePath} (free ${freeSpaceBytes() / 1_048_576}MB)"

    fun freeSpaceBytes(): Long = rootDir.usableSpace

    /**
     * `I-11`: a capture that fails because the disk filled is avoidable. Checked before
     * firing rather than discovered afterwards.
     */
    fun hasRoomFor(bytes: Long, safetyMarginBytes: Long = 200L * 1024 * 1024): Boolean =
        freeSpaceBytes() > bytes + safetyMarginBytes

    fun listSessions(): List<File> =
        File(rootDir, "captures").listFiles()?.filter { it.isDirectory }?.sortedBy { it.name } ?: emptyList()

    /**
     * Reduces a camera-supplied filename to a safe suffix.
     *
     * The filename comes off the wire, so it is untrusted input even though a Canon body
     * is unlikely to be hostile. Replacing path separators alone is not enough - it leaves
     * `..` sequences intact - so consecutive dots are collapsed too. The result is only
     * ever a *suffix* on our own sequence prefix, never the whole name.
     */
    private fun sanitiseFilename(raw: String): String =
        raw.replace(Regex("[^A-Za-z0-9._-]"), "_")
            .replace(Regex("\\.{2,}"), "_") // no "..", so no traversal even if misused
            .trim('.', '_')
            .take(MAX_FILENAME_LENGTH)
            .ifBlank { "IMG.JPG" }

    private fun sha256(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private companion object {
        val SESSION_FORMAT = SimpleDateFormat("yyyyMMdd-HHmmss", Locale.US)

        /** Long enough for any real camera filename, short enough to stay path-safe. */
        const val MAX_FILENAME_LENGTH = 64
    }
}

/**
 * A captured original on disk.
 *
 * [sha256] exists so the "never re-encoded" guarantee is checkable rather than merely
 * asserted - M5's acceptance criterion compares it against the file pulled independently
 * off the camera's card.
 */
data class StoredImage(
    val file: File,
    val sessionId: String,
    val sequence: Int,
    val cameraFilename: String,
    val sizeBytes: Long,
    val sha256: String,
)
