import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/zone.dart';
import '../data/repositories/venue_repo.dart';
import 'local_playback.dart';
import 'session.dart';

/// The §2.0 top-bar identity: venue name, context line, and the green dot.
///
/// Every screen's top bar used to render `Seed.venueName` and
/// `Seed.venueStatus` — mock constants, hardcoded in ten production screens.
/// Removing the mocks was never going to be enough; this is what replaces them.
///
/// The venue name comes from the session (established at sign-in). The status
/// line needs the current zone's connectivity, which only the venue stream
/// knows, so it degrades in steps rather than guessing:
///
///   venue + zone + status known  → "Main floor · online", dot on
///   venue + zone, status unknown → "Main floor", no dot
///   venue with no zones          → "No zones", no dot
///
/// It never claims "online" it cannot substantiate — a green dot on an offline
/// room is worse than no dot at all.
typedef VenueHeader = ({String title, String subtitle, bool statusDot});

final venueHeaderProvider = Provider.autoDispose<VenueHeader>((ref) {
  final context = ref.watch(sessionContextProvider);
  if (context == null) {
    return (title: '', subtitle: '', statusDot: false);
  }

  final zoneName = context.zoneName;
  if (zoneName == null) {
    // Reachable by removing a venue's last zone (S05-5).
    return (title: context.venueName, subtitle: 'No zones', statusDot: false);
  }

  final zone = ref
      .watch(venuesProvider)
      .value
      ?.where((v) => v.id == context.venueId)
      .expand((v) => v.zones)
      .where((z) => z.id == context.zoneId)
      .firstOrNull;

  if (zone == null) {
    return (title: context.venueName, subtitle: zoneName, statusDot: false);
  }

  // The same correction the portfolio applies: a room this app is itself
  // playing cannot honestly be labelled offline in the very chrome above the
  // hero card that is showing its mood. See app/local_playback.dart.
  final online =
      statusOf(zone, ref.watch(locallyPlayingZoneProvider)) != ZoneStatus.offline;
  return (
    title: context.venueName,
    subtitle: '$zoneName · ${online ? 'online' : 'offline'}',
    statusDot: online,
  );
});

/// Just the venue name — for sub-screens whose context line is fixed copy
/// ("Settings · Sound", "Open hours") rather than zone status.
final venueNameProvider = Provider.autoDispose<String>(
    (ref) => ref.watch(sessionContextProvider)?.venueName ?? '');
