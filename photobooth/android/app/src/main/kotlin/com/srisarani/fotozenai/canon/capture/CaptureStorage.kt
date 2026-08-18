package com.srisarani.fotozenai.canon.capture

import android.content.Context
import android.os.Build
import android.os.Environment
import com.srisarani.fotozenai.canon.CanonLog
import java.io.File

/**
 * Chooses where captures are written.
 *
 * ## Why this is not just `getExternalFilesDir()`
 *
 * App-scoped storage (`Android/data/<pkg>/files`) needs no permission and is where we
 * started, but it has two properties that are wrong for a booth:
 *
 * 1. **Nothing else can read it.** Since Android 11, `Android/data/` is invisible to every
 *    third-party file manager and to MediaStore, so no gallery app will ever show the
 *    photos. Verified on the target box (Android 11): the only way to see a capture was adb.
 * 2. **It is deleted when the app is uninstalled.** For photos that cannot be reshot, tying
 *    their lifetime to an app install is a poor trade.
 *
 * So we prefer a public directory and fall back to app-scoped when we cannot have one.
 * Falling back rather than failing matters: a booth that refuses to capture because a
 * storage permission is missing is worse than one that captures somewhere less convenient.
 *
 * ## The permission
 *
 * Writing plain files to a public directory on Android 11+ requires `MANAGE_EXTERNAL_STORAGE`
 * ("All files access"), granted once from system Settings. That is a heavy permission for a
 * Play Store app and a reasonable one for a sideloaded kiosk — which is what this is. The
 * alternative, MediaStore inserts, would give us content URIs instead of files and break
 * `BitmapRegionDecoder`, byte-identical writes, and the print path's `File` inputs.
 */
object CaptureStorage {

    /**
     * Public folder name. Sits at the top level so it is easy to find on a TV box.
     *
     * Renamed from the POC's "CanonTether": on a booth device the folder is what an
     * operator sees when they go looking for the night's photos, and it should name the
     * product rather than the prototype it came from.
     */
    const val PUBLIC_DIR_NAME = "FotozenCaptures"

    /**
     * True when we can write plain files to public storage.
     *
     * Pre-Android 11 the legacy permission model applies and public writes just work.
     */
    fun hasPublicStorageAccess(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            Environment.isExternalStorageManager()
        } else {
            true
        }

    /**
     * The best available capture root, preferring public storage.
     *
     * Always returns a usable directory — never throws, never returns null.
     */
    fun resolveRoot(context: Context): File {
        if (hasPublicStorageAccess()) {
            val public = File(Environment.getExternalStorageDirectory(), PUBLIC_DIR_NAME)
            if (runCatching { public.mkdirs(); public.isDirectory && public.canWrite() }
                    .getOrDefault(false)
            ) {
                CanonLog.i("Captures → public storage: %s", public.absolutePath)
                return public
            }
            CanonLog.w("Public storage granted but %s is not writable; falling back", public)
        } else {
            CanonLog.i(
                "No All-files-access permission - captures stay in app storage and will be " +
                    "invisible to gallery and file manager apps (Android 11 scoped storage)",
            )
        }

        val scoped = context.getExternalFilesDir(null) ?: context.filesDir
        CanonLog.i("Captures → app storage: %s", scoped.absolutePath)
        return scoped
    }

    /** Whether [root] is the public location, for surfacing in the UI. */
    fun isPublic(root: File): Boolean = root.name == PUBLIC_DIR_NAME
}
