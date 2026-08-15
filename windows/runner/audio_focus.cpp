#include "audio_focus.h"

#include <audiopolicy.h>
#include <endpointvolume.h>
#include <flutter/flutter_engine.h>
#include <mmdeviceapi.h>
#include <windows.h>

#include <chrono>

namespace {

// Peak amplitude, 0..1, above which another session counts as "playing".
//
// Not zero. A session that has finished still reports Active for a couple of
// minutes, and a silent one can read a hair above zero from dither, so testing
// state alone would leave the room paused indefinitely after a video ended.
// This is roughly -46 dBFS: below anything audible, above the floor.
constexpr float kAudibleThreshold = 0.005f;

constexpr auto kPollInterval = std::chrono::seconds(1);

// A tiny RAII holder, so every early return below releases in the right order.
template <typename T>
struct ComPtr {
  T* p = nullptr;
  ~ComPtr() {
    if (p) p->Release();
  }
  T** operator&() { return &p; }
  T* operator->() const { return p; }
  explicit operator bool() const { return p != nullptr; }
};

// Is any process other than this one currently making an audible sound on the
// default render device?
//
// Returns false on any COM failure. A watcher that cannot see the mixer must
// not claim the speakers are busy — that would silence a venue for a reason
// nobody could discover.
bool OtherAppIsPlaying(DWORD own_pid) {
  ComPtr<IMMDeviceEnumerator> enumerator;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_ALL, IID_PPV_ARGS(&enumerator)))) {
    return false;
  }

  ComPtr<IMMDevice> device;
  if (FAILED(enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device))) {
    return false;
  }

  ComPtr<IAudioSessionManager2> manager;
  if (FAILED(device->Activate(__uuidof(IAudioSessionManager2), CLSCTX_ALL,
                              nullptr,
                              reinterpret_cast<void**>(&manager)))) {
    return false;
  }

  ComPtr<IAudioSessionEnumerator> sessions;
  if (FAILED(manager->GetSessionEnumerator(&sessions))) return false;

  int count = 0;
  if (FAILED(sessions->GetCount(&count))) return false;

  for (int i = 0; i < count; i++) {
    ComPtr<IAudioSessionControl> control;
    if (FAILED(sessions->GetSession(i, &control))) continue;

    ComPtr<IAudioSessionControl2> control2;
    if (FAILED(control->QueryInterface(IID_PPV_ARGS(&control2)))) continue;

    // Notification chimes and volume-change beeps are not another app taking
    // the room; pausing a venue for a Windows ding would be absurd.
    if (control2->IsSystemSoundsSession() == S_OK) continue;

    DWORD pid = 0;
    if (FAILED(control2->GetProcessId(&pid)) || pid == own_pid) continue;

    AudioSessionState state = AudioSessionStateInactive;
    if (FAILED(control->GetState(&state)) || state != AudioSessionStateActive) {
      continue;
    }

    // Active is necessary but not sufficient — see kAudibleThreshold.
    ComPtr<IAudioMeterInformation> meter;
    if (FAILED(control->QueryInterface(IID_PPV_ARGS(&meter)))) continue;

    float peak = 0.0f;
    if (SUCCEEDED(meter->GetPeakValue(&peak)) && peak > kAudibleThreshold) {
      return true;
    }
  }
  return false;
}

}  // namespace

AudioFocusWatcher::AudioFocusWatcher(flutter::FlutterEngine* engine)
    : channel_(std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          engine->messenger(), "prism/audio_focus",
          &flutter::StandardMethodCodec::GetInstance())) {}

AudioFocusWatcher::~AudioFocusWatcher() { Stop(); }

void AudioFocusWatcher::Start() {
  if (running_.exchange(true)) return;
  thread_ = std::thread(&AudioFocusWatcher::Run, this);
}

void AudioFocusWatcher::Stop() {
  if (!running_.exchange(false)) return;
  if (thread_.joinable()) thread_.join();
}

void AudioFocusWatcher::Run() {
  // Its own apartment: this thread owns every interface it creates, and the
  // Flutter platform thread must not be blocked by a COM call that can take
  // milliseconds when a device is being switched.
  if (FAILED(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED))) return;

  const DWORD own_pid = GetCurrentProcessId();
  bool last_reported = false;
  bool first = true;

  while (running_.load()) {
    const bool playing = OtherAppIsPlaying(own_pid);

    // Only on a change. The app would handle a repeat harmlessly — silence()
    // and resume() are both idempotent — but a message a second forever is
    // noise in every log and profile for no gain.
    if (first || playing != last_reported) {
      first = false;
      last_reported = playing;
      channel_->InvokeMethod(
          "externalAudioChanged",
          std::make_unique<flutter::EncodableValue>(playing));
    }

    // Sliced so quitting is responsive: joining on a full second of sleep makes
    // window close visibly lag.
    for (int i = 0; i < 10 && running_.load(); i++) {
      std::this_thread::sleep_for(kPollInterval / 10);
    }
  }

  CoUninitialize();
}
