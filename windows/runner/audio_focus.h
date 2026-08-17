#ifndef RUNNER_AUDIO_FOCUS_H_
#define RUNNER_AUDIO_FOCUS_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

#include <windows.h>

#include <atomic>
#include <memory>
#include <thread>

namespace flutter {
class FlutterEngine;
}

// Tells the app when another program starts making noise through the same
// speakers, so Prism can get out of the way.
//
// ## Why this exists at all
//
// Every other platform hands this to you. iOS interrupts the audio session and
// Android grants or revokes audio focus, so "something else is playing, stop"
// arrives as an event. **Windows has no such concept** — every process opens
// the shared mixer and they all play at once, which is why starting a video
// left the room's music running underneath it, and why the laptop's media keys
// did nothing: Prism renders a generated stream rather than a track, so nothing
// registers it as media at all.
//
// So the signal has to be built. This walks the default render device's session
// list (the same list Volume Mixer shows), skips our own process and the system
// sounds session, and reports whether anything else is *actually* emitting —
// state alone is not enough, because a session stays Active for a while after
// its audio stops. The peak meter is what separates "open" from "playing".
//
// ## Polling, deliberately
//
// `IAudioSessionNotification` would push, but it fires on session creation and
// destruction rather than on audible/silent, so a browser tab that keeps its
// session open between videos never reports anything. A one-second poll asks
// the question that actually matters, and the cost is one COM call per session
// per second on a control thread.
//
// Nothing here touches the audio render path. It talks to Dart, which decides
// what to do — the engine seam already treats silence as a state (pause and
// takeover both use it), so this is one more input to the same place.
class AudioFocusWatcher {
 public:
  /// Window message used to hop a reading onto the platform thread.
  ///
  /// **Flutter's method channels are not thread-safe.** They may only be
  /// invoked on the platform thread, and this class does its looking on a
  /// worker — so posting the answer through the window's own message queue is
  /// what makes it legal. Calling InvokeMethod straight from the poll thread
  /// appeared to work and dropped messages under load, which is the worst
  /// shape a bug like this can take: the room paused, and then sometimes never
  /// came back, because the message saying the speakers were free was the one
  /// that went missing.
  static constexpr UINT kFocusMessage = WM_APP + 0x51;

  // Sends `externalAudioChanged` with a bool on `prism/audio_focus`.
  AudioFocusWatcher(flutter::FlutterEngine* engine, HWND window);
  ~AudioFocusWatcher();

  AudioFocusWatcher(const AudioFocusWatcher&) = delete;
  AudioFocusWatcher& operator=(const AudioFocusWatcher&) = delete;

  void Start();
  void Stop();

  /// Called from the window procedure, on the platform thread, with the value
  /// the worker posted. The only place the channel is touched.
  void Emit(bool playing);

 private:
  void Run();

  HWND window_;

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::thread thread_;
  std::atomic<bool> running_{false};
};

#endif  // RUNNER_AUDIO_FOCUS_H_
