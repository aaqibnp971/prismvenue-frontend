import AVFoundation
import Flutter

/// Tells the app when something else on this device wants the speakers.
///
/// ## Three platforms, three mechanisms, one message
///
/// The Dart seam is `externalAudioChanged(bool)` and it means the same thing
/// everywhere. How the answer is reached does not survive being shared:
///
/// * **Windows** has no notion of audio focus at all — every process opens the
///   shared mixer — so the runner walks the session list once a second and
///   volunteers the answer.
/// * **Android** grants focus on request and calls back on loss and gain.
/// * **iOS** interrupts. There is no "who else is playing" question to ask; the
///   system stops your session and tells you afterwards, then tells you when it
///   is over — and separately publishes a *hint* when another app's audio
///   starts or stops alongside yours.
///
/// Both iOS signals are listened to, because they cover different things.
/// `interruptionNotification` is a call or an alarm — audio taken away.
/// `silenceSecondaryAudioHintNotification` is another app starting its own
/// playback while ours is technically still allowed: the case a venue cares
/// about most, and the one an interruption never fires for.
///
/// ## Why `.began` is not always followed by a resume
///
/// `.ended` carries an options set, and `shouldResume` is the system saying
/// whether picking up again is appropriate — a call that ended, yes; a music
/// app the user deliberately started, no. Ignoring it is how an app gets a
/// reputation for fighting the user for the speakers.
///
/// A venue is not quite a phone, though, and silence nobody notices is its own
/// failure. So when the system withholds `shouldResume`, the session is probed
/// once — `setActive(true)` succeeds only if nothing else holds it — and the
/// room comes back only if it genuinely can.
final class AudioFocusWatcher {

    private let channel: FlutterMethodChannel
    private let session = AVAudioSession.sharedInstance()
    private var lastReported = false

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(
            name: "prism/audio_focus",
            binaryMessenger: messenger
        )
        configureSession()
        observe()
        channel.setMethodCallHandler { [weak self] call, result in
            self?.handle(call, result)
        }
    }

    /// `.playback` because this is the room's music, not a UI sound: it must
    /// survive the ringer switch and keep going with the screen locked, which
    /// is the normal state of a tablet on a shelf behind a bar.
    ///
    /// Deliberately NOT `.mixWithOthers`. Mixing is what Windows does by
    /// default and is exactly the behaviour being removed — the room playing
    /// underneath a video instead of yielding to it.
    private func configureSession() {
        try? session.setCategory(.playback, mode: .default, options: [])
    }

    private func observe() {
        let centre = NotificationCenter.default
        centre.addObserver(
            self,
            selector: #selector(onInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: session
        )
        centre.addObserver(
            self,
            selector: #selector(onSecondaryAudioHint(_:)),
            name: AVAudioSession.silenceSecondaryAudioHintNotification,
            object: session
        )
    }

    // MARK: - Dart -> platform

    private func handle(_ call: FlutterMethodCall, _ result: FlutterResult) {
        switch call.method {
        case "requestFocus":
            // Activating IS the request on iOS: it fails when something else
            // holds the session exclusively.
            do {
                try session.setActive(true)
                result(true)
            } catch {
                result(false)
            }
        case "abandonFocus":
            // notifyOthersOnDeactivation so whatever ducked for us can come
            // back up immediately rather than after a timeout.
            try? session.setActive(false, options: [.notifyOthersOnDeactivation])
            result(nil)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - Platform -> Dart

    @objc private func onInterruption(_ note: Notification) {
        guard
            let info = note.userInfo,
            let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
            let type = AVAudioSession.InterruptionType(rawValue: raw)
        else { return }

        switch type {
        case .began:
            notify(true)
        case .ended:
            let rawOptions =
                info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            let options = AVAudioSession.InterruptionOptions(rawValue: rawOptions)
            if options.contains(.shouldResume) {
                notify(false)
            } else {
                // The system is not inviting us back. Ask the session instead
                // of assuming either way: it activates only if the speakers are
                // genuinely free. See the class note on why a venue probes here
                // where a music player would simply stay stopped.
                notify(!canReactivate())
            }
        @unknown default:
            break
        }
    }

    /// Another app started or stopped its own playback beside ours.
    ///
    /// `.begin` means "silence your secondary audio", `.end` means it is over.
    /// This is the signal that covers somebody opening a video on the same
    /// tablet, which never raises an interruption.
    @objc private func onSecondaryAudioHint(_ note: Notification) {
        guard
            let raw = note.userInfo?[AVAudioSessionSilenceSecondaryAudioHintTypeKey]
                as? UInt,
            let type = AVAudioSession.SilenceSecondaryAudioHintType(rawValue: raw)
        else { return }
        notify(type == .begin)
    }

    private func canReactivate() -> Bool {
        do {
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    /// Only on a change: the app handles repeats harmlessly — silence and
    /// resume are both idempotent — but the two notifications above overlap,
    /// and a call ending can raise both.
    private func notify(_ playing: Bool) {
        guard playing != lastReported else { return }
        lastReported = playing
        // Notifications already arrive on the main thread, which is the
        // platform thread; the hop is kept explicit because a channel touched
        // from anywhere else is a race that hides rather than crashes.
        DispatchQueue.main.async { [weak self] in
            self?.channel.invokeMethod("externalAudioChanged", arguments: playing)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
}
