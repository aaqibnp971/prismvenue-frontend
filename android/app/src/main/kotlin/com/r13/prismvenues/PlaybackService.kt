package com.r13.prismvenues

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.media.session.MediaSession
import android.media.session.PlaybackState
import androidx.core.app.NotificationCompat

/**
 * Keeps the room playing when nothing is on screen.
 *
 * Finding #1: a venue tablet sits on a shelf and auto-locks, or a staff member
 * switches to the till app. Android then suspends the process and the room goes
 * quiet, with nothing anywhere to say why. The first person to notice is a
 * customer.
 *
 * ## Why a service AND a media session
 *
 * `foregroundServiceType="mediaPlayback"` is the AOSP contract that says "do
 * not reclaim me to save battery". Several OEM battery managers (HyperOS,
 * ColorOS, Funtouch, One UI) run a second policy layer that does not honour it
 * — but most of them key their whitelist off "does this app own a live
 * MediaSession", not off the service type. A foreground service with no session
 * reads to them as a long-lived notification, and notifications are killable.
 * So the session below is not decoration: it is the part those devices check.
 *
 * See PLAYER_RELIABILITY.md T1.1. None of this is sufficient alone, and none of
 * it will ever reproduce on a development device — stock Android and emulators
 * do not run that second layer.
 *
 * ## The notification is not optional
 *
 * Android requires a foreground service to post one. That is a feature here: it
 * is the only place a member of staff can see that Prism is the thing making
 * the sound, and tapping it returns to the app.
 */
class PlaybackService : Service() {

    companion object {
        const val ACTION_START = "com.r13.prismvenues.PLAY"
        const val ACTION_STOP = "com.r13.prismvenues.STOP"

        /** Extra carrying the mood name, so the notification can say it. */
        const val EXTRA_TEXT = "text"

        private const val CHANNEL_ID = "prism_playback"
        private const val NOTIFICATION_ID = 1
    }

    // The platform MediaSession, not MediaSessionCompat: the compat class lives
    // in androidx.media, and pulling a dependency in for one session when the
    // platform one has existed since API 21 is not a trade worth making.
    private var session: MediaSession? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopPlayback()
                return START_NOT_STICKY
            }
            else -> startPlayback(intent?.getStringExtra(EXTRA_TEXT))
        }
        // START_STICKY so an ordinary low-memory kill brings the service back.
        // It does NOT survive a force-stop from a cleaner app — nothing inside
        // the app can (T1.2), which is why last-seen reporting exists.
        return START_STICKY
    }

    private fun startPlayback(text: String?) {
        ensureChannel()

        val media = session ?: MediaSession(this, "PrismVenues").also {
            session = it
        }
        // ACTIVE and PLAYING for as long as audio is intended. An inactive
        // session is exactly what the OEM whitelists ignore.
        media.setPlaybackState(
            PlaybackState.Builder()
                .setState(PlaybackState.STATE_PLAYING, 0, 1.0f)
                .setActions(PlaybackState.ACTION_STOP)
                .build(),
        )
        media.isActive = true

        startForeground(NOTIFICATION_ID, buildNotification(text))
    }

    private fun stopPlayback() {
        session?.let {
            it.setPlaybackState(
                PlaybackState.Builder()
                    .setState(PlaybackState.STATE_STOPPED, 0, 0f)
                    .build(),
            )
            it.isActive = false
            it.release()
        }
        session = null
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun buildNotification(text: String?): Notification {
        val open = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Prism is playing")
            .setContentText(text ?: "This device is driving the room.")
            .setSmallIcon(android.R.drawable.ic_media_play)
            .setContentIntent(open)
            // Low: staff should be able to see it, never be interrupted by it.
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_TRANSPORT)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        manager.createNotificationChannel(
            NotificationChannel(
                CHANNEL_ID,
                "Playing",
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "Shown while this device is driving a room."
                setShowBadge(false)
            },
        )
    }

    override fun onDestroy() {
        session?.release()
        session = null
        super.onDestroy()
    }
}
