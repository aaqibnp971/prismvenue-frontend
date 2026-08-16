package com.r13.prismvenues

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var audioFocus: AudioFocusWatcher? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Same channel name and same `externalAudioChanged` message as the
        // Windows runner sends — see AudioFocusWatcher for why the two
        // platforms arrive at it so differently.
        val channel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "prism/audio_focus",
        )
        val watcher = AudioFocusWatcher(applicationContext, channel)
        audioFocus = watcher
        channel.setMethodCallHandler { call, result -> watcher.handle(call, result) }
    }

    override fun onDestroy() {
        // Focus outlives the activity if nobody gives it back, and a venue
        // tablet that has been closed should not be holding the speakers.
        audioFocus?.dispose()
        audioFocus = null
        super.onDestroy()
    }
}
