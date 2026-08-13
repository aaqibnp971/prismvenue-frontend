import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/weather.dart';
import '../repositories/weather_repo.dart';

/// `WeatherRepo` against Open-Meteo.
///
/// Chosen because it needs **no API key** — no signup, no secret to bake into a
/// `--dart-define`, nothing to leak from a venue iPad, and no per-device quota
/// to exhaust. It is also the only external service this app talks to besides
/// its own backend.
///
/// Deliberately NOT routed through `ApiClient`: that attaches the Supabase
/// bearer token and an `Idempotency-Key` to everything it sends, and neither
/// belongs on a third-party request. Sending a session token to open-meteo.com
/// would be a straightforward credential leak. This uses its own bare
/// [http.Client].
///
/// ## Two calls, very different lifetimes
///
/// **Geocode** (address → lat/lon) runs at most once per venue, ever, and is
/// cached in shared_preferences. A venue does not move. Without the cache this
/// would be a round trip on every launch that can only return the same answer.
///
/// **Forecast** (lat/lon → conditions) runs on a timer. Open-Meteo's current
/// conditions update roughly every 15 minutes, so polling faster only spends
/// someone's battery to receive the same numbers.
///
/// ## What is sent
///
/// The venue's address text (once, to the geocoder) and its coordinates
/// (repeatedly, to the forecast API). No user identity, no session token, no
/// zone or venue id. Worth knowing that a venue's address does reach a third
/// party — it is inherent to asking a weather service about a place, but it is
/// the kind of thing that should be written down rather than discovered.
class OpenMeteoWeatherRepo implements WeatherRepo {
  OpenMeteoWeatherRepo({http.Client? client, this.refreshEvery = const Duration(minutes: 15)})
      : _http = client ?? http.Client();

  final http.Client _http;

  /// How often to re-read conditions. Zero disables the timer and leaves a
  /// single fetch on subscribe — which is what the tests want.
  final Duration refreshEvery;

  static const _geocodeHost = 'geocoding-api.open-meteo.com';
  static const _forecastHost = 'api.open-meteo.com';
  static const _timeout = Duration(seconds: 10);

  /// Coordinates already resolved this session, on top of the persisted cache.
  final _points = <String, GeoPoint?>{};

  @override
  Stream<WeatherReading?> watch({required String venueId, String? address}) {
    late StreamController<WeatherReading?> controller;
    Timer? timer;
    var closed = false;

    Future<void> tick() async {
      final reading = await _read(venueId: venueId, address: address);
      if (!closed && !controller.isClosed) controller.add(reading);
    }

    controller = StreamController<WeatherReading?>(
      onListen: () {
        // Emit something immediately so a subscriber is never left with no
        // value at all; the fetch replaces it a moment later.
        controller.add(null);
        unawaited(tick());
        if (refreshEvery > Duration.zero) {
          timer = Timer.periodic(refreshEvery, (_) => unawaited(tick()));
        }
      },
      onCancel: () {
        closed = true;
        timer?.cancel();
        timer = null;
      },
    );
    return controller.stream;
  }

  /// One reading, or null for any reason at all.
  ///
  /// Every failure path lands here rather than throwing, because the caller is
  /// a stream feeding the audio engine: an exception would either kill the
  /// stream or surface as an error state on a screen that has nothing to say
  /// about the weather.
  Future<WeatherReading?> _read({
    required String venueId,
    String? address,
  }) async {
    try {
      final point = await _pointFor(venueId, address);
      if (point == null) return null;
      return await _forecast(point);
    } catch (_) {
      return null;
    }
  }

  // --- Geocoding ---------------------------------------------------------------

  static String _cacheKey(String venueId) => 'prism.geo.$venueId';

  Future<GeoPoint?> _pointFor(String venueId, String? address) async {
    if (_points.containsKey(venueId)) return _points[venueId];

    final cached = await _cachedPoint(venueId);
    if (cached != null) {
      _points[venueId] = cached;
      return cached;
    }

    if (address == null || address.trim().isEmpty) return null;

    final point = await _geocode(address);
    // Cached even when null is NOT what happens here: a failed lookup is
    // remembered only for this session (via _points), never persisted, so a
    // venue whose address was mistyped and later corrected resolves on the next
    // launch instead of being wrong forever.
    _points[venueId] = point;
    if (point != null) await _cachePoint(venueId, point);
    return point;
  }

  Future<GeoPoint?> _cachedPoint(String venueId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey(venueId));
      if (raw == null) return null;
      return GeoPoint.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _cachePoint(String venueId, GeoPoint point) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey(venueId), jsonEncode(point.toJson()));
    } catch (_) {
      // In memory is enough for this launch.
    }
  }

  /// Address → coordinates, with one fallback.
  ///
  /// Open-Meteo's geocoder resolves PLACE NAMES, not street addresses: it finds
  /// "Dubai" and shrugs at "12 Marina Promenade, Dubai". Since `venues.address`
  /// is free text a human typed, the whole string is tried first and then the
  /// last comma-separated component — which for a conventionally written
  /// address is the city, and for a single-word address is the same string
  /// again (so the retry costs nothing and is skipped).
  ///
  /// Precision does not matter here. Weather varies over tens of kilometres;
  /// getting the right city is the whole requirement.
  Future<GeoPoint?> _geocode(String address) async {
    final attempts = <String>[address.trim()];
    final tail = address.split(',').last.trim();
    if (tail.isNotEmpty && tail != attempts.first) attempts.add(tail);

    for (final query in attempts) {
      final uri = Uri.https(_geocodeHost, '/v1/search', {
        'name': query,
        'count': '1',
        'format': 'json',
      });
      final response = await _http.get(uri).timeout(_timeout);
      if (response.statusCode != 200) continue;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final results = json['results'] as List?;
      if (results == null || results.isEmpty) continue;

      final first = (results.first as Map).cast<String, dynamic>();
      final lat = (first['latitude'] as num?)?.toDouble();
      final lon = (first['longitude'] as num?)?.toDouble();
      if (lat != null && lon != null) return GeoPoint(lat, lon);
    }
    return null;
  }

  // --- Conditions ---------------------------------------------------------------

  Future<WeatherReading?> _forecast(GeoPoint point) async {
    final uri = Uri.https(_forecastHost, '/v1/forecast', {
      'latitude': point.latitude.toStringAsFixed(4),
      'longitude': point.longitude.toStringAsFixed(4),
      // Exactly the four fields the nudge reads. `is_day` is the location-
      // derived one: Open-Meteo computes it from this latitude's own sunrise
      // and sunset, which is a season-and-latitude answer rather than a clock
      // one — a December evening in Reykjavik and one in Dubai are different
      // facts about the room.
      'current': 'temperature_2m,is_day,weather_code,cloud_cover',
    });

    final response = await _http.get(uri).timeout(_timeout);
    if (response.statusCode != 200) return null;

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final current = (json['current'] as Map?)?.cast<String, dynamic>();
    if (current == null) return null;

    final code = (current['weather_code'] as num?)?.toInt();
    if (code == null) return null;

    return WeatherReading(
      condition: WeatherReading.conditionFromWmo(code),
      // cloud_cover is a percentage on the wire; the model wants 0–1.
      cloudCover: ((current['cloud_cover'] as num?)?.toDouble() ?? 0) / 100.0,
      // Absent reads as daylight: the daytime nudge is the gentler of the two,
      // so an unknown sky should not darken a room.
      isDay: (current['is_day'] as num?)?.toInt() != 0,
      // 22°C is the comfort point the chill term measures from, so it is also
      // the right "no information" value — it contributes nothing.
      temperatureC: (current['temperature_2m'] as num?)?.toDouble() ?? 22.0,
      observedAt: DateTime.now(),
    );
  }

  void dispose() => _http.close();
}
