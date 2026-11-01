package dev.encore.app

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.os.Build
import android.os.Bundle
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// AudioServiceActivity keeps the Flutter engine alive for background playback.
class MainActivity : AudioServiceActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 13+ hides all notifications, including the media player in
        // the notification panel and lock screen, until the user allows them.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 0)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Mobile data (or a hotspot): Settings can stream at lower quality.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.encore.app/network")
            .setMethodCallHandler { call, result ->
                if (call.method == "isMetered") {
                    val network =
                        getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
                    result.success(network.isActiveNetworkMetered)
                } else {
                    result.notImplemented()
                }
            }
    }

    private var askedForRate = false

    override fun onFlutterUiDisplayed() {
        super.onFlutterUiDisplayed()
        askForHighRefreshRate()
    }

    // Phones with 120 Hz screens (e.g. Samsung's adaptive refresh) only give
    // Flutter's surface 120 Hz while a finger is on the screen, so animations
    // after it lifts (a swipe settling, the player opening, song changes)
    // ran at 60. Asking for the screen's highest rate fixes that. It is a
    // vote for when the surface draws: a still screen can still drop lower.
    private fun askForHighRefreshRate() {
        if (askedForRate || Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        val surface = findSurfaceView(window.decorView) ?: return
        val rate = display?.supportedModes?.maxOfOrNull { it.refreshRate } ?: return
        if (rate <= 60f) return
        askedForRate = true
        fun ask(holder: SurfaceHolder) {
            if (holder.surface.isValid) {
                holder.surface.setFrameRate(rate, Surface.FRAME_RATE_COMPATIBILITY_DEFAULT)
            }
        }
        ask(surface.holder)
        // The surface is made again after the app was in the background.
        surface.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) = ask(holder)
            override fun surfaceChanged(holder: SurfaceHolder, format: Int, w: Int, h: Int) {}
            override fun surfaceDestroyed(holder: SurfaceHolder) {}
        })
    }

    private fun findSurfaceView(view: View): SurfaceView? {
        if (view is SurfaceView) return view
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) {
                findSurfaceView(view.getChildAt(i))?.let { return it }
            }
        }
        return null
    }
}
