/// What this app knows about the room, which the server does not.
///
/// ## The problem
///
/// `ZoneStatus.offline` means "no device has reported itself online" —
/// `zoneStatus()` in the backend derives it from `devices.online`, and offline
/// wins over everything else because "nothing to fix remotely" is the more
/// useful thing to tell someone.
///
/// But **there is no telemetry ingest**. Nothing anywhere writes
/// `devices.online` or any `reported_*` column, so that flag is frozen at
/// whatever a seed happened to set. A zone with no `devices` row at all reads
/// offline forever, by way of `coalesce(bool_or(online), false)`.
///
/// Meanwhile this app IS the player: `engine_controller.dart` follows
/// `nowPlayingProvider` and renders the mood through prism-core on this
/// machine's own speakers. So the portfolio could sit there labelling a room
/// "Offline" in red while the very same process was audibly playing Evening
/// warmth into it. The dashboard contradicting the speakers is precisely what
/// the engine seam exists to prevent.
///
/// ## The correction, and its limits
///
/// The app can disprove `offline` for any zone it has actually driven audio
/// into this run, for as long as it is still driving audio at all. That is
/// first-hand evidence: sound left this machine for that room.
///
/// It is a LATCH, not a live reading, and that is deliberate. Correcting only
/// the room in hand meant that switching zones flipped the one you had just
/// been listening to straight back to a red "Offline" — alarming, and wrong,
/// because navigating away does not un-prove that a room exists. So the
/// evidence persists while Prism is playing and expires the moment it is not:
/// paused, taken over, failed, or web where there is no engine at all.
///
/// The room in hand keeps its precise status; a room played earlier this run
/// reads quiet and nothing more. Reachability is all that was proven, and
/// whether a human has since overridden it is a question only the server can
/// answer — which it cannot, because `offline` masked it.
///
/// It says nothing about zones this app has never played, and deliberately does
/// not guess. A venue on another iPad may well be genuinely unreachable, and
/// quietly turning every red row green would replace one wrong answer with a
/// more confident wrong answer.
///
/// It is also **not** written back to the server. `reported_*` belongs to
/// telemetry ingest, `prism_api` has no column grant for it (migration 003),
/// and a client asserting its own liveness into a device table would be the
/// wrong shape for that seam. This is a presentation-layer correction, and it
/// disappears the moment real ingest lands and starts writing the truth.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/venue.dart';
import '../data/models/zone.dart';
import '../data/repositories/playback_repo.dart';
import '../engine/engine_controller.dart';
import '../engine/prism_engine.dart';
import 'session.dart';

/// Zones this app has actually driven audio into during this run.
///
/// The latch behind [localPlaybackProvider]. Playing a room is proof it exists
/// and that this machine can reach it; navigating to a different room does not
/// un-prove that. Without this, switching zones flipped the room you had just
/// been listening to straight back to a red "Offline", which is both alarming
/// and wrong.
///
/// Deliberately per-RUN and in memory. It is evidence this process gathered
/// itself, so it must not outlive the process — persisting it would mean
/// asserting reachability on next launch that nothing had re-established.
final playedZonesProvider =
    NotifierProvider<PlayedZones, Set<String>>(PlayedZones.new);

class PlayedZones extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void remember(String zoneId) {
    if (state.contains(zoneId)) return;
    state = {...state, zoneId};
  }

  /// Called when Prism stops driving audio at all — pause, takeover, failure.
  /// The evidence is about a running player, so it expires with one.
  void clear() {
    if (state.isEmpty) return;
    state = const {};
  }
}

/// What this app can vouch for right now, or null when it is not playing.
class LocalPlayback {
  const LocalPlayback({
    required this.reachable,
    required this.currentZoneId,
    required this.currentStatus,
  });

  /// Every zone driven this run, including the current one.
  final Set<String> reachable;

  /// The room being operated, whose status is known precisely.
  final String? currentZoneId;

  /// [currentZoneId]'s real status, derived from `PlaybackState.offSchedule` —
  /// the thing `offline` was masking.
  final ZoneStatus currentStatus;

  /// The status this app can substantiate for [zoneId], or null if it cannot.
  ///
  /// The room in hand gets its precise status. A room played earlier this run
  /// gets [ZoneStatus.auto] and nothing more: reachability is all that was
  /// proven, and whether a human has since overridden it is a question only the
  /// server can answer — which it cannot, because `offline` masked it. Quiet is
  /// the honest reading of "reachable, nothing else known".
  ZoneStatus? statusFor(String zoneId) {
    if (zoneId == currentZoneId) return currentStatus;
    return reachable.contains(zoneId) ? ZoneStatus.auto : null;
  }
}

final localPlaybackProvider = Provider<LocalPlayback?>((ref) {
  // `statusChanges` only emits on CHANGE, so a listener that arrives after the
  // engine started playing would see nothing at all. The plain getter supplies
  // the current value; watching the stream is what keeps this rebuilding.
  final status = ref.watch(engineStatusProvider).value ??
      ref.watch(prismEngineProvider).status;
  // Everything here expires the moment Prism stops driving audio. Paused,
  // taken over, failed or unsupported: the app is no longer the player, so it
  // has nothing left to vouch for and every row falls back to the server.
  if (status != EngineStatus.playing) return null;

  final reachable = ref.watch(playedZonesProvider);
  final zoneId = ref.watch(currentZoneIdProvider);
  final now = ref.watch(nowPlayingProvider).value;
  if (reachable.isEmpty && zoneId == null) return null;

  return LocalPlayback(
    reachable: reachable,
    currentZoneId: zoneId,
    currentStatus: (now?.offSchedule ?? false)
        ? ZoneStatus.offSchedule
        : ZoneStatus.auto,
  );
});

/// [venue] with every zone this app can vouch for corrected.
///
/// Applied to the whole `Venue` rather than at each widget that renders a
/// status, so `worstStatus`, the portfolio's needs-attention sort, the row's
/// sub line and its quick-fix all read the same corrected value. Patching them
/// one by one is how a row ends up amber with a green dot.
///
/// Returns the same instance when there is nothing to correct, so this is free
/// to call on every build.
Venue withLocalPlayback(Venue venue, LocalPlayback? local) {
  if (local == null) return venue;

  final needsFix = venue.zones.any((z) =>
      z.status == ZoneStatus.offline && local.statusFor(z.id) != null);
  if (!needsFix) return venue;

  return venue.copyWith(zones: [
    for (final zone in venue.zones)
      if (zone.status == ZoneStatus.offline && local.statusFor(zone.id) != null)
        Zone(
          id: zone.id,
          name: zone.name,
          status: local.statusFor(zone.id)!,
          moodId: zone.moodId,
          // Dropped, not carried: the detail behind an offline zone is the
          // literal string "Offline", which would otherwise survive onto an
          // amber row as its countdown text. `Zone.copyWith` preserves it for
          // any non-auto status, which is why this builds a Zone directly.
          statusDetail: null,
        )
      else
        zone,
  ]);
}

/// The same correction for a single zone, for screens that render one.
ZoneStatus statusOf(Zone zone, LocalPlayback? local) {
  if (zone.status != ZoneStatus.offline) return zone.status;
  return local?.statusFor(zone.id) ?? zone.status;
}
