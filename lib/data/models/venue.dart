import 'zone.dart';

/// A venue in the estate — §2 S04. Portfolio rows show
/// "{n} zone(s) · {mood}" (S04-2 example "1 zone · Peak").
class Venue {
  const Venue({
    required this.id,
    required this.name,
    required this.zones,
    this.address,
    this.hoursLabel = 'Every day · 7am–11pm', // S05-6 default
    this.timezone,
    this.localTime,
  });

  final String id;
  final String name;
  final List<Zone> zones;
  final String? address;
  final String hoursLabel;

  /// IANA name — the clock every daypart in this venue runs on, and the single
  /// thing that decides which one is current (`app.scheduled_mood_for`).
  ///
  /// Null only until the fetch lands. Shown rather than assumed: it was
  /// invisible and unset for every venue, so a schedule typed in one country
  /// fired on another country's clock with nothing on screen to explain it.
  final String? timezone;

  /// Wall clock in [timezone] right now, "HH:MM", as the server read it.
  /// Server-computed on purpose — the device's clock is the wrong one, and
  /// showing the difference is the entire point.
  final String? localTime;

  bool get hasProblem => zones.any((z) => z.status != ZoneStatus.auto);

  /// Worst state wins for the portfolio row treatment: red > amber > quiet.
  ZoneStatus get worstStatus {
    if (zones.any((z) => z.status == ZoneStatus.offline)) {
      return ZoneStatus.offline;
    }
    if (zones.any((z) => z.status == ZoneStatus.offSchedule)) {
      return ZoneStatus.offSchedule;
    }
    return ZoneStatus.auto;
  }

  Venue copyWith({List<Zone>? zones}) => Venue(
        id: id,
        name: name,
        zones: zones ?? this.zones,
        address: address,
        hoursLabel: hoursLabel,
        timezone: timezone,
        localTime: localTime,
      );
}
