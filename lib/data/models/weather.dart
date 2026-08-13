/// What the sky over a venue is doing.
///
/// Deliberately small. This is not a weather app: the only reason the value
/// exists is to colour the sound, so it carries the four things the PSV nudge
/// in `lib/engine/weather_influence.dart` actually reads and nothing else.
/// Every extra field would be one more thing to keep in step for no audible
/// gain.
///
/// **This is the venue's sky, not the device's.** An owner in Dubai reviewing
/// their London venue must hear London — the whole estate flow falls apart
/// otherwise. So the coordinates come from the venue record, never from device
/// geolocation.
library;

/// Coarse sky state, as far as the sound is concerned.
///
/// WMO weather codes have ~28 values; collapsing them here rather than at the
/// call site keeps the nudge readable and means a code this build has never
/// seen degrades to the nearest sensible bucket instead of throwing.
enum SkyCondition {
  clear,
  partlyCloudy,
  overcast,
  fog,
  rain,
  snow,
  storm;

  /// True when there is water or ice actually falling. The nudge treats this
  /// as heavy overcast regardless of what the cloud-cover percentage claims —
  /// it can rain under a reported 60% sky, and the room should still sound
  /// enclosed.
  bool get isPrecipitating =>
      this == rain || this == snow || this == storm;
}

class WeatherReading {
  const WeatherReading({
    required this.condition,
    required this.cloudCover,
    required this.isDay,
    required this.temperatureC,
    required this.observedAt,
  });

  final SkyCondition condition;

  /// 0–1. Distinct from [condition] because they answer different questions:
  /// "overcast" is a category, this is how much of the sky is actually covered,
  /// and the nudge wants the continuous value so the sound moves gradually
  /// rather than stepping between buckets.
  final double cloudCover;

  /// Daylight at the VENUE. Open-Meteo computes this from the venue's own
  /// sunrise/sunset, which is why it is worth taking from the API rather than
  /// guessing from a clock: "is it dark outside this room" is the question, and
  /// that is a latitude-and-season answer, not a time-of-day one.
  final bool isDay;

  final double temperatureC;

  final DateTime observedAt;

  /// The `context_line` fragment this reading contributes.
  ///
  /// S05's designed example line is "mid-afternoon · ~60% full · clear" — the
  /// last segment is a weather word, so this is the slot the design already
  /// had in mind rather than a new surface invented here.
  String get label => switch (condition) {
        SkyCondition.clear => isDay ? 'clear' : 'clear night',
        SkyCondition.partlyCloudy => 'partly cloudy',
        SkyCondition.overcast => 'overcast',
        SkyCondition.fog => 'fog',
        SkyCondition.rain => 'rain',
        SkyCondition.snow => 'snow',
        SkyCondition.storm => 'storm',
      };

  /// WMO code → bucket. Open-Meteo returns these directly.
  ///
  /// Unknown codes fall to [SkyCondition.partlyCloudy] rather than throwing:
  /// weather is decoration on the sound, and a code added to the standard after
  /// this build shipped must not be able to silence a venue.
  static SkyCondition conditionFromWmo(int code) {
    // Bounded FIRST. WMO codes run 0–99, and an open-ended `code >= 95` turned
    // every out-of-range value — including a garbled 999 — into a thunderstorm,
    // which is the loudest possible way to misread a field.
    if (code < 0 || code > 99) return SkyCondition.partlyCloudy;
    if (code == 0) return SkyCondition.clear;
    if (code == 1 || code == 2) return SkyCondition.partlyCloudy;
    if (code == 3) return SkyCondition.overcast;
    if (code == 45 || code == 48) return SkyCondition.fog;
    if (code >= 95) return SkyCondition.storm;
    if (code >= 71 && code <= 77) return SkyCondition.snow;
    if (code >= 85 && code <= 86) return SkyCondition.snow;
    if (code >= 51 && code <= 67) return SkyCondition.rain;
    if (code >= 80 && code <= 82) return SkyCondition.rain;
    return SkyCondition.partlyCloudy;
  }
}

/// Where a venue is, for the weather lookup.
///
/// Cached once per venue: an address does not move, and geocoding on every
/// launch would be a round trip that can only ever return the same answer.
class GeoPoint {
  const GeoPoint(this.latitude, this.longitude);

  final double latitude;
  final double longitude;

  Map<String, dynamic> toJson() => {'lat': latitude, 'lon': longitude};

  static GeoPoint? fromJson(Map<String, dynamic> json) {
    final lat = (json['lat'] as num?)?.toDouble();
    final lon = (json['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return GeoPoint(lat, lon);
  }
}
