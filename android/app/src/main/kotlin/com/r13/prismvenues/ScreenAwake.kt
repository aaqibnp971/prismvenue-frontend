package com.r13.prismvenues

import android.app.Activity
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Starts and stops the foreground service, and keeps the screen on with it.
 *
 * Finding #1 has two halves on Android and they are easy to confuse. The
 * service keeps the PROCESS alive once the screen is off. `FLAG_KEEP_SCREEN_ON`
 * stops the screen going off in the first place, which is what an owner
 * actually asked for when they put a tablet on a shelf and it locked itself.
 *
 * The flag is held only while Prism is driving audio, never for the life of the
 * app: a tablet somebody is using to edit next week's schedule should be
 * allowed to sleep like any other device.
 *
 * Both are driven from one Dart call, because they answer the same question —
 * "is this device the player right now?" — and drifting apart would give a
 * service with no screen, or a screen with no service.
 */
class ScreenAwake(private val activity: Activity) {

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startPlaying" -> {
                val text = call.argument<String>("text")
                val intent = android.content.Intent(activity, PlaybackService::class.java)
                    .setAction(PlaybackService.ACTION_START)
                    .putExtra(PlaybackService.EXTRA_TEXT, text)
                // startForegroundService, not startService: from O onwards the
                // latter throws once the app is in the background, which is
                // precisely when this matters.
                activity.startForegroundService(intent)
                keepScreenOn(true)
                result.success(null)
            }

            "stopPlaying" -> {
                activity.startService(
                    android.content.Intent(activity, PlaybackService::class.java)
                        .setAction(PlaybackService.ACTION_STOP),
                )
                keepScreenOn(false)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /** Window flags are main-thread only; every caller here is already on it. */
    private fun keepScreenOn(on: Boolean) {
        activity.runOnUiThread {
            if (on) {
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            } else {
                activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
            }
        }
    }

    /** Leave nothing holding the screen awake behind us. */
    fun dispose() = keepScreenOn(false)
}
