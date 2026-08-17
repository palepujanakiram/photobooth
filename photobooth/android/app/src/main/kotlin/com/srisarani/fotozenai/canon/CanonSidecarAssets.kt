package com.srisarani.fotozenai.canon

import android.content.Context
import android.util.Log
import java.io.File

/** Extracts glibc deps and JNI sidecar binaries into an exec-able filesDir. */
internal object CanonSidecarAssets {
    private const val TAG = "CanonSidecar"
    const val ASSET_DIR = "canon_sidecar"
    const val HOOK_ASSET_VER = "3"

    fun sidecarDir(filesDir: File): File = File(filesDir, ASSET_DIR)

    fun extractGlibcDeps(
        context: Context,
        abi: String,
        destDir: File,
    ) {
        if (cacheIsCurrent(destDir, abi)) {
            Log.d(TAG, "Glibc assets already extracted for $abi at $destDir")
            return
        }
        Log.i(TAG, "Extracting glibc assets for $abi to $destDir")
        destDir.deleteRecursively()
        destDir.mkdirs()
        val assetPath = "$ASSET_DIR/$abi"
        val assetFiles = context.assets.list(assetPath) ?: emptyArray()
        if (assetFiles.isEmpty()) {
            Log.e(TAG, "No sidecar glibc assets at $assetPath")
            return
        }
        for (name in assetFiles) {
            val dest = File(destDir, name)
            context.assets.open("$assetPath/$name").use { src ->
                dest.outputStream().use { out -> src.copyTo(out) }
            }
        }
        File(destDir, ".abi").writeText(abi)
        File(destDir, ".hookver").writeText(HOOK_ASSET_VER)
        Log.i(TAG, "Extracted ${assetFiles.size} glibc dependency files for $abi")
    }

    fun stageExecutables(
        nativeDir: File,
        destDir: File,
        abi: String,
    ) {
        destDir.mkdirs()
        val copies =
            listOf(
                File(nativeDir, CanonSidecarAbi.interpreterSoName(abi)) to
                    File(destDir, CanonSidecarAbi.interpreterRuntimeName(abi)),
                File(nativeDir, CanonSidecarAbi.BINARY_SO) to
                    File(destDir, CanonSidecarAbi.BINARY_RUNTIME),
                File(nativeDir, CanonSidecarAbi.EDSDK_SO) to
                    File(destDir, CanonSidecarAbi.EDSDK_SO),
            )
        for ((src, dest) in copies) {
            if (!src.exists()) {
                Log.e(TAG, "Missing JNI lib ${src.name} in ${nativeDir.absolutePath}")
                continue
            }
            src.copyTo(dest, overwrite = true)
            dest.setReadable(true, false)
            dest.setExecutable(true, false)
        }
        makeRuntimeExecutable(destDir)
    }

    /** Android 10+ will not mmap a 0600 file as PROT_EXEC — glibc .so files need +x. */
    fun makeRuntimeExecutable(dir: File) {
        dir.listFiles()?.forEach { file ->
            if (file.isFile) {
                file.setReadable(true, false)
                file.setExecutable(true, false)
            }
        }
    }

    private fun cacheIsCurrent(
        destDir: File,
        abi: String,
    ): Boolean {
        val marker = File(destDir, ".abi")
        val hookVer = File(destDir, ".hookver")
        if (!marker.exists() || marker.readText().trim() != abi) return false
        if (!hookVer.exists() || hookVer.readText().trim() != HOOK_ASSET_VER) return false
        return nonEmpty(destDir, "libc.so.6") &&
            nonEmpty(destDir, "libudev.so.1") &&
            nonEmpty(destDir, CanonSidecarAbi.USB_HOOK_SO)
    }

    private fun nonEmpty(
        dir: File,
        name: String,
    ): Boolean {
        val file = File(dir, name)
        return file.exists() && file.length() > 0
    }
}
