import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The mood set every venue is on unless it has a catalogue of its own
/// (migration 022). The six [builtInMoods] belong to it.
const kDefaultMoodSetId = '00000000-0000-4000-8000-000000000001';

/// One mood, complete: everything needed to draw it AND everything the engine
/// needs to play it.
///
/// Until migration 022 this class held only the drawing half, the PSV preset
/// lived in the engine bindings (`VenueMood`), the scene file in a map in
/// `prism_engine_native.dart`, and the three were kept in step by hand. That
/// works for one fixed catalogue and cannot express a venue with its own, so a
/// mood is now a row the server sends (`GET /moods`) and this is its shape.
class Mood {
  const Mood({
    required this.id,
    required this.name,
    required this.dotDark,
    required this.dotLight,
    required this.gradStart,
    required this.gradEnd,
    required this.bpm,
    required this.energy,
    required this.arousal,
    required this.valence,
    required this.cognitiveLoad,
    required this.readiness,
    required this.modeHint,
    required this.sceneManifest,
    this.lowpassFloorHz,
    this.moodSetId = kDefaultMoodSetId,
    this.sortOrder = 0,
    this.isDefault = false,
    this.known = true,
  });

  /// What an id resolves to when no catalogue has it.
  ///
  /// `moodById` used to THROW on an unknown id — a red screen — which was
  /// defensible while the ids were six compile-time constants and is not now
  /// that they arrive from a server. This draws as a neutral grey tile carrying
  /// the raw id, so the gap is visible rather than disguised, and [known] is
  /// false so nothing can mistake it for something playable: the engine fails
  /// closed on it (silence and an alert), never substitutes another mood.
  const Mood.unknown(this.id)
      : name = id,
        dotDark = const Color(0xFF8A8A93),
        dotLight = const Color(0xFF8A8A93),
        gradStart = const Color(0xFF8A8A93),
        gradEnd = const Color(0xFF6E6E77),
        bpm = null,
        energy = 0,
        arousal = 0.5,
        valence = 0.5,
        cognitiveLoad = 0.5,
        readiness = 0.5,
        modeHint = '',
        sceneManifest = '',
        lowpassFloorHz = null,
        moodSetId = '',
        sortOrder = 0,
        isDefault = false,
        known = false;

  /// From `GET /moods` / `GET /zones/{id}/moods`. The wire is snake_case; this
  /// is the only place it is read.
  factory Mood.fromJson(Map<String, dynamic> json) => Mood(
        id: json['id'] as String,
        name: json['name'] as String,
        dotDark: _hex(json['dot_dark'] as String),
        dotLight: _hex(json['dot_light'] as String),
        gradStart: _hex(json['grad_start'] as String),
        gradEnd: _hex(json['grad_end'] as String),
        // Null stays null. An unpulsed mood has no tempo, and the card must be
        // able to say so rather than print an invented number.
        bpm: (json['bpm'] as num?)?.toInt(),
        energy: (json['energy'] as num).toInt(),
        arousal: (json['arousal'] as num).toDouble(),
        valence: (json['valence'] as num).toDouble(),
        cognitiveLoad: (json['cognitive_load'] as num).toDouble(),
        readiness: (json['readiness'] as num).toDouble(),
        modeHint: json['mode_hint'] as String,
        sceneManifest: json['scene_manifest'] as String,
        // Null stays null here too, and it matters more: a mood with no floor
        // must render exactly the samples it rendered before floors existed.
        lowpassFloorHz: (json['lowpass_floor_hz'] as num?)?.toDouble(),
        moodSetId: json['mood_set_id'] as String,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        isDefault: json['is_default'] as bool? ?? false,
      );

  /// The inverse of [Mood.fromJson], for the on-device copy of the catalogue.
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'dot_dark': _toHex(dotDark),
        'dot_light': _toHex(dotLight),
        'grad_start': _toHex(gradStart),
        'grad_end': _toHex(gradEnd),
        'bpm': bpm,
        'energy': energy,
        'arousal': arousal,
        'valence': valence,
        'cognitive_load': cognitiveLoad,
        'readiness': readiness,
        'mode_hint': modeHint,
        'scene_manifest': sceneManifest,
        'lowpass_floor_hz': lowpassFloorHz,
        'mood_set_id': moodSetId,
        'sort_order': sortOrder,
        'is_default': isDefault,
      };

  final String id;
  final String name;

  /// Dot color on the dark theme.
  final Color dotDark;

  /// Dot color on the light theme.
  final Color dotLight;

  /// Playing gradient start/end (150°).
  final Color gradStart;
  final Color gradEnd;

  /// Null when the mood has no pulse — nothing to count.
  final int? bpm;

  /// 1–5. The bar meter on the mood card; the engine never reads it.
  final int energy;

  /// The PSV preset, each 0..1 — what the engine is pinned to for this mood.
  final double arousal;
  final double valence;
  final double cognitiveLoad;
  final double readiness;

  /// One of the hints `psv.h` defines.
  final String modeHint;

  /// The scene file, relative to the app's audio directory.
  final String sceneManifest;

  /// Engine ABI 0.6: how far the master low-pass may close. Null — which is
  /// what all six built-in moods have — means no floor at all.
  final double? lowpassFloorHz;

  /// Which catalogue this mood belongs to. A zone offers exactly one set.
  final String moodSetId;

  /// Display order within its set.
  final int sortOrder;

  /// The mood a zone on this set starts on.
  final bool isDefault;

  /// False only for [Mood.unknown].
  final bool known;

  /// "80 BPM", or null when there is no tempo to state. The one place the
  /// label is composed, so a tile, a dialog and a list cannot disagree about
  /// what an unpulsed mood shows.
  String? get tempoLabel => bpm == null ? null : '$bpm BPM';

  Color dot(Brightness b) => b == Brightness.dark ? dotDark : dotLight;

  /// Playing-state tile gradient: 150°, gradStart → gradEnd.
  LinearGradient playingGradient() => _linearGradient150([gradStart, gradEnd]);

  /// Idle mood-tile tint — §1.3: `linear-gradient(150deg, moodColor@13%,
  /// moodColor@3%)` over the palette `tint` base. The stops are
  /// pre-composited onto [over] (Flutter's BoxDecoration ignores `color`
  /// when `gradient` is set, so the CSS layering is baked in here).
  LinearGradient idleTintGradient(Brightness b, {required Color over}) {
    final c = dot(b);
    return _linearGradient150([
      Color.alphaBlend(c.withValues(alpha: .13), over),
      Color.alphaBlend(c.withValues(alpha: .03), over),
    ]);
  }

  /// Idle mood-tile border: `moodColor@22%` — §1.3.
  Color idleBorder(Brightness b) => dot(b).withValues(alpha: .22);
}

/// "#RRGGBB" → an opaque colour. The server's check constraint guarantees the
/// shape; a malformed value falls to the neutral grey rather than throwing in
/// the middle of a build.
Color _hex(String value) {
  final parsed = value.length == 7 && value.startsWith('#')
      ? int.tryParse(value.substring(1), radix: 16)
      : null;
  return Color(0xFF000000 | (parsed ?? 0x8A8A93));
}

String _toHex(Color c) {
  final rgb = c.toARGB32() & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

/// CSS `linear-gradient(150deg, …)` equivalent: 0° points up, angles run
/// clockwise, so the 150° direction vector is (sin 150°, −cos 150°).
LinearGradient _linearGradient150(List<Color> colors) {
  const deg = 150.0;
  final rad = deg * math.pi / 180;
  final dx = math.sin(rad);
  final dy = -math.cos(rad);
  return LinearGradient(
    begin: Alignment(-dx, -dy),
    end: Alignment(dx, dy),
    colors: colors,
  );
}

/// The Default set — README §1.3, in canonical order.
///
/// Compiled in so that the six every existing venue uses are known before the
/// first network call, on a backend that predates `GET /moods`, and on a tablet
/// that restarts with no connection. They are the SAME rows migration 022
/// writes: `test/built_in_moods_test.dart` holds this list to the engine
/// bindings' `VenueMood` presets, and the migration is held to both by
/// `compare_default_moods.py`. A server row with the same id replaces its
/// entry here; these are a starting point, never an override.
///
/// No built-in mood has a low-pass floor, and none may gain one here: a floor
/// changes the rendered samples, and "every existing venue sounds exactly as
/// before" is a test (`golden_render_test.cpp`), not a hope.
const builtInMoods = [
  Mood(
    id: 'morning-calm',
    name: 'Morning calm',
    dotDark: Color(0xFF2DD4A7),
    dotLight: Color(0xFF1FA982),
    gradStart: Color(0xFF34D3A8),
    gradEnd: Color(0xFF0FA37B),
    bpm: 80,
    energy: 2,
    arousal: 0.32,
    valence: 0.70,
    cognitiveLoad: 0.22,
    readiness: 0.62,
    modeHint: 'venue_morning_calm',
    sceneManifest: 'mood_morning_calm.json',
    sortOrder: 1,
  ),
  Mood(
    id: 'daytime-flow',
    name: 'Daytime flow',
    dotDark: Color(0xFF84C44A),
    dotLight: Color(0xFF699F35),
    gradStart: Color(0xFF92CE58),
    gradEnd: Color(0xFF5F9427),
    bpm: 95,
    energy: 3,
    arousal: 0.52,
    valence: 0.65,
    cognitiveLoad: 0.42,
    readiness: 0.50,
    modeHint: 'venue_daytime_flow',
    sceneManifest: 'mood_daytime_flow.json',
    sortOrder: 2,
    isDefault: true,
  ),
  Mood(
    id: 'afternoon-lift',
    name: 'Afternoon lift',
    dotDark: Color(0xFFF5A623),
    dotLight: Color(0xFFE08F0E),
    gradStart: Color(0xFFF7AE33),
    gradEnd: Color(0xFFD9820E),
    bpm: 110,
    energy: 4,
    arousal: 0.70,
    valence: 0.72,
    cognitiveLoad: 0.40,
    readiness: 0.55,
    modeHint: 'venue_afternoon_lift',
    sceneManifest: 'mood_afternoon_lift.json',
    sortOrder: 3,
  ),
  Mood(
    id: 'evening-warmth',
    name: 'Evening warmth',
    dotDark: Color(0xFFE86C9E),
    dotLight: Color(0xFFCB487E),
    gradStart: Color(0xFFEF7FAC),
    gradEnd: Color(0xFFD14380),
    bpm: 92,
    energy: 3,
    arousal: 0.62,
    valence: 0.60,
    cognitiveLoad: 0.38,
    readiness: 0.35,
    modeHint: 'venue_evening_warmth',
    sceneManifest: 'mood_evening_warmth.json',
    sortOrder: 4,
  ),
  Mood(
    id: 'peak',
    name: 'Peak',
    dotDark: Color(0xFFF0564F),
    dotLight: Color(0xFFD83A33),
    gradStart: Color(0xFFF4685F),
    gradEnd: Color(0xFFD22F28),
    bpm: 124,
    energy: 5,
    arousal: 0.92,
    valence: 0.70,
    cognitiveLoad: 0.35,
    readiness: 0.58,
    modeHint: 'venue_peak',
    sceneManifest: 'mood_peak.json',
    sortOrder: 5,
  ),
  Mood(
    id: 'wind-down',
    name: 'Wind-down',
    dotDark: Color(0xFF9A8CF0),
    dotLight: Color(0xFF6E5ED2),
    gradStart: Color(0xFFA99CF4),
    gradEnd: Color(0xFF6F5BE0),
    bpm: 68,
    energy: 1,
    arousal: 0.12,
    valence: 0.40,
    cognitiveLoad: 0.50,
    readiness: 0.20,
    modeHint: 'venue_wind_down',
    sceneManifest: 'mood_wind_down.json',
    sortOrder: 6,
  ),
];

/// Every mood this app currently knows, by id.
///
/// A plain object rather than a Riverpod provider because the lookup is called
/// from two dozen `build` methods, dialogs and label helpers that hold no
/// `ref` — the same reason `moodById` was a top-level function. The provider
/// that fills it (`moodCatalogProvider`) is what screens watch to rebuild when
/// it changes; this is only where the answer is kept.
///
/// It starts as the six [builtInMoods] and only ever GROWS within a session:
/// server rows are merged over it. Nothing is removed on a failed fetch, so a
/// dropped connection cannot turn a room's mood into an unknown one.
class MoodCatalog extends ChangeNotifier {
  MoodCatalog._();

  static final MoodCatalog instance = MoodCatalog._();

  final Map<String, Mood> _byId = {for (final m in builtInMoods) m.id: m};

  /// The mood for [id], or [Mood.unknown] — never a throw, never another mood.
  Mood byId(String id) => _byId[id] ?? Mood.unknown(id);

  bool knows(String id) => _byId.containsKey(id);

  /// Every known mood of one set, in display order.
  List<Mood> inSet(String moodSetId) => _byId.values
      .where((m) => m.moodSetId == moodSetId)
      .toList()
    ..sort((a, b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      return order != 0 ? order : a.id.compareTo(b.id);
    });

  /// Adds [moods], replacing any entry with the same id.
  void merge(Iterable<Mood> moods) {
    var changed = false;
    for (final m in moods) {
      _byId[m.id] = m;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Back to the built-in six. On sign-out, so one account's catalogue does
  /// not outlive its session on a shared tablet — and in tests.
  void reset() {
    _byId
      ..clear()
      ..addAll({for (final m in builtInMoods) m.id: m});
    notifyListeners();
  }
}

/// The mood for [id]. See [MoodCatalog.byId].
Mood moodById(String id) => MoodCatalog.instance.byId(id);
