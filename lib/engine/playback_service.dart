import 'package:flutter/services.dart';

/// Tells the platform that this device is currently driving a room.
///
/// Finding #1: a venue tablet sits on a shelf and auto-locks, or a staff member
/// opens the till app. The OS suspends Prism, the room goes quiet, and nothing
/// on screen says why — the first person to notice is a customer.
///
/// The two platforms need opposite things and both are sent from here:
///
/// * **Android** needs a foreground service typed `mediaPlayback`, holding a
///   live `MediaSession`, or the process is reclaimed once the screen is off.
///   It also gets `FLAG_KEEP_SCREEN_ON`, which stops the screen going off at
///   all — the thing an owner actually wanted when they mounted a tablet.
/// * **iOS** needs the `audio` background mode (Info.plist) plus an active
///   `.playback` session, both already in place; the call below additionally
///   disables the idle timer so a wall-mounted iPad does not dim and lock.
/// * **Windows** needs neither and implements neither.
///
/// Deliberately a separate channel from `prism/audio_focus`. Focus is the OS
/// telling us whether we MAY play; this is us telling the OS that we ARE.
/// Opposite directions, and running them over one channel made the focus
/// handler's contract harder to read than it needed to be.
///
/// Every call is best-effort. A platform that cannot answer must never be able
/// to keep a venue silent, so `MissingPluginException` is the normal case on
/// Windows, on web and in tests — not an error.
const MethodChannel playbackServiceChannel =
    MethodChannel('prism/playback_service');

/// This device has started driving [text] — a mood name, for the notification.
Future<void> startForegroundPlayback({String? text}) async {
  try {
    await playbackServiceChannel
        .invokeMethod<void>('startPlaying', {'text': text});
  } on MissingPluginException {
    // Windows, web, tests. Nothing to hold up.
  } catch (_) {
    // A refused notification permission lands here. The room keeps playing
    // while the app is in front either way, so this must not propagate.
  }
}

/// This device has stopped driving a room.
///
/// Called on pause, takeover, sign-out and external audio — anything that makes
/// the room deliberately silent. Leaving the service up would keep a
/// "Prism is playing" notification on a tablet that is not playing, and hold
/// the screen awake all night for nothing.
Future<void> stopForegroundPlayback() async {
  try {
    await playbackServiceChannel.invokeMethod<void>('stopPlaying');
  } on MissingPluginException {
    // As above.
  } catch (_) {}
}
