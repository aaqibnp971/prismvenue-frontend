import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_venue_repo.dart';
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
  Future<void> addVenue({
    required String name,
    required String address,
    required List<String> zoneNames,
  });

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
