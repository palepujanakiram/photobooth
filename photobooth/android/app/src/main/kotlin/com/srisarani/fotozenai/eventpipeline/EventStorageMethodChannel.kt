package com.srisarani.fotozenai.eventpipeline

import android.content.Context
import android.hardware.usb.UsbManager
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.os.storage.StorageManager
import android.provider.MediaStore
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * Storage discovery and MediaStore enumeration for the event pipeline ingest.
 *
 * The probe run on 2026-09-07 settled the mechanism: a USB card reader auto-mounts,
 * the app UID **cannot** read `/storage/<uuid>/` directly even holding sdcard_rw
 * (that needs MANAGE_EXTERNAL_STORAGE, which is Play-restricted), but MediaStore
 * indexes the card completely. One cursor therefore yields the whole tier-1 dedupe
 * key plus `datetaken`, with no file reads at all.
 *
 * [probeStorage] is retained so the same measurement can be repeated on the Amlogic
 * box, where `vold` and MediaProvider behaviour still has to be confirmed.
 */
object EventStorageMethodChannel {
    private const val TAG = "EventStorage"
    const val CHANNEL_NAME = "com.srisarani.fotozenai/event_storage"

    private val mainHandler = Handler(Looper.getMainLooper())

    fun register(
        flutterEngine: FlutterEngine,
        context: Context,
    ) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }

    fun register(
        messenger: BinaryMessenger,
        context: Context,
    ) {
        val appContext = context.applicationContext
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            // Every call touches disk or a content provider, so none of it belongs
            // on the platform thread.
            EventPipelineExecutors.io.execute {
                val response =
                    try {
                        Result.success(dispatch(appContext, call.method, call.arguments))
                    } catch (e: Throwable) {
                        Log.e(TAG, "${call.method} failed", e)
                        Result.failure<Any?>(e)
                    }
                mainHandler.post {
                    response.fold(
                        onSuccess = { value ->
                            if (value == NOT_IMPLEMENTED) {
                                result.notImplemented()
                            } else {
                                result.success(value)
                            }
                        },
                        onFailure = { error ->
                            result.error("event_storage_error", error.message, null)
                        },
                    )
                }
            }
        }
    }

    private val NOT_IMPLEMENTED = Any()

    private fun dispatch(
        context: Context,
        method: String,
        arguments: Any?,
    ): Any? {
        val args = arguments as? Map<*, *> ?: emptyMap<String, Any?>()
        return when (method) {
            "probeStorage" -> probeStorage(context)
            "listVolumes" -> listRemovableVolumes(context)
            "queryImages" ->
                queryImages(
                    context,
                    volumeName = args["volumeName"] as? String ?: return emptyList<Any?>(),
                    folderPrefixes = (args["folders"] as? List<*>)?.filterIsInstance<String>(),
                )
            "readRange" ->
                readRange(
                    context,
                    uri = args["uri"] as? String ?: return ByteArray(0),
                    offset = (args["offset"] as? Number)?.toLong() ?: 0L,
                    length = (args["length"] as? Number)?.toInt() ?: 0,
                )
            "freeBytes" -> freeBytes(args["path"] as? String)
            "lanes" -> EventPipelineExecutors.describe()
            else -> NOT_IMPLEMENTED
        }
    }

    // ------------------------------------------------------------------ probe

    /**
     * The Phase 1 measurement, kept so it can be re-run on unfamiliar hardware.
     *
     * `directRead` is the decisive field: when it is false — as measured on
     * Android 13 — plain `File` APIs are out and MediaStore is the mechanism.
     */
    fun probeStorage(context: Context): Map<String, Any?> {
        val volumes = listAllVolumes(context)
        return mapOf(
            "volumes" to volumes,
            "mediaStoreVolumes" to MediaStore.getExternalVolumeNames(context).toList(),
            "usbDevices" to listUsbDevices(context),
        )
    }

    private fun listAllVolumes(context: Context): List<Map<String, Any?>> {
        val storageManager = context.getSystemService(StorageManager::class.java)
            ?: return emptyList()
        return storageManager.storageVolumes.map { volume ->
            val directory = volume.directory
            mapOf(
                "uuid" to volume.uuid,
                "description" to volume.getDescription(context),
                "isRemovable" to volume.isRemovable,
                "isPrimary" to volume.isPrimary,
                "state" to volume.state,
                "path" to directory?.absolutePath,
                // Whether the app UID can enumerate it with no grant at all.
                "directRead" to canListDirectly(directory),
                "mediaStoreVolumeName" to volume.mediaStoreVolumeName,
                // Capacity, so the picker can tell two seated cards apart by
                // more than a UUID an operator has no way to recognise.
                "totalBytes" to totalBytes(directory?.absolutePath),
            )
        }
    }

    private fun canListDirectly(directory: File?): Boolean {
        if (directory == null) return false
        return try {
            directory.listFiles() != null
        } catch (e: SecurityException) {
            Log.d(TAG, "directRead denied for ${directory.absolutePath}: ${e.message}")
            false
        }
    }

    private fun listUsbDevices(context: Context): List<Map<String, Any?>> {
        val usbManager = context.getSystemService(UsbManager::class.java) ?: return emptyList()
        return usbManager.deviceList.values.map { device ->
            val interfaces = (0 until device.interfaceCount).map { device.getInterface(it) }
            mapOf(
                "deviceName" to device.deviceName,
                "vendorId" to device.vendorId,
                "productId" to device.productId,
                "manufacturerName" to device.manufacturerName,
                "productName" to device.productName,
                // Interface class 8 is USB Mass Storage — a card reader.
                "isMassStorage" to interfaces.any { it.interfaceClass == 8 },
                "interfaceClasses" to interfaces.map { it.interfaceClass },
            )
        }
    }

    /**
     * Removable volumes that MediaStore can be queried against.
     *
     * A volume with no `mediaStoreVolumeName` is mounted but not indexed, which is
     * the case Dart must surface rather than reporting an empty card.
     */
    fun listRemovableVolumes(context: Context): List<Map<String, Any?>> {
        val indexed = MediaStore.getExternalVolumeNames(context)
        return listAllVolumes(context)
            .filter { it["isRemovable"] == true }
            .map { volume ->
                val name = volume["mediaStoreVolumeName"] as? String
                volume + mapOf("isIndexed" to (name != null && indexed.contains(name)))
            }
    }

    // ------------------------------------------------------------- enumeration

    /**
     * One cursor over a volume's images, returning the whole tier-1 dedupe key.
     *
     * `DATE_MODIFIED` is **seconds** while `DATE_TAKEN` is **milliseconds** — a
     * real distinction, confirmed on a probe card where the two were eleven hours
     * apart. Modified time is normalised to ms here so Dart never has to know.
     */
    fun queryImages(
        context: Context,
        volumeName: String,
        folderPrefixes: List<String>?,
    ): List<Map<String, Any?>> {
        val collection = MediaStore.Images.Media.getContentUri(volumeName)
        val projection =
            arrayOf(
                MediaStore.Images.Media._ID,
                MediaStore.Images.Media.DISPLAY_NAME,
                MediaStore.Images.Media.SIZE,
                MediaStore.Images.Media.DATE_MODIFIED,
                MediaStore.Images.Media.DATE_TAKEN,
                MediaStore.Images.Media.RELATIVE_PATH,
                MediaStore.Images.Media.MIME_TYPE,
                MediaStore.Images.Media.WIDTH,
                MediaStore.Images.Media.HEIGHT,
                MediaStore.Images.Media.ORIENTATION,
            )

        val out = mutableListOf<Map<String, Any?>>()
        context.contentResolver
            .query(collection, projection, null, null, null)
            ?.use { cursor ->
                val idCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media._ID)
                val nameCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DISPLAY_NAME)
                val sizeCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.SIZE)
                val modCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_MODIFIED)
                val takenCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.DATE_TAKEN)
                val pathCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.RELATIVE_PATH)
                val mimeCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.MIME_TYPE)
                val widthCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.WIDTH)
                val heightCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.HEIGHT)
                val orientCol = cursor.getColumnIndexOrThrow(MediaStore.Images.Media.ORIENTATION)

                while (cursor.moveToNext()) {
                    val relativeDir = cursor.getString(pathCol).orEmpty().trim('/')
                    if (!matchesPrefix(relativeDir, folderPrefixes)) continue
                    val name = cursor.getString(nameCol).orEmpty()
                    val id = cursor.getLong(idCol)
                    out.add(
                        mapOf(
                            "uri" to Uri.withAppendedPath(collection, id.toString()).toString(),
                            "displayName" to name,
                            "relativePath" to if (relativeDir.isEmpty()) name else "$relativeDir/$name",
                            "folder" to relativeDir,
                            "sizeBytes" to cursor.getLong(sizeCol),
                            "modifiedAtMs" to cursor.getLong(modCol) * 1000L,
                            "capturedAtMs" to cursor.getLong(takenCol).takeIf { it > 0 },
                            "mimeType" to cursor.getString(mimeCol),
                            "width" to cursor.getInt(widthCol).takeIf { it > 0 },
                            "height" to cursor.getInt(heightCol).takeIf { it > 0 },
                            "orientation" to cursor.getInt(orientCol),
                        ),
                    )
                }
            }
        return out
    }

    /** Segment-aware prefix match, so `DCIM` does not also match `DCIMX`. */
    private fun matchesPrefix(
        folder: String,
        prefixes: List<String>?,
    ): Boolean {
        if (prefixes.isNullOrEmpty()) return true
        val lower = folder.lowercase()
        return prefixes.any { raw ->
            val root = raw.trim('/').lowercase()
            root.isEmpty() || lower == root || lower.startsWith("$root/")
        }
    }

    /**
     * Reads a window of a MediaStore item, for the content-key samples.
     *
     * Only head and tail are ever requested — 128 KiB per genuinely-new photo
     * rather than reading a 6 MB file end to end.
     */
    fun readRange(
        context: Context,
        uri: String,
        offset: Long,
        length: Int,
    ): ByteArray {
        if (length <= 0) return ByteArray(0)
        context.contentResolver.openInputStream(Uri.parse(uri))?.use { input ->
            var remaining = offset
            while (remaining > 0) {
                val skipped = input.skip(remaining)
                if (skipped <= 0) break
                remaining -= skipped
            }
            val buffer = ByteArray(length)
            var filled = 0
            while (filled < length) {
                val read = input.read(buffer, filled, length - filled)
                if (read < 0) break
                filled += read
            }
            return if (filled == length) buffer else buffer.copyOf(filled)
        }
        return ByteArray(0)
    }

    /**
     * Free space on the volume holding [path].
     *
     * Event media sits outside `KioskDiskGuard` by design, so a free-space floor
     * is the only thing stopping an import filling the disk.
     */
    private fun totalBytes(path: String?): Long? {
        val target = path?.takeIf { it.isNotBlank() } ?: return null
        return try {
            val stat = StatFs(target)
            stat.blockCountLong * stat.blockSizeLong
        } catch (e: IllegalArgumentException) {
            Log.d(TAG, "totalBytes failed for $target: ${e.message}")
            null
        }
    }

    private fun freeBytes(path: String?): Long? {
        val target = path?.takeIf { it.isNotBlank() } ?: return null
        return try {
            val stat = StatFs(target)
            stat.availableBlocksLong * stat.blockSizeLong
        } catch (e: IllegalArgumentException) {
            Log.d(TAG, "freeBytes failed for $target: ${e.message}")
            null
        }
    }
}
