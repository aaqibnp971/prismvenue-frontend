package com.r13.prismvenues

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Tells the app when something else on this device wants the speakers.
 *
 * ## Why this is not the Windows implementation
 *
 * `windows/runner/audio_focus.cpp` answers the same question by walking the
 * mixer's session list once a second, because Windows has no notion of audio
 * focus — every process opens the shared output and they all sound at once.
 *
 * Android does have the notion, and it is the opposite shape: you *request*
 * focus, the system grants or refuses it, and it calls you back when you lose
 * or regain it. Polling here would be both wrong and rude — wrong because
 * `isMusicActive()` counts our own playback, and rude because an app that never
 * requests focus is one the rest of the system cannot duck. So Prism asks, and
 * gets told.
 *
 * The Dart seam is unchanged: `externalAudioChanged(bool)` still means "somebody
 * else has the speakers". Only the two `requestFocus` / `abandonFocus` calls are
 * new, and they are no-ops on platforms that answer the question without being
 * asked.
 *
 * ## Permanent loss, and why it still polls a little
 *
 * A transient loss — a call, a notification, a short video — is followed by
 * `AUDIOFOCUS_GAIN`, so the room comes back on its own. A **permanent** loss
 * has no such callback: the system hands the speakers to another app and stops
 * talking to us.
 *
 * On a phone that is the end of it, and every media app stays stopped. A venue
 * is not a phone: nobody is going to notice the music never came back after a
 * staff member watched a clip. So after a permanent loss only, this polls
 * `isMusicActive()` until the speakers are free and reports that. The reading is
 * trustworthy in exactly this window, because Prism itself is silent — which is
 * the one case where `isMusicActive()` is not answering about us.
 */
class AudioFocusWatcher(
    private val context: Context,
    private val channel: MethodChannel,
) : AudioManager.OnAudioFocusChangeListener {

    private val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val main = Handler(Looper.getMainLooper())

    private var request: AudioFocusRequest? = null
    private var pollingAfterPermanentLoss = false

    private val attributes = AudioAttributes.Builder()
        // MEDIA/GAME would both duck for a notification. This is the room's
        // music: it is the media, and it should be treated as such.
        .setUsage(AudioAttributes.USAGE_MEDIA)
        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
        .build()

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestFocus" -> result.success(requestFocus())
            "abandonFocus" -> {
                abandonFocus()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /** True when Prism may play. Idempotent — holding focus twice is not a thing. */
    private fun requestFocus(): Boolean {
        stopPolling()
        request?.let { return true }

        val next = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
            .setAudioAttributes(attributes)
            // False: the engine ramps every gain change itself (prism-core rule
            // 3, nothing steps), and a system duck would fight that ramp. Prism
            // stops instead, which is also what a venue wants — music at half
            // volume under a phone call is worse than no music.
            .setWillPauseWhenDucked(true)
            .setOnAudioFocusChangeListener(this, main)
            .build()

        val granted = audio.requestAudioFocus(next) ==
            AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        if (granted) request = next
        return granted
    }

    fun abandonFocus() {
        stopPolling()
        request?.let {
            audio.abandonAudioFocusRequest(it)
            request = null
        }
    }

    override fun onAudioFocusChange(change: Int) {
        when (change) {
            AudioManager.AUDIOFOCUS_GAIN -> {
                stopPolling()
                notify(false)
            }

            // Ours again is not coming. The system has given the speakers away.
            AudioManager.AUDIOFOCUS_LOSS -> {
                request = null // already revoked; abandoning it again is a no-op
                notify(true)
                startPollingForSilence()
            }

            // A call, a notification, a clip. GAIN follows, so the request is
            // deliberately kept — abandoning here is what would stop it coming.
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT,
            AudioManager.AUDIOFOCUS_LOSS_TRANSIENT_CAN_DUCK -> notify(true)
        }
    }

    private fun startPollingForSilence() {
        if (pollingAfterPermanentLoss) return
        pollingAfterPermanentLoss = true
        main.postDelayed(pollTick, POLL_MS)
    }

    private val pollTick = object : Runnable {
        override fun run() {
            if (!pollingAfterPermanentLoss) return
            if (!audio.isMusicActive) {
                pollingAfterPermanentLoss = false
                notify(false)
                return
            }
            main.postDelayed(this, POLL_MS)
        }
    }

    private fun stopPolling() {
        pollingAfterPermanentLoss = false
        main.removeCallbacks(pollTick)
    }

    private fun notify(playing: Boolean) {
        main.post { channel.invokeMethod("externalAudioChanged", playing) }
    }

    fun dispose() {
        abandonFocus()
    }

    private companion object {
        const val POLL_MS = 1_000L
    }
}
