import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';
import '../mock/mock_playback_repo.dart';
import '../models/playback_state.dart';
import '../models/takeover_state.dart';

/// Now-playing boundary — §5: PlaybackRepo streams now-playing/noise so the
/// eventual FastAPI + MQTT backend slots in behind the same interface.
abstract class PlaybackRepo {
  /// Emits the current state immediately, then every change.
  Stream<PlaybackState> watchNowPlaying();

  /// Noise % (0–100). Mock ticks so the app looks alive (§5).
  Stream<int> watchNoise();

  /// S01-3 confirm → switch the vibe.
  Future<void> setMood(String moodId);

  /// S01-2: staff paused the room.
  Future<void> pause({required String by});

  Future<void> resume();

  /// Hands the room back to the schedule / self-drive after a manual override,
  /// clearing [PlaybackState.offSchedule]. Idempotent server-side.
  ///
  /// Lives here rather than on `VenueRepo.returnZoneToAuto` — which does the
  /// same thing for a zone row — because the flag that gates the Floor control
  /// rides on [PlaybackState], and only the playback repo can refresh the
  /// now-playing stream that carries it. Doing it through VenueRepo would leave
  /// the hero showing an override the server had already cleared. PlaybackRepo
  /// already owns the other hand-the-room-back verb, [endTakeover].
  Future<void> returnToAuto();

  // ---- Takeover (§2 S02) ----

  /// Emits the current takeover state immediately, then every second while
  /// active (the countdown ticks here so UI and auto-return share one clock).
  Stream<TakeoverState> watchTakeover();

  /// S02-1 CTA: hand the speakers to staff audio; Prism returns
  /// automatically after [handBackAfter].
  Future<void> startTakeover({required Duration handBackAfter});

  /// S02-4: extend ADDS the chosen duration (§6-A7).
  Future<void> extendTakeover(Duration by);

  /// S02-4 "Remove auto-return instead": clears the deadline — Prism waits
  /// until staff hand the room back themselves. The takeover stays active
  /// and [endTakeover] still works; only the countdown stops existing.
  Future<void> removeAutoReturn();

  /// S02-3 confirm (or countdown reaching zero): Prism takes the room back.
  Future<void> endTakeover();
}

/// The mock is handed the same zone resolver `ApiScope` gives the API repo, so
/// on mocks two rooms hold two moods exactly as they do against the backend.
/// `ref.read` inside the closure rather than `ref.watch` at build time: the
/// scope is resolved per call, so changing the session's zone takes effect
/// without rebuilding the repository (and without dropping its state).
final playbackRepoProvider = Provider<PlaybackRepo>((ref) {
  final repo = MockPlaybackRepo(zoneId: () => ref.read(currentZoneIdProvider));
  ref.onDispose(repo.dispose);
  return repo;
});

/// §5 State: nowPlayingProvider (Stream, mock ticks).
///
/// Each watches the current zone so it resubscribes once sign-in establishes
/// one — a stream started before then has no zone to fetch for.
final nowPlayingProvider = StreamProvider.autoDispose<PlaybackState>((ref) {
  ref.watch(currentZoneIdProvider);
  return ref.watch(playbackRepoProvider).watchNowPlaying();
});

final noiseProvider = StreamProvider.autoDispose<int>((ref) {
  ref.watch(currentZoneIdProvider);
  return ref.watch(playbackRepoProvider).watchNoise();
});

final takeoverStateProvider = StreamProvider.autoDispose<TakeoverState>((ref) {
  ref.watch(currentZoneIdProvider);
  return ref.watch(playbackRepoProvider).watchTakeover();
});

/// §5 State: takeoverCountdownProvider — the ticking remaining time.
final takeoverCountdownProvider = Provider.autoDispose<Duration>((ref) =>
    ref.watch(takeoverStateProvider).value?.remaining ?? Duration.zero);
