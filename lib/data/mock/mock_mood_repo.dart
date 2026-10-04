import '../../theme/moods.dart';
import '../repositories/mood_repo.dart';

/// The mock catalogue: the six built-in moods, for every room.
///
/// Every mock venue is on the Default set, as every real venue was until
/// migration 022. A test that needs a room with a catalogue of its own
/// overrides `moodRepoProvider` with a list of its choosing.
class MockMoodRepo implements MoodRepo {
  const MockMoodRepo({this.catalogue = builtInMoods, this.zoneMoods});

  final List<Mood> catalogue;

  /// What the room in hand offers. Defaults to the whole [catalogue].
  final List<Mood>? zoneMoods;

  @override
  Stream<List<Mood>> watchCatalogue() => Stream.value(catalogue);

  @override
  Stream<List<Mood>> watchZoneMoods() => Stream.value(zoneMoods ?? catalogue);
}
