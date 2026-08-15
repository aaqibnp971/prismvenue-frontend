#ifndef RUNNER_AUDIO_FOCUS_H_
#define RUNNER_AUDIO_FOCUS_H_

#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>

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
  // Sends `externalAudioChanged` with a bool on `prism/audio_focus`.
  explicit AudioFocusWatcher(flutter::FlutterEngine* engine);
  ~AudioFocusWatcher();

  AudioFocusWatcher(const AudioFocusWatcher&) = delete;
  AudioFocusWatcher& operator=(const AudioFocusWatcher&) = delete;

  void Start();
  void Stop();

 private:
  void Run();

  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel_;
  std::thread thread_;
  std::atomic<bool> running_{false};
};

#endif  // RUNNER_AUDIO_FOCUS_H_
