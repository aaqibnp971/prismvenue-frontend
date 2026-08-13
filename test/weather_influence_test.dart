import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_core_bindings/prism_core_bindings.dart';
import 'package:prism_venues/data/models/weather.dart';
import 'package:prism_venues/engine/weather_influence.dart';

/// Weather → PSV → the engine's actual audio parameters.
///
/// The assertions below deliberately do **not** stop at the nudge. A test that
/// only checked "cognitive_load went up by 0.03" would pass while changing
/// nothing anyone can hear. What matters is whether `cutoff_hz`, the five stem
/// gains, the density gates and the layer set move — so this drives the §5
/// mapping and asserts on those.
///
/// `_AudioParams` below is a mirror of `pgae/src/mapping.cpp`, which stays
/// authoritative: it is the code that actually renders, and it is covered by
/// `ctest -R PgaeMapping`. This copy exists because the invariants that bound
/// this feature are statements ABOUT that mapping ("weather must not open a
/// layer"), and they cannot be expressed without it. If the two ever disagree,
/// the C++ is right and this file is stale.
void main() {
  // --- The mapping, mirrored from pgae/src/mapping.cpp §5 --------------------

  double clamp01(double v) => v.clamp(0.0, 1.0);

  _AudioParams paramsFor(double arousal, double load, double readiness) {
    // Confidence is 1.0 for a pinned mood — load-bearing, and why `effective()`
    // collapses to the raw value here. A mood pinned at low confidence would be
    // pulled back toward neutral and barely change the sound at all.
    final a = arousal - 0.5;
    final l = load - 0.5;
    final r = readiness - 0.5;

    final brightness = clamp01(0.55 + 0.9 * a - 0.8 * l);
    final gains = <String, double>{
      'bed': clamp01(0.6 + 0.6 * l),
      'sub': clamp01(0.5 - 0.6 * r),
      'pulse': clamp01(0.5 + 0.7 * a - 0.6 * l),
      'lead': clamp01(0.5 + 0.4 * a - 0.9 * l),
      'air': clamp01(0.5 + 0.5 * a - 0.6 * l),
    };
    return _AudioParams(
      cutoffHz: 300 * math.pow(12000 / 300, brightness).toDouble(),
      density: clamp01(0.5 + 0.9 * a - 1.0 * l),
      gains: gains,
      // bed and sub are always on; the other three are gated.
      active: {
        'bed',
        'sub',
        if (gains['pulse']! >= 0.35) 'pulse',
        if (gains['air']! >= 0.55) 'air',
        if (gains['lead']! >= 0.72) 'lead',
      },
    );
  }

  _AudioParams paramsForMood(VenueMood m, PsvNudge n) => paramsFor(
        (m.arousal + n.arousal).clamp(0.0, 1.0),
        (m.cognitiveLoad + n.cognitiveLoad).clamp(0.0, 1.0),
        (m.readiness + n.readiness).clamp(0.0, 1.0),
      );

  // --- Fixtures --------------------------------------------------------------

  WeatherReading reading({
    SkyCondition condition = SkyCondition.clear,
    double cloudCover = 0,
    bool isDay = true,
    double temperatureC = 22,
  }) =>
      WeatherReading(
        condition: condition,
        cloudCover: cloudCover,
        isDay: isDay,
        temperatureC: temperatureC,
        observedAt: DateTime.utc(2026, 8, 12, 15),
      );

  /// The corners of the input space, not a happy path. If the invariants hold
  /// here they hold everywhere between.
  final grid = <String, WeatherReading?>{
    'no reading at all': null,
    'clear bright afternoon':
        reading(cloudCover: 0.0, temperatureC: 30),
    'clear cold night': reading(isDay: false, temperatureC: -5),
    'overcast day': reading(
        condition: SkyCondition.overcast, cloudCover: 1.0, temperatureC: 12),
    'storm at night': reading(
        condition: SkyCondition.storm,
        cloudCover: 1.0,
        isDay: false,
        temperatureC: 2),
    'freezing fog at night': reading(
        condition: SkyCondition.fog,
        cloudCover: 0.2, // fog routinely reports LOW cloud cover
        isDay: false,
        temperatureC: -10),
    'warm rain, low reported cloud': reading(
        condition: SkyCondition.rain, cloudCover: 0.3, temperatureC: 28),
  };

  // --- The feature actually does something -----------------------------------

  group('weather moves the engine parameters that already exist', () {
    test('a grey cold night is darker and heavier than a clear warm day', () {
      // The headline claim, asserted on real audio parameters rather than on
      // the offsets that produced them.
      const mood = VenueMood.daytimeFlow;
      final bright = paramsForMood(
          mood, nudgeFor(reading(cloudCover: 0.0, temperatureC: 30)));
      final grey = paramsForMood(
          mood,
          nudgeFor(reading(
              condition: SkyCondition.storm,
              cloudCover: 1.0,
              isDay: false,
              temperatureC: 2)));

      // The bottom gets heavier. This is the loud half of the effect: sub is
      // the one gain that moves on readiness alone, and it is the loudest
      // stem, so night is felt rather than merely heard.
      expect(grey.gains['sub']!, greaterThan(bright.gains['sub']!));
      expect(grey.gains['sub']! - bright.gains['sub']!, greaterThan(0.03));

      // The master low-pass closes down, and the steady bed rises under load
      // while the melodic foreground recedes. Small by design — these three
      // ride on the gate-bearing dimensions.
      expect(grey.cutoffHz, lessThan(bright.cutoffHz));
      expect(grey.gains['bed']!, greaterThan(bright.gains['bed']!));
      expect(grey.gains['lead']!, lessThan(bright.gains['lead']!));
      expect(grey.density, lessThan(bright.density));
    });

    test('every mood responds, not just the middle of the range', () {
      for (final mood in VenueMood.all) {
        final bright = paramsForMood(
            mood, nudgeFor(reading(cloudCover: 0.0, temperatureC: 30)));
        final grey = paramsForMood(
            mood,
            nudgeFor(reading(
                condition: SkyCondition.overcast,
                cloudCover: 1.0,
                isDay: false,
                temperatureC: 0)));
        // Asserted on sub rather than cutoff because peak's cutoff cannot move
        // — see the saturation test below.
        expect(grey.gains['sub']!, greaterThan(bright.gains['sub']!),
            reason: mood.id);
      }
    });

    test("peak's cutoff is saturated, so its weather lives in the low end", () {
      // Not a defect, and worth pinning down so nobody "fixes" it: peak's
      // brightness computes to 1.048, which clamp01 pins at 1.0 — the top of
      // the 300 Hz…12 kHz range. The filter is already wide open, so no
      // realistic tint can darken it, and a test asserting "cutoff always
      // drops" would fail on peak alone.
      const peak = VenueMood.peak;
      final bright = paramsForMood(peak, nudgeFor(reading(cloudCover: 0)));
      final grey = paramsForMood(
          peak,
          nudgeFor(reading(
              condition: SkyCondition.storm,
              cloudCover: 1.0,
              isDay: false,
              temperatureC: 0)));

      expect(bright.cutoffHz, 12000.0);
      expect(grey.cutoffHz, 12000.0);
      // The effect is still audible, just entirely in the bottom end.
      expect(grey.gains['sub']!, greaterThan(bright.gains['sub']!));
    });

    test('no reading changes nothing at all', () {
      // The failure story for the whole feature: no network, no address, an API
      // that is down. Pinning preset + none must be identical to pinning the
      // preset, or "weather is unavailable" would itself be audible.
      expect(nudgeFor(null), same(PsvNudge.none));
      for (final mood in VenueMood.all) {
        final plain = paramsFor(mood.arousal, mood.cognitiveLoad, mood.readiness);
        final nudged = paramsForMood(mood, nudgeFor(null));
        expect(nudged.cutoffHz, plain.cutoffHz, reason: mood.id);
        expect(nudged.gains, plain.gains, reason: mood.id);
        expect(nudged.active, plain.active, reason: mood.id);
      }
    });
  });

  // --- ...but never enough to become a different mood ------------------------

  group('weather colours the mood and never replaces it', () {
    test('the layer set is never changed, for any mood in any weather', () {
      // The binding constraint on maxOffset. Afternoon-lift sits at lead = 0.67
      // against a 0.72 gate — 0.05 of headroom — so a nudge much larger than
      // this opens a fifth layer and turns it into a different mood. If this
      // fails after a coefficient change, that is the feature exceeding its
      // brief, not a flaky test.
      for (final mood in VenueMood.all) {
        final plain = paramsFor(mood.arousal, mood.cognitiveLoad, mood.readiness);
        for (final entry in grid.entries) {
          final nudged = paramsForMood(mood, nudgeFor(entry.value));
          expect(nudged.active, plain.active,
              reason: '${mood.id} in ${entry.key}: weather opened or closed a '
                  'layer (${plain.active} → ${nudged.active})');
        }
      }
    });

    test('a nudged mood stays nearer its own preset than any other', () {
      // The closest pair of presets are ~0.19 apart, so the offset magnitude
      // has to stay under ~0.095 for this to hold. It is the reason the
      // coefficients are small rather than dramatic.
      for (final mood in VenueMood.all) {
        for (final entry in grid.entries) {
          final n = nudgeFor(entry.value);
          final own = _distance(mood, mood, n);
          for (final other in VenueMood.all) {
            if (identical(other, mood)) continue;
            expect(own, lessThan(_distance(mood, other, n)),
                reason: '${mood.id} in ${entry.key} drifted closer to '
                    '${other.id}');
          }
        }
      }
    });

    test('no offset exceeds its documented ceiling', () {
      // Two ceilings, not one: the gate-bearing dimensions are held to a tiny
      // tint, while readiness — which no gate reads — carries the audible part.
      for (final entry in grid.entries) {
        final n = nudgeFor(entry.value);
        expect(n.arousal.abs(), lessThanOrEqualTo(maxTintOffset),
            reason: entry.key);
        expect(n.cognitiveLoad.abs(), lessThanOrEqualTo(maxTintOffset),
            reason: entry.key);
        expect(n.readiness.abs(), lessThanOrEqualTo(maxDepthOffset),
            reason: entry.key);
      }
    });

    test('the pinned dimensions stay inside [0,1]', () {
      // wind-down sits at arousal 0.12 and readiness 0.20; peak at 0.92. A
      // nudge that pushed a dimension out of range would be INVALID_ARGUMENT at
      // the ABI, which surfaces as the whole setMood failing.
      for (final mood in VenueMood.all) {
        for (final entry in grid.entries) {
          final n = nudgeFor(entry.value);
          for (final v in [
            mood.arousal + n.arousal,
            mood.cognitiveLoad + n.cognitiveLoad,
            mood.readiness + n.readiness,
          ]) {
            expect(v, inInclusiveRange(0.0, 1.0),
                reason: '${mood.id} in ${entry.key}');
          }
        }
      }
    });
  });

  // --- Individual inputs pull the direction they claim to ---------------------

  group('each input moves the sound the way its comment says', () {
    test('cloud closes the room down', () {
      final clear = nudgeFor(reading(cloudCover: 0.0));
      final covered = nudgeFor(
          reading(condition: SkyCondition.overcast, cloudCover: 1.0));
      expect(covered.cognitiveLoad, greaterThan(clear.cognitiveLoad));
      expect(covered.arousal, lessThan(clear.arousal));
    });

    test('darkness lifts the low end and damps arousal', () {
      final day = nudgeFor(reading(isDay: true));
      final night = nudgeFor(reading(isDay: false));
      expect(night.readiness, lessThan(day.readiness));
      expect(night.arousal, lessThan(day.arousal));
    });

    test('cold warms the sound; heat does not invert it', () {
      final cold = nudgeFor(reading(temperatureC: 0));
      final mild = nudgeFor(reading(temperatureC: 22));
      final hot = nudgeFor(reading(temperatureC: 45));
      expect(cold.cognitiveLoad, greaterThan(mild.cognitiveLoad));
      // Above the comfort point the term contributes nothing rather than
      // reversing — "hot" is not the opposite of "cosy" in this mapping.
      expect(hot.cognitiveLoad, mild.cognitiveLoad);
    });

    test('rain counts as heavy cover even under a clear-ish reported sky', () {
      // It can rain under 30% reported cloud, and the room should still sound
      // enclosed.
      final drizzleUnderBlueSky =
          nudgeFor(reading(condition: SkyCondition.rain, cloudCover: 0.3));
      final plainlyCloudy = nudgeFor(
          reading(condition: SkyCondition.partlyCloudy, cloudCover: 0.3));
      expect(drizzleUnderBlueSky.cognitiveLoad,
          greaterThan(plainlyCloudy.cognitiveLoad));
    });

    test('fog is the strongest enclosure signal despite low cloud cover', () {
      final fog = nudgeFor(reading(condition: SkyCondition.fog, cloudCover: 0.2));
      final clear = nudgeFor(reading(cloudCover: 0.2));
      expect(fog.cognitiveLoad, greaterThan(clear.cognitiveLoad));
    });
  });

  // --- WMO decoding -----------------------------------------------------------

  group('WMO codes', () {
    test('the buckets that matter decode correctly', () {
      expect(WeatherReading.conditionFromWmo(0), SkyCondition.clear);
      expect(WeatherReading.conditionFromWmo(2), SkyCondition.partlyCloudy);
      expect(WeatherReading.conditionFromWmo(3), SkyCondition.overcast);
      expect(WeatherReading.conditionFromWmo(45), SkyCondition.fog);
      expect(WeatherReading.conditionFromWmo(61), SkyCondition.rain);
      expect(WeatherReading.conditionFromWmo(71), SkyCondition.snow);
      expect(WeatherReading.conditionFromWmo(95), SkyCondition.storm);
    });

    test('an unknown code degrades instead of throwing', () {
      // Weather is decoration on the sound. A code added to the standard after
      // this build shipped must not be able to silence a venue.
      expect(WeatherReading.conditionFromWmo(999), SkyCondition.partlyCloudy);
      expect(WeatherReading.conditionFromWmo(-1), SkyCondition.partlyCloudy);
    });
  });
}

/// Distance from [mood] nudged by [n] to [target]'s preset.
double _distance(VenueMood mood, VenueMood target, PsvNudge n) {
  final da = (mood.arousal + n.arousal) - target.arousal;
  final dl = (mood.cognitiveLoad + n.cognitiveLoad) - target.cognitiveLoad;
  final dr = (mood.readiness + n.readiness) - target.readiness;
  // valence is untouched by the nudge but still separates the presets, so it
  // belongs in the comparison.
  final dv = mood.valence - target.valence;
  return math.sqrt(da * da + dl * dl + dr * dr + dv * dv);
}

class _AudioParams {
  const _AudioParams({
    required this.cutoffHz,
    required this.density,
    required this.gains,
    required this.active,
  });

  final double cutoffHz;
  final double density;
  final Map<String, double> gains;
  final Set<String> active;
}
