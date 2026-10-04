/// The low-pass floor, as far as the app is concerned (engine ABI 0.6).
///
/// The floor exists for one venue's mood sets. It was approved on the condition
/// that every existing venue keeps sounding exactly as it did, and the engine
/// holds up its half of that with a hash test: a mood with no floor renders the
/// same samples as before. This file holds up the app's half — that for the six
/// Default moods, what the app hands the engine is null. Not 0, not "wide open",
/// not whatever the last mood left behind.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_core_bindings/prism_core_bindings.dart';
import 'package:prism_venues/engine/prism_engine_native.dart';
import 'package:prism_venues/engine/weather_influence.dart';
import 'package:prism_venues/theme/moods.dart';

void main() {
  test('every mood the app can show resolves to an engine preset', () {
    // The id list the UI draws from and the list the engine knows must be the
    // same six, or the test below is checking the wrong set.
    expect(builtInMoods.map((m) => m.id).toSet(),
        VenueMood.all.map((m) => m.id).toSet());
    expect(builtInMoods, hasLength(6));
  });

  test('for every Default mood the app passes the engine a null floor', () {
    for (final mood in builtInMoods) {
      final preset = VenueMood.byId(mood.id)!;
      final pinned = moodToPin(preset, PsvNudge.none);

      expect(pinned.lowpassFloorHz, isNull, reason: mood.id);
      // No nudge means the preset itself, untouched — the same object.
      expect(identical(pinned, preset), isTrue, reason: mood.id);
    }
  });

  test('weather cannot add a floor to a Default mood', () {
    // The nudge is applied on every mood change, so it is the one thing that
    // sits between the compiled preset and the engine. Checked at both ends of
    // the range the weather feature is allowed to move the vector.
    const extremes = [
      PsvNudge(arousal: 0.006, cognitiveLoad: 0.006, readiness: 0.09),
      PsvNudge(arousal: -0.006, cognitiveLoad: -0.006, readiness: -0.09),
      PsvNudge(arousal: 0.006, cognitiveLoad: -0.006, readiness: -0.09),
    ];
    for (final mood in builtInMoods) {
      final preset = VenueMood.byId(mood.id)!;
      for (final nudge in extremes) {
        final pinned = moodToPin(preset, nudge);
        expect(pinned.lowpassFloorHz, isNull, reason: mood.id);
        expect(pinned.id, mood.id);
      }
    }
  });

  test('a mood that has a floor keeps it through the same path', () {
    // The other direction: a floor that the nudge dropped would close the
    // filter on a room whose texture bed depends on it being open.
    const forestFloor = VenueMood.fromData(
      id: 'lnl-forest-floor',
      modeHint: 'lnl_forest_floor',
      arousal: 0.25,
      valence: 0.65,
      cognitiveLoad: 0.50,
      readiness: 0.50,
      lowpassFloorHz: 6000,
    );

    expect(moodToPin(forestFloor, PsvNudge.none).lowpassFloorHz, 6000);
    expect(
      moodToPin(
        forestFloor,
        const PsvNudge(arousal: 0.006, cognitiveLoad: -0.006, readiness: -0.09),
      ).lowpassFloorHz,
      6000,
    );
  });
}
