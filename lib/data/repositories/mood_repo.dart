import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';
import '../../theme/moods.dart';
import '../mock/mock_mood_repo.dart';
import 'playback_repo.dart';

/// The mood catalogue boundary.
///
/// Two reads, and they answer different questions:
///
///   * [watchCatalogue] — every mood this account may see. The id → mood
///     lookup. An owner's portfolio shows rooms from more than one mood set on
///     one screen, so a lookup limited to the room in hand would leave the
///     others nameless.
///   * [watchZoneMoods] — what the room in hand OFFERS: the moods of its own
///     set, in display order. The Floor grid and the schedule editor draw
///     exactly this list. A mood from another zone's set is not a choice, and
///     the database refuses it if sent (migration 023).
abstract class MoodRepo {
  Stream<List<Mood>> watchCatalogue();

  Stream<List<Mood>> watchZoneMoods();
}

final moodRepoProvider = Provider<MoodRepo>((ref) => const MockMoodRepo());

/// Loads the catalogue and keeps [MoodCatalog] filled from it.
///
/// Screens that draw a mood by id watch this — not for its value, which they
/// read through `moodById`, but so they rebuild when a mood they showed as
/// unknown becomes known.
///
/// Not `autoDispose`: the lookup is needed by whatever screen comes next, and
/// dropping the subscription between two routes would refetch on every
/// navigation for a list that changes when somebody runs a migration.
final moodCatalogProvider = StreamProvider<List<Mood>>((ref) {
  // Re-subscribes on sign-in and sign-out. The catalogue belongs to the
  // account: a different account may be in a different organisation.
  final signedIn = ref.watch(sessionProvider.select((user) => user?.id));
  if (signedIn == null) {
    // Signed out. Whatever the last account could see is not this screen's to
    // keep; back to the six every build knows.
    MoodCatalog.instance.reset();
    return Stream.value(const <Mood>[]);
  }
  return ref.watch(moodRepoProvider).watchCatalogue().map((moods) {
    MoodCatalog.instance.merge(moods);
    return moods;
  });
});

final _zoneMoodsStreamProvider =
    StreamProvider.autoDispose<List<Mood>>((ref) {
  ref.watch(currentZoneIdProvider);
  return ref.watch(moodRepoProvider).watchZoneMoods();
});

/// The moods the room in hand offers — what the Floor grid and the schedule
/// editor draw.
///
/// The server's answer when there is one. Until then, and when there cannot be
/// one (offline, or a backend that predates the endpoint), the fallback is
/// deliberately narrow: **the moods in the same set as the one the room is
/// playing**, from whatever the catalogue already knows.
///
/// That rule is what keeps both promises at once. An existing venue is playing
/// one of the six built-in moods, so its grid shows the six immediately, with
/// no network — exactly what it showed when they were compiled in. A venue
/// with its own catalogue is playing a mood the built-ins do not contain, so
/// with nothing loaded it is offered NOTHING rather than the Default six: an
/// empty grid is a visible gap, while six moods that room cannot play would be
/// an invitation to tap one.
final zoneMoodsProvider = Provider.autoDispose<List<Mood>>((ref) {
  final fetched = ref.watch(_zoneMoodsStreamProvider);
  if (fetched.hasValue) return fetched.value!;

  // Rebuild when the catalogue fills in.
  ref.watch(moodCatalogProvider);
  final playing = ref.watch(nowPlayingProvider).value?.moodId;
  final catalog = MoodCatalog.instance;
  if (playing == null || !catalog.knows(playing)) return const [];
  return catalog.inSet(catalog.byId(playing).moodSetId);
});
