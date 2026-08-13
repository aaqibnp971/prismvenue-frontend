/// Weather and location → a nudge on the PSV the app already pins.
///
/// ## What this changes, and what it does not
///
/// It changes the **existing** engine parameters. Nothing new is added to the
/// engine, no new dimension is introduced, and `pgae` still sees nothing but a
/// PSV — the structural firewall is untouched, which is not negotiable
/// (`firewall_includes` fails the build otherwise).
///
/// The chain is the one that already exists:
///
/// ```
///   weather + venue location
///        │  (this file)
///        ▼
///   arousal / cognitive_load / readiness            ← the SAME four dimensions
///        │  prism_set_mood_override
///        ▼
///   pgae/src/mapping.cpp  §5
///        ▼
///   cutoff_hz, gains[5], active[5], density         ← the SAME audio params
/// ```
///
/// So a wet, cold, dark evening genuinely moves the master low-pass down, lifts
/// the sub, and thins the density — because that is what raising
/// `cognitive_load` and dropping `readiness` already do. There is no second
/// code path and no weather-specific parameter anywhere in the engine.
///
/// ## Why the host and not the PCE
///
/// `prism-core` has no networking anywhere, by design — not for telemetry, not
/// for assets — so any external signal must arrive through the host. The other
/// door, a `weather.h` adapter beside `circadian.h` feeding `fusion.cpp`, needs
/// a venues PCE profile that does not exist; and it would change nothing today
/// even if written, because the app pins a mood override on every `setMood` and
/// the override replaces all four dimensions before the audio sees them. So the
/// override *is* the place where an external signal can reach the sound, and
/// this modulates it rather than competing with it. There is only one override
/// slot; this design never needs a second.
///
/// ## Why the numbers are small
///
/// The brief is that weather **colours the chosen mood and never replaces it**.
/// Peak on a grey night is still recognisably Peak. Two invariants make that
/// checkable rather than a matter of taste, and
/// `test/weather_influence_test.dart` asserts both across every mood and a grid
/// of conditions:
///
/// 1. **The layer set never changes.** The six moods were derived FROM the §5
///    mapping so each lands on a deliberate side of the density gates
///    (`pulse ≥ 0.35`, `air ≥ 0.55`, `lead ≥ 0.72`). Afternoon-lift in
///    particular sits at `lead = 0.67`, only 0.05 under its gate — so a nudge
///    much bigger than this would open a fifth layer and turn it into a
///    different mood. That margin is what sets [maxOffset], not a round number.
/// 2. **The nudged vector stays nearer its own preset than any other.** The
///    closest pair of presets (daytime-flow ↔ evening-warmth) are ~0.19 apart,
///    so the offset magnitude has to stay under ~0.095.
///
/// If you widen [maxOffset], those two tests are what will tell you which mood
/// broke first.
library;

import 'dart:math' as math;

import '../data/models/weather.dart';

/// An additive adjustment to three of the four PSV dimensions.
///
/// `valence` is absent deliberately: it is carried end to end by the whole
/// system and read by nothing (PGAE §11), so nudging it would be a change that
/// cannot be heard — the most confusing kind to leave in a codebase.
class PsvNudge {
  const PsvNudge({
    required this.arousal,
    required this.cognitiveLoad,
    required this.readiness,
  });

  /// No influence — what the engine gets when weather is unknown, unavailable,
  /// or switched off. Pinning a preset plus [none] is bit-identical to pinning
  /// the preset alone, which is what makes this feature safe to fail: no
  /// network, no reading, no change.
  static const none =
      PsvNudge(arousal: 0, cognitiveLoad: 0, readiness: 0);

  final double arousal;
  final double cognitiveLoad;
  final double readiness;

  bool get isNeutral => arousal == 0 && cognitiveLoad == 0 && readiness == 0;

  /// Euclidean magnitude, for the "still nearest its own preset" invariant.
  double get magnitude => math.sqrt(
      arousal * arousal + cognitiveLoad * cognitiveLoad + readiness * readiness);

  @override
  String toString() => 'PsvNudge(a: ${arousal.toStringAsFixed(3)}, '
      'l: ${cognitiveLoad.toStringAsFixed(3)}, '
      'r: ${readiness.toStringAsFixed(3)})';
}

/// Ceiling on `arousal` and `cognitive_load` — the two dimensions the density
/// gates are computed from.
///
/// **Derived, not chosen, and much smaller than it looks like it should be.**
/// The gates (`pulse ≥ 0.35`, `air ≥ 0.55`, `lead ≥ 0.72`) read only these two
/// dimensions, and two of the six presets sit on a knife edge above one:
///
/// | mood | gain | gate | margin |
/// |---|---|---|---|
/// | daytime-flow | `air` 0.558 | 0.55 | **0.008** |
/// | morning-calm | `air` 0.578 | 0.55 | 0.028 |
/// | afternoon-lift | `lead` 0.670 | 0.72 | 0.050 |
///
/// `air` moves by `0.5·Δarousal − 0.6·Δload`, so in the worst corner — arousal
/// pushed down while load is pushed up, i.e. a cold storm at night — a cap of
/// `c` costs it `1.1c`. Daytime-flow's 0.008 of headroom therefore forces
/// `c < 0.0073`.
///
/// That margin is a property of the PRESETS, not of this feature: daytime-flow's
/// air layer is on by 0.008, so anything that perturbs the vector at all can
/// flip it. Worth knowing before tuning `VenueMood` — see the note in
/// `CLAUDE.md`. It is also why the weather's weight lives on [maxDepthOffset]
/// below instead.
const double maxTintOffset = 0.006;

/// Ceiling on `readiness`, which can be far larger — and is where the audible
/// part of this feature actually lives.
///
/// `readiness` appears in **no gate**. The only thing it drives is
/// `sub = clamp01(0.5 − 0.6·readiness)`, and `sub` is always on, so moving it
/// cannot change which layers play however far it travels. It is also the
/// loudest stem: `host_roundtrip_test.dart` notes that on a single scene
/// wind-down's low readiness drives sub to 0.68 against peak's 0.45, and that
/// this dominates RMS.
///
/// So a dark, wet night lands as a genuinely heavier bottom end — `sub` moving
/// by up to 0.048 — while the layer set and the mood's identity are untouched
/// by construction rather than by a carefully chosen constant. The engine gets
/// no louder: master gain, the −3 dBFS limiter and the volume guardrails are
/// all downstream and all unchanged.
///
/// Bounded by the nearest-own-preset invariant rather than by a gate. The
/// closest pair of presets (daytime-flow ↔ evening-warmth) differ by 0.15 in
/// readiness alone, and past about 0.12 a nudged daytime-flow starts to sit
/// nearer evening-warmth than itself. 0.09 keeps real margin under that.
///
/// Worth 0.054 on the `sub` gain end to end, which after the engine's
/// `amp = 0.4·x^1.5` curve is roughly 1.4 dB on the loudest stem — a room that
/// audibly sits lower on a wet night without any change in overall level.
const double maxDepthOffset = 0.09;

/// Weather and location → the nudge.
///
/// Null in, [PsvNudge.none] out. That is the whole failure story: no network,
/// no address to geocode, an API that is down, a venue at sea — the room plays
/// exactly what it plays today.
///
/// ### What each input does to the sound, and why
///
/// * **Cloud / precipitation → up on `cognitive_load`.** In the §5 mapping,
///   load is the dimension that closes the room down: `brightness` falls
///   (`-0.8l`), so the master low-pass drops; `density` falls (`-1.0l`); `bed`
///   RISES (`+0.6l`) while `lead` recedes hardest (`-0.9l`). That is exactly
///   what a grey, wet sky should sound like — more interior, warmer, less
///   sparkle. It is the main lever and the one you will hear.
/// * **Daylight → up on `arousal`, dark → down.** Straight lift and damp:
///   arousal raises brightness (`+0.9a`), density (`+0.9a`) and every voiced
///   layer. This is the one genuinely LOCATION-derived term — `is_day` comes
///   from the venue's own sunrise and sunset, which is a latitude-and-season
///   answer, not a clock answer. A December evening in Reykjavík and one in
///   Dubai are different facts about the room.
/// * **Night and heavy cloud → down on `readiness`.** `sub` is the one gain
///   that moves on readiness alone (`0.5 - 0.6r`), so dropping it lifts the low
///   end. A dark room gets a heavier bottom without getting louder — the
///   limiter and master gain are untouched.
///
/// Note what is deliberately absent: nothing here scales volume. Loudness is a
/// venue guardrail (S05-2), set by a human, and weather has no business
/// touching it.
PsvNudge nudgeFor(WeatherReading? reading) {
  if (reading == null) return PsvNudge.none;

  // Precipitation reads as a heavily covered sky whatever the cloud percentage
  // claims — it can rain under a reported 60%, and the room should still sound
  // enclosed.
  final overcast = _clamp01(math.max(
    reading.cloudCover,
    reading.condition.isPrecipitating ? 0.85 : 0.0,
  ));

  // Fog is the strongest "enclosed" signal there is, and it routinely reports
  // low cloud cover because the cloud is at ground level rather than above it.
  final enclosed = reading.condition == SkyCondition.fog
      ? math.max(overcast, 0.9)
      : overcast;

  // How far below comfortable, normalised over a 15° span. Cold rooms want a
  // warmer, closer sound; above ~22°C this contributes nothing rather than
  // inverting, because "hot" is not the opposite of "cosy" in the way the
  // mapping is shaped.
  final chill = _clamp01((22.0 - reading.temperatureC) / 15.0);

  final day = reading.isDay;

  return PsvNudge(
    // The tint: a small, gate-safe move on the master low-pass and the voiced
    // layers' balance.
    arousal: _tint(-0.003 * enclosed + (day ? 0.002 : -0.003)),
    cognitiveLoad: _tint(0.004 * enclosed + 0.002 * chill),
    // The depth: where the weather is actually heard. Gate-free, so it runs an
    // order of magnitude larger than the tint and is scaled to reach the cap
    // in the worst corner rather than stopping short of it.
    readiness: _depth((day ? 0.0 : -0.055) - 0.035 * enclosed),
  );
}

double _tint(double v) => v.clamp(-maxTintOffset, maxTintOffset);

double _depth(double v) => v.clamp(-maxDepthOffset, maxDepthOffset);

double _clamp01(double v) => v.clamp(0.0, 1.0);
