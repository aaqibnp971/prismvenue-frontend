import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/models/timezone.dart';

/// The one piece of clock logic that lives in the app rather than in Postgres.
void main() {
  test('the device reading is two offsets, six months apart', () {
    // A single offset cannot separate a DST zone from a fixed one: +0 in
    // January is London and Abidjan both, and they diverge in July. Sampled
    // mid-month so a changeover, which happens at the edges, cannot land on it.
    final offsets = DeviceOffsets.fromDevice(DateTime(2026, 3, 1));

    expect(offsets.januaryMinutes,
        DateTime(2026, 1, 15).timeZoneOffset.inMinutes);
    expect(offsets.julyMinutes, DateTime(2026, 7, 15).timeZoneOffset.inMinutes);
    expect(offsets.toJson(), {
      'january_minutes': offsets.januaryMinutes,
      'july_minutes': offsets.julyMinutes,
    });
  });

  test('offsets render the way a venue manager reads them', () {
    String label(int minutes) =>
        TimezoneOption(name: 'X/Y', utcOffsetMinutes: minutes).offsetLabel;

    expect(label(0), 'GMT');
    expect(label(330), 'GMT+5:30');
    expect(label(240), 'GMT+4');
    // A minus sign, not a hyphen — it sits next to digits.
    expect(label(-240), 'GMT−4');
    expect(label(-210), 'GMT−3:30');
  });

  test('the name splits into something readable', () {
    const option =
        TimezoneOption(name: 'America/Argentina/Buenos_Aires', utcOffsetMinutes: -180);
    // Last segment, so a three-part name still names the city.
    expect(option.city, 'Buenos Aires');
    expect(option.region, 'America');
  });
}
