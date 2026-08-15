/// Keeps the sound engine in step with what the app believes the room is doing.
///
/// ## Why this listens to state instead of being called from the mood button
///
/// The obvious wiring — mood tile `onTap` also calls the engine — is wrong,
/// because a tap is not the only thing that changes the mood. The weekly
/// schedule changes it. Another manager on another iPad changes it. Self-drive
/// changes it. The backend is the source of truth and the app already streams
/// it through [nowPlayingProvider].
///
/// So the engine follows that stream. Every path that can change the room —
/// including ones that do not exist yet — reaches the audio for free, and the
/// speakers can never disagree with the dashboard.
///
/// The same applies to silence: takeover and pause are states, not events, so
/// this reacts to [takeoverStateProvider] and `PlaybackState.paused` rather
/// than to the buttons that set them.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/local_playback.dart';
import '../app/session.dart';
import '../data/models/guardrails.dart';
import '../data/models/playback_state.dart';
import '../data/models/takeover_state.dart';
import '../data/models/user.dart';
import '../data/models/weather.dart';
import '../data/repositories/playback_repo.dart';
import '../data/repositories/settings_repo.dart';
import '../data/repositories/weather_repo.dart';
import 'audio_focus.dart';
import 'prism_engine.dart';
import 'weather_influence.dart';

/// The engine instance. Created once and disposed with the container.
final prismEngineProvider = Provider<PrismEngine>((ref) {
  final engine = PrismEngine();
  ref.onDispose(engine.dispose);
  return engine;
});

/// Live engine status, for surfacing "why is there no sound" in the UI.
final engineStatusProvider = StreamProvider<EngineStatus>((ref) {
  final engine = ref.watch(prismEngineProvider);
  return engine.statusChanges;
});

/// Prism's own output level, 0–100, polled for the Floor hero's meter. Null
/// while nothing is playing.
///
/// **Polled, not pushed.** The level changes every audio block — thousands of
/// times a second — and a stream of that would be pure waste for something a
/// human reads a few times a second. 10 Hz is faster than the eye needs and
/// costs one atomic load per tick.
///
/// `autoDispose` so the timer stops the moment the Floor screen is gone; there
/// is nowhere else that renders this.
///
/// It reports what the ENGINE is emitting, which is why it is scaled from
/// dBFS rather than linearly — see [_levelToPercent].
final engineOutputLevelProvider = StreamProvider.autoDispose<int?>((ref) {
  final engine = ref.watch(prismEngineProvider);
  return Stream<int?>.periodic(
    const Duration(milliseconds: 100),
    (_) {
      final level = engine.outputLevel;
      return level == null ? null : _levelToPercent(level);
    },
  ).distinct();
});

/// Linear RMS → a percentage a human can read.
///
/// Straight `rms * 100` would be useless: hearing is logarithmic, and the
/// engine's own numbers make that concrete — `amp = 0.4·x^1.5` with a 0.7
/// master and a −3 dBFS ceiling puts ordinary playback around −20 dBFS, which
/// is a linear amplitude of about 0.1. Every mood would sit in the bottom
/// tenth of the bar and the meter would look broken.
///
/// So this maps −60 dBFS → 0% and 0 dBFS → 100%, which puts typical playback
/// near two thirds and leaves visible travel both ways.
int _levelToPercent(double rms) {
  if (rms <= 0) return 0;
  const floorDb = -60.0;
  final db = 20 * (math.log(rms) / math.ln10);
  final pct = ((db - floorDb) / -floorDb) * 100;
  return pct.clamp(0, 100).round();
}

/// Drives the engine from app state. Watched once, near the app root.
final engineControllerProvider = Provider<EngineController>((ref) {
  final controller = EngineController(ref);
  ref.onDispose(controller.dispose);
  controller._attach();
  return controller;
});

class EngineController {
  EngineController(this._ref);

  final Ref _ref;
  final _subscriptions = <ProviderSubscription<Object?>>[];

  bool _started = false;

  // The four independent reasons the room may be silent. See _syncAudible.
  bool _takeoverActive = false;
  bool _paused = false;
  bool _externalAudio = false;

  PrismEngine get _engine => _ref.read(prismEngineProvider);

  void _attach() {
    // fireImmediately so a mood already playing when the app opens is picked
    // up, rather than waiting for the next change.
    _subscriptions.add(
      _ref.listen<AsyncValue<PlaybackState>>(
        nowPlayingProvider,
        (_, next) => _onPlayback(next.value),
        fireImmediately: true,
      ),
    );
    _subscriptions.add(
      _ref.listen<AsyncValue<TakeoverState>>(
        takeoverStateProvider,
        (_, next) => _onTakeover(next.value),
        fireImmediately: true,
      ),
    );
    // Sign-out. The engine follows state, and "nobody is signed in" is a state
    // in which Prism has no business driving a room.
    //
    // Nothing else here can notice it. Every other stream is zone-scoped, and
    // signing out clears the zone, so they start THROWING `no_zone_selected`
    // rather than emitting — `next.value` is null, `_onPlayback` returns early,
    // and the last mood plays on over the sign-in screen until the process
    // ends. On a shared venue iPad that is the next person's room, still
    // running on the last person's session.
    _subscriptions.add(
      _ref.listen<User?>(
        sessionProvider,
        (_, next) => _onSession(next),
        fireImmediately: true,
      ),
    );
    // The venue's volume policy. Watched rather than read at mood-change time:
    // a manager dragging the band expects the room to follow now, not at the
    // next mood. See app/engine seam and S05-2.
    _subscriptions.add(
      _ref.listen<AsyncValue<Guardrails>>(
        guardrailsProvider,
        (_, next) => _onGuardrails(next),
        fireImmediately: true,
      ),
    );
    // Something else on this machine using the speakers. A state like the
    // others, and followed the same way — see engine/audio_focus.dart for why
    // Windows has to be told this rather than being asked.
    _subscriptions.add(
      _ref.listen<AsyncValue<bool>>(
        externalAudioProvider,
        (_, next) => _onExternalAudio(next.value ?? false),
        fireImmediately: true,
      ),
    );
    // Weather is a state, like the other two, so it is followed the same way
    // rather than being fetched at the point of a mood change. That matters:
    // the sky moves while the mood stands still, and a room left on Peak all
    // evening should still darken as the light goes.
    //
    // `weatherProvider` is scoped to the session's venue, so "Open floor" on a
    // room in another city repoints this along with everything else.
    _subscriptions.add(
      _ref.listen<AsyncValue<WeatherReading?>>(
        weatherProvider,
        (_, next) => _onWeather(next.value),
        fireImmediately: true,
      ),
    );
  }

  /// The last ceiling actually pushed to the engine; null before the first.
  int? _appliedVolumeMax;

  /// Applies S05-2's ceiling to the engine.
  ///
  /// The seed default covers the window before the first value arrives — the
  /// router and the transition setting use the same fallback, and the seed is
  /// full output, so a slow first fetch cannot leave a room silent.
  ///
  /// After that the last applied ceiling is **held** rather than re-defaulted.
  /// An empty `AsyncValue` means loading or error, not "no policy", and reading
  /// it as one pushed the room to 70% every time the stream hiccuped — loudest
  /// exactly where a manager had deliberately set a low ceiling. Signing out
  /// made `guardrailsProvider` throw `no_zone_selected`, so it happened on
  /// every sign-out. A volume guardrail must not fail upward.
  Future<void> _onGuardrails(AsyncValue<Guardrails> next) =>
      _applyCeiling(next.value);

  Future<void> _applyCeiling(Guardrails? guardrails) async {
    if (!_signedIn) return;
    if (guardrails == null && _appliedVolumeMax != null) return;
    final ceiling = (guardrails ?? const Guardrails()).volumeMax;
    if (ceiling == _appliedVolumeMax) return;
    _appliedVolumeMax = ceiling;
    await _engine.setVolumePolicy(ceiling);
  }

  bool _signedIn = false;

  /// Starts and stops the room with the session.
  ///
  /// Signing in replays the current playback state rather than waiting for the
  /// next emission. The order in `AuthController._apply` is context first, user
  /// last, so a zone-scoped stream can well have emitted while [_signedIn] was
  /// still false — and that emission was ignored on purpose. Without the replay
  /// the room would stay silent until something else happened to change.
  Future<void> _onSession(User? user) async {
    final signedIn = user != null;
    if (signedIn == _signedIn) return;
    _signedIn = signedIn;
    if (signedIn) {
      await _onPlayback(_ref.read(nowPlayingProvider).value);
      return;
    }

    await _engine.silence();
    // Prism has stopped driving, so it can vouch for no room being reachable.
    _ref.read(playedZonesProvider.notifier).clear();
    // The ceiling is deliberately NOT cleared. The engine is silent, so it
    // changes nothing now, and holding the last real number is a better guess
    // for the gap before the next account's guardrails land than resetting to
    // full output would be. _onPlayback applies the real one before it resumes.
  }

  /// Folds the venue's sky into the pinned PSV.
  ///
  /// A null reading — no address, no network, an API that is down — maps to
  /// [PsvNudge.none], which is bit-identical to pinning the preset alone. So
  /// losing the weather returns the room to its plain mood instead of freezing
  /// it on the last sky that was seen.
  Future<void> _onWeather(WeatherReading? reading) =>
      _engine.applyInfluence(nudgeFor(reading));

  Future<void> _onPlayback(PlaybackState? state) async {
    if (state == null) return;
    // Nobody is signed in, so nothing may reach the speakers — whatever a
    // stream says. The guard belongs here rather than only on the sign-out
    // path because these streams do not reliably stop: they are zone-scoped
    // and the API ones start throwing, but a late or cached emission arriving
    // after sign-out would otherwise resume the room over the sign-in screen.
    if (!_signedIn) return;

    // Start lazily rather than at app launch: extracting stems and opening an
    // audio device is wasted work for a manager who only came in to edit the
    // schedule, and on iOS it would take the audio session for no reason.
    if (!_started) {
      _started = true;
      await _engine.start();
    }

    // How slowly the room eases between vibes is a venue setting (S05-3), so it
    // is read here rather than baked into the engine. `read`, not `listen`: the
    // value matters at the moment a mood changes, and a guardrails edit should
    // not by itself retrigger a transition.
    final guardrails =
        _ref.read(guardrailsProvider).value ?? const Guardrails();
    await _engine.setMood(
      state.moodId,
      transition: guardrails.transitionDuration,
      alignToBar: guardrails.transitionAlignsToBar,
    );

    _paused = state.paused;
    await _syncAudible();
  }

  Future<void> _onTakeover(TakeoverState? state) async {
    final active = state?.active ?? false;
    if (active == _takeoverActive) return;
    _takeoverActive = active;
    // Tracked either way — the flag still has to be right for the next
    // sign-in — but a takeover ending while signed out must not un-silence.
    if (!_signedIn) return;
    await _syncAudible();
  }

  /// Another program on this machine is using the speakers.
  ///
  /// Prism gets out of the way for the same reason it does during a takeover:
  /// it is not the only thing that can own the room, and playing underneath a
  /// video is worse than not playing at all. It comes back on its own when the
  /// other sound stops — a venue is not somewhere anyone will remember to press
  /// play again.
  Future<void> _onExternalAudio(bool playing) async {
    if (playing == _externalAudio) return;
    _externalAudio = playing;
    if (!_signedIn) return;
    await _syncAudible();
  }

  /// Brings the engine into line with every reason the room might be silent.
  ///
  /// There are four, they are independent, and they arrive on four different
  /// streams: nobody signed in, paused, staff have taken over, something else
  /// is using the speakers. Each used to resume or silence directly, which
  /// meant every new reason had to be repeated in every existing branch — and
  /// the branches had already drifted (ending a takeover re-read `paused` from
  /// a provider; nothing re-read anything else). One predicate, one place.
  ///
  /// Both engine calls are idempotent, so being called on a change that turns
  /// out not to move the outcome costs nothing.
  Future<void> _syncAudible() async {
    if (!_audible) {
      await _engine.silence();
      // Prism is not driving, so it can vouch for no room being reachable.
      // See app/local_playback.dart.
      _ref.read(playedZonesProvider.notifier).clear();
      return;
    }

    // Before the room is audible again, not after. On a zone change the
    // guardrails and now-playing fetches race, and resuming first would let a
    // room play a moment at the previous zone's ceiling.
    await _applyCeiling(_ref.read(guardrailsProvider).value);
    await _engine.resume();
    // Recorded only once the room is actually being driven — a mood set while
    // paused or taken over proves nothing about reachability.
    final zoneId = _ref.read(currentZoneIdProvider);
    if (zoneId != null) {
      _ref.read(playedZonesProvider.notifier).remember(zoneId);
    }
  }

  bool get _audible =>
      _signedIn && !_paused && !_takeoverActive && !_externalAudio;

  void dispose() {
    for (final s in _subscriptions) {
      s.close();
    }
    _subscriptions.clear();
  }
}
