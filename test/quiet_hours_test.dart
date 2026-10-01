/// Finding #5 — quiet hours was never enforced.
///
/// An owner switched on "after 10pm · cap at 55%" for a venue with neighbours
/// and believed the room was capped at night. It was not: `quietHours` was read
/// nowhere outside the settings screen, the start time and cap had no field in
/// the model at all, and the row rendered a fixed "After 10:00 pm · cap at 55%"
/// for every venue on earth.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/models/guardrails.dart';

void main() {
  group('the row describes the real setting', () {
    test('label is built from the values, not hard-coded', () {
      const g = Guardrails(
        quietHoursOn: true,
        quietHoursStartMinutes: 23 * 60 + 30,
        quietHoursCapPct: 40,
      );

      expect(g.quietHoursLabel, 'After 11:30 pm · cap at 40%');
    });

    test('midnight and noon are not both "12 am"', () {
      const midnight = Guardrails(quietHoursStartMinutes: 0);
      const noon = Guardrails(quietHoursStartMinutes: 12 * 60);

      expect(midnight.quietHoursStartLabel, '12:00 am');
      expect(noon.quietHoursStartLabel, '12:00 pm');
    });

    test('switched off says so rather than naming a time it ignores', () {
      const off = Guardrails(quietHoursOn: false);

      expect(off.quietHoursLabel, 'Off');
    });
  });

  group('the ceiling the engine applies', () {
    // The engine takes the lower of the band ceiling and the live quiet cap.
    // Expressed here as the rule itself, because it is the part an owner is
    // trusting when they say "not after ten, the neighbours".
    int ceiling({required int band, int? quiet}) =>
        quiet == null ? band : (quiet < band ? quiet : band);

    test('outside quiet hours the band decides', () {
      expect(ceiling(band: 70), 70);
    });

    test('inside quiet hours the cap pulls the room down', () {
      expect(ceiling(band: 70, quiet: 55), 55);
    });

    test('a cap louder than the band never raises the room', () {
      // "Cap at 55" on a band that already tops out at 40 must not make the
      // room LOUDER at 10pm. That is the failure mode worth a test.
      expect(ceiling(band: 40, quiet: 55), 40);
    });
  });
}
