package dev.encore.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.ryanheise.audioservice.AudioService

/// Runs while songs download, so they finish after Encore is closed, and
/// shows their progress. The downloads themselves run in Dart (the same
/// code as on desktop); this keeps that alive:
/// - as a foreground service, it keeps the app's process running;
/// - it binds to the player's AudioService, which holds the Flutter engine.
///   Closing Encore stops the player (as in Spotify), and a stopped
///   AudioService destroys the engine once nothing is bound to it; bound
///   here, it waits until the downloads are done.
class DownloadService : Service() {
    companion object {
        private const val TAG = "DownloadService"
        private const val CHANNEL = "dev.encore.downloads"
        private const val PROGRESS_ID = 2001
        private const val DONE_ID = 2002

        private enum class State { STOPPED, STARTING, RUNNING }

        private var state = State.STOPPED
        private var stopOnceStarted = false
        private var latest: Notification? = null

        /// [number] of [total] songs is downloading, [percent] done.
        fun progress(context: Context, title: String, number: Int, total: Int, percent: Int) {
            val notification = build(context) {
                setContentTitle("Downloading $number of $total")
                    .setContentText(title)
                    .setProgress(100, percent, false)
                    .setOngoing(true)
                    .setOnlyAlertOnce(true)
                    // Android 12+ otherwise holds it back for up to 10 s.
                    .setForegroundServiceBehavior(
                        NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE
                    )
            }
            latest = notification
            stopOnceStarted = false
            when (state) {
                State.RUNNING -> manager(context).notify(PROGRESS_ID, notification)
                State.STARTING -> {} // shows [latest] when it starts
                State.STOPPED -> try {
                    state = State.STARTING
                    ContextCompat.startForegroundService(
                        context, Intent(context, DownloadService::class.java)
                    )
                } catch (e: Exception) {
                    // Not allowed from the background (Android 12+): the
                    // downloads go on while Encore runs anyway.
                    state = State.STOPPED
                    Log.w(TAG, "Couldn't start: $e")
                }
            }
        }

        /// The downloads are done: [done] saved, [failed] not. [notify]
        /// says so in a notification (when Encore isn't on screen).
        fun finished(context: Context, done: Int, failed: Int, notify: Boolean) {
            when (state) {
                // Stopping before it has started would crash the app.
                State.STARTING -> stopOnceStarted = true
                State.RUNNING -> {
                    state = State.STOPPED
                    context.stopService(Intent(context, DownloadService::class.java))
                }
                State.STOPPED -> {}
            }
            if (!notify || done + failed == 0) return
            val title =
                if (done == 0) "Couldn't download ${songs(failed)}" else "Downloaded ${songs(done)}"
            manager(context).notify(DONE_ID, build(context) {
                setContentTitle(title)
                if (done > 0 && failed > 0) setContentText("${songs(failed)} couldn't be downloaded")
                setAutoCancel(true)
            })
        }

        private fun songs(n: Int) = if (n == 1) "1 song" else "$n songs"

        private fun manager(context: Context) =
            context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

        private fun build(
            context: Context,
            content: NotificationCompat.Builder.() -> Unit,
        ): Notification {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager(context).createNotificationChannel(
                    NotificationChannel(CHANNEL, "Downloads", NotificationManager.IMPORTANCE_LOW)
                )
            }
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
            return NotificationCompat.Builder(context, CHANNEL)
                .setSmallIcon(R.drawable.ic_stat_encore)
                .setCategory(NotificationCompat.CATEGORY_PROGRESS)
                .setContentIntent(
                    open?.let {
                        PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE)
                    }
                )
                .apply(content)
                .build()
        }
    }

    private var bound = false
    private val player = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName?, service: IBinder?) {}
        override fun onServiceDisconnected(name: ComponentName?) {}
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = latest ?: build(this) { setContentTitle("Downloading") }
        ServiceCompat.startForeground(
            this, PROGRESS_ID, notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q)
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        )
        state = State.RUNNING
        if (!bound) {
            bound = bindService(
                Intent(this, AudioService::class.java)
                    .setAction("android.media.browse.MediaBrowserService"),
                player, Context.BIND_AUTO_CREATE
            )
        }
        if (stopOnceStarted) {
            stopOnceStarted = false
            stopSelf()
        }
        return START_NOT_STICKY
    }

    // Android 15 allows data syncs 6 hours a day; past that, it stops here.
    override fun onTimeout(startId: Int, fgsType: Int) = stopSelf()

    override fun onDestroy() {
        state = State.STOPPED
        if (bound) {
            unbindService(player)
            bound = false
        }
        super.onDestroy()
    }
}
