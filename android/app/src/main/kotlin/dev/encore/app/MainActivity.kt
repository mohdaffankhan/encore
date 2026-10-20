package dev.encore.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import com.ryanheise.audioservice.AudioServiceActivity

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
}
