import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';
import '../mock/mock_playback_repo.dart';
import '../models/playback_state.dart';
import '../models/takeover_state.dart';
import '../models/zone_activity.dart';

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

  /// Claim or release this device as the room's player (finding #2).
  ///
  /// Returns the installation holding the room afterwards, which is not
  /// necessarily this one: two tablets can race for a room, and the loser must
  /// be told at once rather than going on believing it is playing.
  Future<String?> setThisDevicePlays(bool play);

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

  /// Recent changes to a room, newest first — finding #15.
  ///
  /// Takes a zone id, unlike every other method here, and that is not an
  /// oversight: the zone-detail screen shows a room the session is not
  /// necessarily operating, so resolving the zone from [ApiScope] would answer
  /// about a different room than the one on screen.
  ///
  /// A future rather than a stream. This is a "what just happened" panel that
  /// somebody opens, reads and closes — a live subscription would cost a
  /// refetch on every mood change in a room nobody is watching, to redraw a
  /// list nobody is looking at.
  Future<List<ZoneActivityEntry>> activityFor(String zoneId);
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


/// Finding #15's "Recent activity" panel.
///
/// `autoDispose` and family-keyed: opened per zone, and dropped the moment the
/// screen goes away. Refetched on every open rather than kept warm — a log
/// read once a week is not worth a cache that can go stale.
final zoneActivityProvider = FutureProvider.autoDispose
    .family<List<ZoneActivityEntry>, String>((ref, zoneId) {
  return ref.watch(playbackRepoProvider).activityFor(zoneId);
});
