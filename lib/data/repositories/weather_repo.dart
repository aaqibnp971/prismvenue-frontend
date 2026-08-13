import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';
import '../models/weather.dart';
import '../mock/mock_weather_repo.dart';
import 'venue_repo.dart';

/// The sky over a venue — the only external signal that reaches the engine.
///
/// Shaped like the other five repositories (abstract boundary, mock by default,
/// API implementation swapped in by `buildPrismContainer`) so the swap seam
/// stays a single override list.
///
/// It differs from them in one way worth naming: **every failure is null, and
/// null is a valid answer.** No address, no network, a geocoder that cannot
/// place the venue, an API that is down — all of them mean "no reading", which
/// the engine turns into `PsvNudge.none` and therefore into exactly the sound
/// the app made before this feature existed. Weather is decoration on the
/// sound; it must never be able to make a room silent or wrong.
abstract class WeatherRepo {
  /// Emits the current reading immediately (possibly null), then on refresh.
  ///
  /// [address] is free text off the venue record and may be null — a venue is
  /// not required to have one.
  Stream<WeatherReading?> watch({required String venueId, String? address});
}

final weatherRepoProvider = Provider<WeatherRepo>((ref) {
  final repo = MockWeatherRepo();
  ref.onDispose(repo.dispose);
  return repo;
});

/// The reading for the venue currently being operated.
///
/// Watches the session's venue, so "Open floor" on a room in another city
/// repoints the weather along with everything else — an owner in Dubai
/// reviewing their London venue hears London.
///
/// The address comes from the venue list rather than the session context,
/// because `SessionContext` carries only ids and names. While the list is still
/// loading this passes null, which the geocoder cache usually covers anyway.
final weatherProvider = StreamProvider.autoDispose<WeatherReading?>((ref) {
  final venueId = ref.watch(currentVenueIdProvider);
  if (venueId == null) return Stream.value(null);

  final address = ref
      .watch(venuesProvider)
      .value
      ?.where((v) => v.id == venueId)
      .map((v) => v.address)
      .firstOrNull;

  return ref.watch(weatherRepoProvider).watch(venueId: venueId, address: address);
});
