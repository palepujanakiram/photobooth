package com.srisarani.fotozenai.eventpipeline

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/**
 * Keeps the event pipeline running while the app is not in front.
 *
 * Without this the queue stalls the moment the operator locks the phone: Dart
 * timers are throttled in the background, and on a long event that means an
 * import finishes and then nothing else happens until someone wakes the screen.
 * A foreground service is the only way Android lets a process keep working, and
 * the notification is the price of that.
 *
 * The service does **not** own the work — the stage lanes in
 * [EventPipelineExecutors] and the Dart orchestration do. Its whole job is to
 * keep the process alive and tell the operator why.
 */
class EventPipelineService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int,
    ): Int {
        val text = intent?.getStringExtra(EXTRA_STATUS) ?: "Processing photos"
        startForegroundCompat(text)
        // Restart if the system kills us mid-event; the queue is durable, so
        // resuming costs nothing and stopping silently would lose the event.
        return START_STICKY
    }

    private fun startForegroundCompat(text: String) {
        ensureChannel(this)
        val notification =
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Event photo queue")
                .setContentText(text)
                .setSmallIcon(android.R.drawable.stat_sys_upload)
                .setOngoing(true)
                .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    override fun onDestroy() {
        Log.d(TAG, "pipeline service stopped")
        super.onDestroy()
    }

    companion object {
        private const val TAG = "EventPipelineService"
        private const val CHANNEL_ID = "event_pipeline"
        private const val NOTIFICATION_ID = 4711
        private const val EXTRA_STATUS = "status"

        const val METHOD_CHANNEL = "com.srisarani.fotozenai/event_pipeline_service"

        private fun ensureChannel(context: Context) {
            val manager = context.getSystemService(NotificationManager::class.java)
                ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Event photo queue",
                    // Low: the operator needs to see it is running, not be
                    // interrupted by it every time a photo finishes.
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Keeps importing, framing and printing running."
                    setShowBadge(false)
                },
            )
        }

        fun start(
            context: Context,
            status: String,
        ) {
            val intent =
                Intent(context, EventPipelineService::class.java)
                    .putExtra(EXTRA_STATUS, status)
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, EventPipelineService::class.java))
        }

        /** Lets Dart start and stop the service as the queue fills and drains. */
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
            MethodChannel(messenger, METHOD_CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "start" -> {
                        start(
                            appContext,
                            call.argument<String>("status") ?: "Processing photos",
                        )
                        result.success(true)
                    }
                    "stop" -> {
                        stop(appContext)
                        result.success(true)
                    }
                    "lanes" -> result.success(EventPipelineExecutors.describe())
                    else -> result.notImplemented()
                }
            }
        }
    }
}
