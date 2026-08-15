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
/// The app can disprove `offline` for exactly one zone: the one it is
/// operating, while its own engine reports [EngineStatus.playing]. That is
/// first-hand evidence — audio is leaving this machine for that room.
///
/// It says nothing about any other zone, and this deliberately does not guess
/// about them. A venue on another iPad may well be genuinely unreachable, and
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

/// The zone this app is itself rendering audio for, and what its status
/// actually is — or null when the engine is not playing.
///
/// The status is derived rather than assumed: `PlaybackState.offSchedule` is
/// the server's own answer to "is a human holding this room", and it is the
/// thing `offline` was masking. So a room the app is playing under a manual
/// mood pin correctly stays amber rather than being flattened to a quiet green
/// row.
final locallyPlayingZoneProvider =
    Provider<({String zoneId, ZoneStatus status})?>((ref) {
  // `statusChanges` only emits on CHANGE, so a listener that arrives after the
  // engine started playing would see nothing at all. The plain getter supplies
  // the current value; watching the stream is what keeps this rebuilding.
  final status = ref.watch(engineStatusProvider).value ??
      ref.watch(prismEngineProvider).status;
  if (status != EngineStatus.playing) return null;

  final zoneId = ref.watch(currentZoneIdProvider);
  if (zoneId == null) return null;

  final now = ref.watch(nowPlayingProvider).value;
  if (now == null) return null;

  return (
    zoneId: zoneId,
    status: now.offSchedule ? ZoneStatus.offSchedule : ZoneStatus.auto,
  );
});

/// [venue] with the locally-playing zone's status corrected.
///
/// Applied to the whole `Venue` rather than at each widget that renders a
/// status, so `worstStatus`, the portfolio's needs-attention sort, the row's
/// sub line and its quick-fix all read the same corrected value. Patching them
/// one by one is how a row ends up amber with a green dot.
///
/// Returns the same instance when there is nothing to correct, so this is free
/// to call on every build.
Venue withLocalPlayback(
  Venue venue,
  ({String zoneId, ZoneStatus status})? local,
) {
  if (local == null) return venue;

  final needsFix = venue.zones.any(
      (z) => z.id == local.zoneId && z.status == ZoneStatus.offline);
  if (!needsFix) return venue;

  return venue.copyWith(zones: [
    for (final zone in venue.zones)
      if (zone.id == local.zoneId)
        Zone(
          id: zone.id,
          name: zone.name,
          status: local.status,
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
ZoneStatus statusOf(Zone zone, ({String zoneId, ZoneStatus status})? local) =>
    (local != null && local.zoneId == zone.id) ? local.status : zone.status;
