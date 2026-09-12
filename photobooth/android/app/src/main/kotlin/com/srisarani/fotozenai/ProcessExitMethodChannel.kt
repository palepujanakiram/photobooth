package com.srisarani.fotozenai

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Historical process deaths for this UID (API 30+).
 *
 * LMK / SIGKILL / ANR often never reach Dart or Bugsnag. The next launch can
 * still read [ApplicationExitInfo] and report why the previous process died.
 */
object ProcessExitMethodChannel {
    private const val CHANNEL_NAME = "photobooth/process_exits"
    private const val MAX_EXITS = 10

    fun register(
        messenger: BinaryMessenger,
        context: Context,
    ) {
        MethodChannel(messenger, CHANNEL_NAME).setMethodCallHandler { call, result ->
            if (call.method != "getHistoricalProcessExits") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            result.success(readExits(context))
        }
    }

    fun register(
        flutterEngine: FlutterEngine,
        context: Context,
    ) {
        register(flutterEngine.dartExecutor.binaryMessenger, context)
    }

    private fun readExits(context: Context): List<Map<String, Any?>> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return emptyList()
        val activityManager =
            context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
                ?: return emptyList()
        return try {
            activityManager
                .getHistoricalProcessExitReasons(null, 0, MAX_EXITS)
                .map { info -> toMap(info) }
        } catch (_: RuntimeException) {
            emptyList()
        }
    }

    private fun toMap(info: ApplicationExitInfo): Map<String, Any?> {
        return mapOf(
            "timestampMs" to info.timestamp,
            "reason" to reasonName(info.reason),
            "reasonCode" to info.reason,
            "status" to info.status,
            "description" to info.description,
            "importance" to info.importance,
            "pssKb" to info.pss,
            "rssKb" to info.rss,
        )
    }

    private fun reasonName(reason: Int): String {
        return when (reason) {
            ApplicationExitInfo.REASON_EXIT_SELF -> "EXIT_SELF"
            ApplicationExitInfo.REASON_SIGNALED -> "SIGNALED"
            ApplicationExitInfo.REASON_LOW_MEMORY -> "LOW_MEMORY"
            ApplicationExitInfo.REASON_CRASH -> "CRASH"
            ApplicationExitInfo.REASON_CRASH_NATIVE -> "CRASH_NATIVE"
            ApplicationExitInfo.REASON_ANR -> "ANR"
            ApplicationExitInfo.REASON_INITIALIZATION_FAILURE -> "INITIALIZATION_FAILURE"
            ApplicationExitInfo.REASON_PERMISSION_CHANGE -> "PERMISSION_CHANGE"
            ApplicationExitInfo.REASON_EXCESSIVE_RESOURCE_USAGE ->
                "EXCESSIVE_RESOURCE_USAGE"
            ApplicationExitInfo.REASON_USER_REQUESTED -> "USER_REQUESTED"
            ApplicationExitInfo.REASON_USER_STOPPED -> "USER_STOPPED"
            ApplicationExitInfo.REASON_DEPENDENCY_DIED -> "DEPENDENCY_DIED"
            ApplicationExitInfo.REASON_OTHER -> "OTHER"
            else -> namedReasonApi33Plus(reason)
        }
    }

    private fun namedReasonApi33Plus(reason: Int): String {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            reason == ApplicationExitInfo.REASON_FREEZER
        ) {
            return "FREEZER"
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            if (reason == ApplicationExitInfo.REASON_PACKAGE_STATE_CHANGE) {
                return "PACKAGE_STATE_CHANGE"
            }
            if (reason == ApplicationExitInfo.REASON_PACKAGE_UPDATED) {
                return "PACKAGE_UPDATED"
            }
        }
        return "UNKNOWN"
    }
}
