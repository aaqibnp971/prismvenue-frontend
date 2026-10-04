/// The six built-in moods, against the three other places that describe them.
///
/// Moods are data now (migration 022, `GET /moods`), and the engine is handed
/// a preset built from the row rather than one looked up by id. The promise
/// that goes with that change is that every existing venue sounds exactly as
/// it did — and for the six moods those venues play, that comes down to this
/// file: the preset the app builds must be, number for number, the preset the
/// engine bindings have always held.
library;

import 'dart:io';
import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_core_bindings/prism_core_bindings.dart';
import 'package:prism_venues/engine/prism_engine_native.dart';
import 'package:prism_venues/engine/weather_influence.dart';
import 'package:prism_venues/theme/moods.dart';

void main() {
  setUp(MoodCatalog.instance.reset);

  test('the built-in moods are the same six the engine bindings know', () {
    expect(builtInMoods.map((m) => m.id).toSet(),
        VenueMood.all.map((m) => m.id).toSet());
    expect(builtInMoods, hasLength(6));
  });

  test('the preset built from each row equals the engine\'s own', () {
    for (final mood in builtInMoods) {
      final compiled = VenueMood.byId(mood.id)!;
      final built = presetFor(mood);

      expect(built.id, compiled.id);
      expect(built.modeHint, compiled.modeHint, reason: mood.id);
      // Exact, not close: the same decimal literal on both sides parses to
      // the same double, and anything else is a different sound.
      expect(built.arousal, compiled.arousal, reason: mood.id);
      expect(built.valence, compiled.valence, reason: mood.id);
      expect(built.cognitiveLoad, compiled.cognitiveLoad, reason: mood.id);
      expect(built.readiness, compiled.readiness, reason: mood.id);
      expect(built.lowpassFloorHz, isNull, reason: mood.id);
      expect(compiled.lowpassFloorHz, isNull, reason: mood.id);
    }
  });

  test('a row from the server builds the same preset as the built-in one', () {
    // What `GET /moods` sends for Peak, as JSON numbers.
    final fromServer = Mood.fromJson(const {
      'id': 'peak',
      'name': 'Peak',
      'mood_set_id': kDefaultMoodSetId,
      'sort_order': 5,
      'is_default': false,
      'arousal': 0.92,
      'valence': 0.7,
      'cognitive_load': 0.35,
      'readiness': 0.58,
      'bpm': 124,
      'energy': 5,
      'dot_dark': '#F0564F',
      'dot_light': '#D83A33',
      'grad_start': '#F4685F',
      'grad_end': '#D22F28',
      'mode_hint': 'venue_peak',
      'scene_manifest': 'mood_peak.json',
      'lowpass_floor_hz': null,
    });
    final compiled = VenueMood.peak;
    final built = presetFor(fromServer);

    expect(built.arousal, compiled.arousal);
    expect(built.valence, compiled.valence);
    expect(built.cognitiveLoad, compiled.cognitiveLoad);
    expect(built.readiness, compiled.readiness);
    expect(built.modeHint, compiled.modeHint);
    expect(built.lowpassFloorHz, isNull);
    // And through the last step before the FFI boundary.
    expect(moodToPin(built, PsvNudge.none).lowpassFloorHz, isNull);
  });

  test('a floor on the row reaches the preset, and only then', () {
    const forest = Mood(
      id: 'lnl-forest-floor',
      name: 'Forest Floor',
      dotDark: Color(0xFF84C44A),
      dotLight: Color(0xFF699F35),
      gradStart: Color(0xFF92CE58),
      gradEnd: Color(0xFF5F9427),
      bpm: null,
      energy: 1,
      arousal: 0.25,
      valence: 0.65,
      cognitiveLoad: 0.50,
      readiness: 0.50,
      modeHint: 'venue_settle',
      sceneManifest: 'mood_lnl_forest_floor.json',
      lowpassFloorHz: 6000,
      moodSetId: 'a-set-of-its-own',
    );
    expect(presetFor(forest).lowpassFloorHz, 6000);
    expect(moodToPin(presetFor(forest), PsvNudge.none).lowpassFloorHz, 6000);
  });

  test('every built-in mood names a scene that ships with the app', () {
    for (final mood in builtInMoods) {
      expect(File('assets/audio/${mood.sceneManifest}').existsSync(), isTrue,
          reason: '${mood.id} -> ${mood.sceneManifest}');
    }
  });

  test('display order, the default and the set are what migration 022 writes',
      () {
    expect(builtInMoods.map((m) => m.id), [
      'morning-calm',
      'daytime-flow',
      'afternoon-lift',
      'evening-warmth',
      'peak',
      'wind-down',
    ]);
    expect(builtInMoods.map((m) => m.sortOrder), [1, 2, 3, 4, 5, 6]);
    expect(builtInMoods.where((m) => m.isDefault).map((m) => m.id),
        ['daytime-flow']);
    expect(builtInMoods.every((m) => m.moodSetId == kDefaultMoodSetId), isTrue);
  });

  group('scene path', () {
    test('a plain file name resolves inside the audio directory', () {
      expect(scenePathFor('/audio', 'mood_peak.json'), '/audio/mood_peak.json');
      expect(scenePathFor('/audio', 'lnl/mood.json'), '/audio/lnl/mood.json');
    });

    test('anything that could leave the audio directory is refused', () {
      // The name comes from the server. A refused name is treated like a
      // missing file: the room fails closed.
      expect(scenePathFor('/audio', '../secrets.json'), isNull);
      expect(scenePathFor('/audio', 'a/../../b.json'), isNull);
      expect(scenePathFor('/audio', '/etc/passwd.json'), isNull);
      expect(scenePathFor('/audio', r'C:\x.json'), isNull);
      expect(scenePathFor('/audio', r'a\b.json'), isNull);
      expect(scenePathFor('/audio', ''), isNull);
    });
  });
}
