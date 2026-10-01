import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_last_seen_repo.dart';

/// Tells the server this device is still here, and what it is playing.
///
/// Deliberately called "last seen" rather than "heartbeat". What is recorded is
/// a tablet checking in: which installation, which zone, when, and the mood it
/// is rendering. Nothing here observes a person, and the vocabulary should not
/// suggest otherwise to anyone reading the data map.
///
/// This is the client half of the seam `app/local_playback.dart` was written
/// to work around. Until it existed, nothing in the system ever wrote
/// `devices.last_seen_at` or any `reported_*` column, so "Offline" was frozen
/// at whatever a seed had set and the portfolio could label a room offline in
/// red while this very process was audibly playing into it.
abstract class LastSeenRepo {
  /// Report once for [zoneId].
  ///
  /// Every field but the zone is optional, and null means "no change" rather
  /// than "clear it" — a tablet whose engine failed to load must still be able
  /// to say it is present, because "on but silent" is the state an owner most
  /// needs to see.
  ///
  /// Never throws. A report that does not arrive is not worth interrupting a
  /// venue for; the server simply keeps the previous time and, after three
  /// minutes without one, correctly calls the zone offline.
  Future<void> report({
    required String zoneId,
    String? mode,
    String? moodId,
    int? volumePct,
  });
}

final lastSeenRepoProvider =
    Provider<LastSeenRepo>((ref) => MockLastSeenRepo());
