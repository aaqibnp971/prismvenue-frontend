import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_venue_repo.dart';
import '../models/timezone.dart';
import '../models/venue.dart';

/// Venue/estate boundary — §2 S04. Async/stream-shaped for the future
/// backend (§C).
abstract class VenueRepo {
  /// The owner's portfolio, sorted "Needs attention" first (S04-2).
  Stream<List<Venue>> watchVenues();

  Stream<Venue?> watchVenue(String id);

  /// S04-1/2 quick-fix: puts an off-schedule zone back on auto.
  Future<void> returnZoneToAuto(String venueId, String zoneId);

  /// S04-3 "Add venue" — zones from the S04-4 sheet, by name.
  ///
  /// [deviceOffsets] is how the new venue gets a clock. Nothing in the app or
  /// the API carries a default zone to fall back on, so without it the column
  /// default stands — which is how every venue ended up on one arbitrary zone,
  /// and why a schedule typed in India fired on Gulf time.
  Future<void> addVenue({
    required String name,
    required String address,
    required List<String> zoneNames,
    DeviceOffsets? deviceOffsets,
  });

  /// Every zone the server knows, for the picker. Fetched rather than bundled:
  /// the tz database changes, and a list compiled into the app goes stale.
  Future<List<TimezoneOption>> listTimezones();

  /// S05 "Time zone" — which clock this venue's schedule runs on.
  Future<void> setTimezone(String venueId, String timezone);

  /// Add a zone to an existing venue — the other half of [removeZone].
  ///
  /// Zones used to be creatable only as part of [addVenue], which made
  /// "Remove zone" a one-way door: a venue whose last zone was removed had no
  /// zone-scoped screen left and no way to get one back, because `ApiScope`
  /// throws `no_zone_selected` on every one of them. An owner looking at a
  /// "0 zones" row in the portfolio had nothing they could do about it.
  ///
  /// Throws on a duplicate name for the same reason [renameZone] does — the
  /// value lands in the same column, under the same unique constraint.
  Future<void> addZone(String venueId, String name);

  /// S05-5's zone name field.
  ///
  /// The field shipped fully interactive with no save affordance and no write
  /// path, so every edit was silently discarded on navigate-back.
  /// `open_questions.md` #24 recorded the missing affordance; an editable field
  /// that throws away input is a defect whatever the frame omitted.
  ///
  /// Throws on a duplicate name — `zones` has unique (venue_id, name) — so the
  /// screen can say which constraint was hit rather than reverting silently.
  Future<void> renameZone(String zoneId, String name);

  /// S05-5 "Remove zone".
  Future<void> removeZone(String zoneId);
}

final venueRepoProvider = Provider<VenueRepo>((ref) {
  final repo = MockVenueRepo();
  ref.onDispose(repo.dispose);
  return repo;
});

final venuesProvider = StreamProvider.autoDispose<List<Venue>>(
    (ref) => ref.watch(venueRepoProvider).watchVenues());

final venueProvider = StreamProvider.autoDispose.family<Venue?, String>(
    (ref, id) => ref.watch(venueRepoProvider).watchVenue(id));
