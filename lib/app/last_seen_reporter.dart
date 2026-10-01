/// Tells the server, on a timer, that this tablet is still here.
///
/// ## Why the app has to be the one to say it
///
/// Nothing else can. The venue device is the only thing that knows whether it
/// is switched on, signed in, and rendering audio into a room; the server only
/// ever knew what a room was *asked* to play. That gap is why every zone read
/// "Offline", why `in_sync` was false everywhere, and why `local_playback.dart`
/// had to correct the portfolio from inside the app rather than from data.
///
/// ## What it reports, and what it refuses to report
///
/// Presence is reported whenever somebody is signed in and a zone is in
/// context — **not** only while audio is playing. A tablet that is on, with the
/// app open and the room paused, is a completely different situation from a
/// tablet that is off, and an owner needs to be able to tell them apart.
///
/// The mood and volume are reported only when this app is actually driving the
/// room ([playedZonesProvider] is the same first-hand evidence
/// `local_playback.dart` uses). Anything else would be reporting what the room
/// was told to play back to the server that told it.
///
/// `mode` is sent only for the two states the device can vouch for: paused and
/// taken over. It is left out while playing, because "auto" versus "manual" is
/// a fact about the server's desired state, not about this device, and the
/// column it lands in should not be filled with a guess. The server coalesces a
/// missing field to whatever was last reported.
///
/// ## Timing
///
/// Every 60 seconds, and immediately whenever the operated zone changes so a
/// room does not sit "Offline" for a minute after somebody opens it. The
/// server's window is three minutes, which tolerates one missed report plus
/// jitter before a room is honestly called offline.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/guardrails.dart';
import '../data/repositories/last_seen_repo.dart';
import '../data/repositories/playback_repo.dart';
import '../data/repositories/settings_repo.dart';
import '../engine/engine_controller.dart';
import '../engine/prism_engine.dart';
import 'local_playback.dart';
import 'session.dart';

/// How often a present device reports. Paired with the server's three-minute
/// freshness window in migration 015 — change one and the other needs thought.
const lastSeenInterval = Duration(seconds: 60);

/// Held for the life of the app, like [engineControllerProvider].
///
/// Constructed here but **not started** here. `start()` is called by `main()`,
/// because starting a repeating timer is a side effect of the app running, not
/// of a provider being read — and a widget test that pumps the app would
/// otherwise fail on a pending 60-second timer it never asked for.
final lastSeenReporterProvider = Provider<LastSeenReporter>((ref) {
  final reporter = LastSeenReporter(ref);
  ref.onDispose(reporter.dispose);
  return reporter;
});

class LastSeenReporter {
  LastSeenReporter(this._ref, {Duration interval = lastSeenInterval})
      : _interval = interval;

  final Ref _ref;
  final Duration _interval;
  final _subscriptions = <ProviderSubscription<Object?>>[];
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(_interval, (_) => unawaited(reportNow()));
    // Report the moment the operated room changes, rather than up to a minute
    // later. "Open floor" on a zone should turn it online promptly, because
    // that is exactly when somebody is looking at it.
    _subscriptions.add(
      _ref.listen<String?>(
        currentZoneIdProvider,
        (previous, next) {
          if (next != null && next != previous) unawaited(reportNow());
        },
        fireImmediately: true,
      ),
    );
  }

  /// One report for the zone in hand. Safe to call at any time.
  Future<void> reportNow() async {
    // Signed out is not "offline" — it is nobody's room to report on, and a
    // shared venue iPad may be sitting on the sign-in screen between shifts.
    if (_ref.read(sessionProvider) == null) return;
    final zoneId = _ref.read(currentZoneIdProvider);
    if (zoneId == null) return;

    final playing = _ref.read(playedZonesProvider).contains(zoneId) &&
        _ref.read(prismEngineProvider).status == EngineStatus.playing;

    final now = _ref.read(nowPlayingProvider).value;
    final takeover = _ref.read(takeoverStateProvider).value?.active ?? false;

    await _ref.read(lastSeenRepoProvider).report(
          zoneId: zoneId,
          mode: takeover
              ? 'takeover'
              : (now?.paused ?? false)
                  ? 'paused'
                  : null,
          // Only what this device is actually rendering. See the library note.
          moodId: playing ? now?.moodId : null,
          volumePct: playing
              ? (_ref.read(guardrailsProvider).value ?? const Guardrails())
                  .volumeMax
              : null,
        );
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    for (final s in _subscriptions) {
      s.close();
    }
    _subscriptions.clear();
  }
}
