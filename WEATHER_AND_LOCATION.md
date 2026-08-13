# Weather and location in the sound engine

How a venue's sky reaches the speakers, which engine parameters it moves, by how
much, and why it is not allowed to move them further.

Read `CLAUDE.md` § *The sound engine* first if you have not — this document
assumes the PSV → PGAE split and the §5 mapping.

---

## The short version

Weather and location change the **existing** engine parameters. Nothing was
added to the engine. There is no weather-specific coefficient, no weather branch
in the render path, and `pgae` still sees nothing but a PSV.

What actually happens is that the host adjusts the vector it was already pinning:

```
venue address ─geocode(once)→ lat/lon ─Open-Meteo→ cloud, is_day, temp, WMO code
                                                            │
                                          lib/engine/weather_influence.dart
                                                            │  PsvNudge
                                                            ▼
                      VenueMood preset  +  nudge   ← the SAME four dimensions
                                                            │  prism_set_mood_override
                                                            ▼
                                          core/src/prism_core.cpp :: publish_psv
                                                            ▼
                                              pgae/src/mapping.cpp  §5
                                                            ▼
              cutoff_hz · gains[5] · active[5] · density   ← the SAME audio params
```

So a wet, cold, dark evening genuinely lowers the master low-pass and lifts the
sub — because that is what raising `cognitive_load` and lowering `readiness`
already did before anyone thought about weather.

---

## Why it enters here and nowhere else

`CLAUDE.md` names four possible doors. This is the first one, and the others were
not chosen for concrete reasons:

| door | why not (yet) |
|---|---|
| **Host nudges the pinned PSV** | ← **this is what is built** |
| New PCE adapter (`weather.h` beside `circadian.h`) | Needs a venues PCE profile, which does not exist. And it would change nothing even if written: the app pins a mood override on every `setMood`, and the override replaces all four dimensions, so every PCE output is discarded before the audio sees it. |
| Weather picks a different scene | Biggest audible effect by far, and zero engine change — but it needs new manifests and stem sets per condition. No Stem Production Specification exists, so there is no audio to point it at. |
| A new PSV dimension | A spec change (PSV §10, additive MINOR, neutral 0.5, ships at `confidence = 0`). Only worth it alongside the PCE adapter above. |

Two constraints shaped this and are not negotiable:

- **`prism-core` has no networking, anywhere, by design** — not for telemetry,
  not for assets. Any external signal must arrive through the host. That is why
  the fetch lives in Flutter and the engine never learns that weather exists.
- **`pgae` may see nothing but a PSV.** `firewall_includes` fails the build
  otherwise. Nothing here goes near that boundary.

There is also only ever **one override slot**. A design that pinned weather
separately would fight the manager's mood pin for it. This one does not compete:
it adjusts the pin that is already there.

---

## Where location comes in

Location matters twice, and neither is the device's location.

1. **Which sky.** Coordinates come from `venues.address`, geocoded once and
   cached. An owner in Dubai reviewing their London venue hears **London** —
   device GPS would break the estate flow entirely.
2. **`is_day`.** Open-Meteo computes this from the venue's own sunrise and
   sunset, which is a latitude-and-season answer rather than a clock answer. A
   December evening in Reykjavík and one in Dubai are different facts about the
   room, and this is the one term that is genuinely location-derived rather than
   weather-derived.

This is separate from the *other* thing location already did, which is unchanged:
`venues.timezone` drives migration 010's `pg_cron` job, deciding **which daypart
is current** and therefore which mood plays. That picks the mood; this colours
it.

---

## What each input does, and why that direction

From the §5 mapping (`pgae/src/mapping.cpp`), with `a`, `l`, `r` as the
confidence-weighted dimensions minus 0.5:

```
brightness = clamp01(0.55 + 0.9a − 0.8l)      cutoff_hz = 300 · (12000/300)^brightness
density    = clamp01(0.5  + 0.9a − 1.0l)
bed   = clamp01(0.6 + 0.6l)      sub = clamp01(0.5 − 0.6r)
pulse = clamp01(0.5 + 0.7a − 0.6l)
lead  = clamp01(0.5 + 0.4a − 0.9l)
air   = clamp01(0.5 + 0.5a − 0.6l)
gates: bed + sub always on;  pulse ≥ 0.35,  air ≥ 0.55,  lead ≥ 0.72
```

| input | dimension | effect on the sound |
|---|---|---|
| cloud cover, precipitation, fog | `cognitive_load` ↑ | Closes the room down: cutoff falls (`−0.8l`), density falls, `bed` **rises** (`+0.6l`), `lead` recedes hardest (`−0.9l`). Grey skies sound more interior. |
| daylight | `arousal` ↑ (dark: ↓) | Straight lift and damp — brightness, density and every voiced layer. |
| darkness, heavy cloud | `readiness` ↓ | Lifts `sub`, the only gain that moves on readiness alone. A heavier bottom without getting louder. |
| cold | `cognitive_load` ↑ | Same closing-down as cloud. Measured from a 22 °C comfort point; above it the term contributes nothing rather than inverting. |

Two deliberate non-effects:

- **Nothing scales volume.** Loudness is a venue guardrail (S05-2) set by a
  human. Master gain, the −3 dBFS limiter and the volume band are all downstream
  and untouched.
- **`valence` is not nudged.** It is carried end to end and read by nothing
  (PGAE §11), so moving it would be a change nobody can hear — the most
  confusing kind to leave in a codebase.

---

## How much — the actual numbers

Measured, not estimated. `sub` is the loudest stem, which is why the low end is
where this is heard.

### daytime-flow

| sky | cutoff | Δ | `sub` | density | layers |
|---|---|---|---|---|---|
| no reading | 3088 Hz | — | 0.500 | 0.598 | 4 |
| clear warm day | 3108 Hz | +0.7% | 0.500 | 0.600 | 4 |
| overcast cool day | 3028 Hz | −1.9% | 0.521 | 0.592 | 4 |
| clear night | 3049 Hz | −1.3% | 0.534 | 0.594 | 4 |
| cold storm night | 2974 Hz | −3.7% | 0.554 | 0.587 | 4 |

End to end that is **+0.054 on `sub`**, which after the engine's
`amp = 0.4 · x^1.5` curve is about **1.4 dB on the loudest stem**, plus a small
darkening of the filter. The layer count never changes.

### peak is a special case

`peak`'s brightness computes to 1.048, which `clamp01` pins at 1.0 — the top of
the 300 Hz…12 kHz range. **Its cutoff cannot move**, in any weather, because the
filter is already wide open. Its weather is entirely in the low end
(`sub` 0.452 → 0.488). This is not a defect; a test pins it down so nobody
"fixes" it.

---

## Why the numbers are small — the two invariants

Both are asserted in `test/weather_influence_test.dart` against the real mapping,
across every mood and a grid of extreme conditions.

**1. The layer set never changes.** The six moods were derived *from* the mapping
so each lands on a deliberate side of the density gates. Two sit on a knife edge:

| mood | gain | gate | margin |
|---|---|---|---|
| daytime-flow | `air` 0.558 | 0.55 | **0.008** |
| morning-calm | `air` 0.578 | 0.55 | 0.028 |
| afternoon-lift | `lead` 0.670 | 0.72 | 0.050 |

`air` moves by `0.5·Δarousal − 0.6·Δload`, so a cap of `c` on the gate-bearing
dimensions costs it `1.1c` in the worst corner. Daytime-flow's 0.008 of headroom
forces `c < 0.0073` — hence `maxTintOffset = 0.006`. That margin is a property of
the **presets**, not of this feature: anything that perturbs the vector at all
can flip daytime-flow's air layer. Worth knowing before retuning `VenueMood`.

This is also why the weather's weight lives on `readiness` instead:
**`readiness` appears in no gate**, so `maxDepthOffset = 0.09` is safe by
construction rather than by a carefully chosen constant.

**2. A nudged mood stays nearer its own preset than any other.** The closest pair
(daytime-flow ↔ evening-warmth) are ~0.19 apart, and past about 0.12 of readiness
a nudged daytime-flow starts to sit nearer evening-warmth than itself.

The first draft used a flat 0.04 cap. The layer-set test caught it immediately:
morning-calm lost its air layer in a storm, which is not colouring a mood, it is
playing a different one.

### If you want it more dramatic

That is a deliberate widening of the brief, not a tuning tweak. In rough order of
effect per unit of work:

1. **A different scene per condition** — different stems entirely. Needs audio
   content that does not exist yet, but no engine change at all.
2. **Let weather cross the gates** — change invariant 1 first, and accept that a
   layer appearing and disappearing with the sky is a mood-level change.
3. **Widen the preset margins** — daytime-flow's 0.008 above the air gate is the
   binding constraint on the tint. Moving it buys room for everything else, but
   `tests/pce/parity_test.cpp` is not involved here and `VenueMood` is duplicated
   in `harness/main.cpp`, so both must move together.

---

## Where the code lives

| file | role |
|---|---|
| `lib/data/models/weather.dart` | `WeatherReading`, `SkyCondition`, WMO decoding |
| `lib/data/repositories/weather_repo.dart` | The boundary + `weatherProvider`, scoped to the session's venue |
| `lib/data/api/open_meteo_weather_repo.dart` | Geocode (cached, once per venue) + 15-minute forecast poll |
| `lib/data/mock/mock_weather_repo.dart` | Per-venue seeded skies for `PRISM_USE_MOCKS=true` |
| **`lib/engine/weather_influence.dart`** | **The whole policy: `nudgeFor(reading)` → `PsvNudge`** |
| `lib/engine/prism_engine.dart` | `applyInfluence(PsvNudge)` on the interface |
| `lib/engine/prism_engine_native.dart` | `_pin()` — the single place the vector is published |
| `lib/engine/engine_controller.dart` | Follows `weatherProvider` like any other state |
| `prism-core/…/prism_core_bindings.dart` | `VenueMood.adjusted(...)` — same mood, adjusted dimensions |

`VenueMood.adjusted` preserves `id` and `mode_hint` deliberately. This is still
Peak; it is Peak on a wet night. The hint names *which* mood is playing, and a
consumer that changed behaviour because the weather changed would be reading it
as something it is not.

---

## Failure behaviour

**Every failure is silent and total: no reading → `PsvNudge.none` → exactly the
sound the app made before this existed.** Pinning `preset + none` is
bit-identical to pinning the preset, and a test asserts it.

That covers: no address on the venue, a geocoder that cannot place it, no
network, an API that is down or rate-limited, a WMO code this build has never
seen, and web builds (where the engine is a no-op anyway).

Losing the weather mid-session returns the room to its plain preset rather than
freezing it on the last sky seen — `applyInfluence(none)` is a normal, ramped
re-pin.

---

## Verifying it yourself

**The mapping assertions** — no device, milliseconds. This is where "input X
moves parameter Y" belongs:

```bash
flutter test test/weather_influence_test.dart
```

The test file carries a mirror of §5 so it can assert on real `cutoff_hz`,
`gains[]`, `active[]` and `density` rather than on the offsets that produced
them. `pgae/src/mapping.cpp` stays authoritative — it is the code that renders,
and `ctest -R PgaeMapping` covers it. If the two disagree, the C++ is right.

**By ear, on mocks** — no backend, no network, no credentials. `MockWeatherRepo`
seeds three different skies, so walking the estate switches sky along with venue:

```bash
flutter run -d windows --dart-define=PRISM_USE_MOCKS=true
```

Marina Café is clear and warm, Dockside is a cold storm at night, Harbor House is
overcast. Sign in as `owner@…`, then Venues → a venue → "Open floor" and listen
to the bottom end as you move between them. The Floor hero's context line shows
which sky is in effect.

**Two traps** carried over from the engine docs, both still apply: skip the first
~2 s of any render (master fade-in 0.5 s, level smoothing 0.25 s, cutoff 0.6 s),
and remember the stems are dark — 0.00–0.14% of their energy is above 4 kHz, so a
brightness change will not show up in high-frequency energy the way you expect.

---

## What is sent, and to whom

Open-Meteo receives the venue's **address text** (once, to the geocoder) and its
**coordinates** (every 15 minutes, to the forecast API). No user identity, no
session token, no zone or venue id.

The weather repository deliberately does **not** use `ApiClient`: that attaches
the Supabase bearer token and an `Idempotency-Key` to every request, and sending
a session token to `open-meteo.com` would be a straightforward credential leak.
It uses its own bare `http.Client`.
