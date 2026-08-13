import 'dart:async';

import '../models/weather.dart';
import '../repositories/weather_repo.dart';

/// Weather without a network.
///
/// Keyed by venue, like the other mocks and like the real thing: two venues in
/// two cities have two skies, so an owner switching between them on mocks hears
/// the same independence they would against Open-Meteo. A single shared reading
/// would make the estate flow look like it collapses everything into one place
/// — the exact class of wrongness the zone-scoped mocks exist to avoid.
///
/// The seeds are deliberately different from each other so the effect is
/// audible while walking the estate on `--dart-define=PRISM_USE_MOCKS=true`:
/// Marina Café is clear and warm, Dockside is a cold storm at night, Harbor
/// House is overcast. Anything not named falls to a neutral clear day, which
/// nudges almost nothing.
class MockWeatherRepo implements WeatherRepo {
  MockWeatherRepo({Map<String, WeatherReading>? seed})
      : _byVenue = {...(seed ?? _defaultSeed)};

  static Map<String, WeatherReading> get _defaultSeed => {
        'marina-cafe': WeatherReading(
          condition: SkyCondition.clear,
          cloudCover: 0.05,
          isDay: true,
          temperatureC: 31,
          observedAt: DateTime(2026, 8, 12, 15),
        ),
        'dockside': WeatherReading(
          condition: SkyCondition.storm,
          cloudCover: 1.0,
          isDay: false,
          temperatureC: 3,
          observedAt: DateTime(2026, 8, 12, 22),
        ),
        'harbor-house': WeatherReading(
          condition: SkyCondition.overcast,
          cloudCover: 0.9,
          isDay: true,
          temperatureC: 11,
          observedAt: DateTime(2026, 8, 12, 15),
        ),
      };

  final Map<String, WeatherReading> _byVenue;

  static final _fallback = WeatherReading(
    condition: SkyCondition.clear,
    cloudCover: 0.1,
    isDay: true,
    temperatureC: 22,
    observedAt: DateTime(2026, 8, 12, 15),
  );

  final _controllers = <StreamController<WeatherReading?>>[];

  @override
  Stream<WeatherReading?> watch({required String venueId, String? address}) {
    final reading = _byVenue[venueId] ?? _fallback;
    // No ticker: weather that changed on a timer would make widget tests
    // unsettleable for no benefit, the same reason MockPlaybackRepo takes
    // `tickNoise: false`.
    final controller = StreamController<WeatherReading?>();
    controller.add(reading);
    _controllers.add(controller);
    return controller.stream;
  }

  /// Push a different sky at a venue — for exercising the audible difference
  /// by hand without waiting on a real forecast to change.
  void set(String venueId, WeatherReading reading) {
    _byVenue[venueId] = reading;
    for (final c in _controllers) {
      if (!c.isClosed) c.add(reading);
    }
  }

  void dispose() {
    for (final c in _controllers) {
      c.close();
    }
    _controllers.clear();
  }
}
