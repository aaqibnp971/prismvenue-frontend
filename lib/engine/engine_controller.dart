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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/guardrails.dart';
import '../data/models/playback_state.dart';
import '../data/models/takeover_state.dart';
import '../data/models/weather.dart';
import '../data/repositories/playback_repo.dart';
import '../data/repositories/settings_repo.dart';
import '../data/repositories/weather_repo.dart';
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

    // Start lazily rather than at app launch: extracting stems and opening an
    // audio device is wasted work for a manager who only came in to edit the
    // schedule, and on iOS it would take the audio session for no reason.
    if (!_started) {
      _started = true;
      await _engine.start();
    }

    // How slowly the room eases between vibes is a venue setting (S05-3), so it is
    // read here rather than baked into the engine. `read`, not `listen`: the value
    // matters at the moment a mood changes, and a guardrails edit should not by
    // itself retrigger a transition. The seed default covers the window before the
    // first emission — the router relies on the same fallback.
    final guardrails = _ref.read(guardrailsProvider).value ?? const Guardrails();
    await _engine.setMood(
      state.moodId,
      transition: guardrails.transitionDuration,
      alignToBar: guardrails.transitionAlignsToBar,
    );

    // Pause is a silence with a different label. Takeover is handled separately
    // and wins — see _onTakeover.
    if (state.paused) {
      await _engine.silence();
    } else if (!_takeoverActive) {
      await _engine.resume();
    }
  }

  bool _takeoverActive = false;

  Future<void> _onTakeover(TakeoverState? state) async {
    final active = state?.active ?? false;
    if (active == _takeoverActive) return;
    _takeoverActive = active;

    if (active) {
      // The whole point of takeover: the engine gets out of the way so staff
      // can play their own audio through the same speakers.
      await _engine.silence();
    } else {
      // Only come back if the room is not also paused — otherwise ending a
      // takeover would override a pause nobody cancelled.
      final paused = _ref.read(nowPlayingProvider).value?.paused ?? false;
      if (!paused) await _engine.resume();
    }
  }

  void dispose() {
    for (final s in _subscriptions) {
      s.close();
    }
    _subscriptions.clear();
  }
}
