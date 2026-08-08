# Keeping the room playing

Failure modes of the Prism player on a real venue device, and what to do about
each. Companion to `SOUND_ENGINE.md`, which covers how the engine is wired;
this covers everything that stops it running.

The symptom is always the same and always bad: **the room goes quiet and nobody
notices.** No user is watching the player. Staff are working. The first person
to notice silence is a customer, and by then it has been quiet for a while. So
every case below is judged on two questions — *can we prevent it?* and *if not,
how fast do we recover and who finds out?*

Cases are grouped by what actually fixes them, because that is what decides who
owns the work:

| | Fix lives in | Can we automate it? |
|---|---|---|
| T1.1 OEM battery manager | device settings + our service config | partly |
| T1.2 Bundled cleaner | device settings only | no — see below |
| T1.3 Shared-device audio focus | our code | yes, but never completely |

---

## T1.1 — OEM battery manager kills the process

**HyperOS (Xiaomi), ColorOS (Oppo), Realme UI, Funtouch (vivo), One UI
(Samsung).**

### What is actually happening

On AOSP, a foreground service declaring `foregroundServiceType="mediaPlayback"`
is protected — the platform will not reclaim it to save battery. Every OEM above
runs a *second* policy layer on top of AOSP that does not honour that contract.
It kills on its own idle heuristic, typically screen-off plus no recent user
interaction, and it applies that heuristic to audio playback because from its
point of view an app nobody has touched in two hours is a battery leak.

Stock Android does not do this. Pixels do not do this. Emulators do not do this.
**Which is why this will never reproduce on a development device** — the entire
class of bug is invisible until it is on a customer's counter.

### The fix, in layers

None of these is sufficient alone.

**1. Foreground service with a live MediaSession.** Declare
`FOREGROUND_SERVICE_MEDIA_PLAYBACK` and the `mediaPlayback` service type, and
hold an **active** `MediaSession` with a playing `PlaybackState` for as long as
audio is intended. Several OEM whitelists key off "does this app own a live
media session", not off the service type. A foreground service with no session
reads to them as a long-lived notification, and notifications are killable.

**2. Battery-optimisation exemption.** The one part that is programmatic and
verifiable:

```kotlin
val pm = getSystemService(POWER_SERVICE) as PowerManager
if (!pm.isIgnoringBatteryOptimizations(packageName)) {
    startActivity(Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                         Uri.parse("package:$packageName")))
}
```

Play policy restricts `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`, but continuous
media playback is an accepted justification. Declare it as such.

**3. OEM autostart lists — user-only.** These cannot be set by code, at all.
Deep-link the user to the exact screen and fall back to app details on
`ActivityNotFoundException`, because component names move between versions:

| OEM | Component |
|---|---|
| Xiaomi / HyperOS | `com.miui.securitycenter/com.miui.permcenter.autostart.AutoStartManagementActivity`<br>plus `com.miui.powerkeeper/.ui.HiddenAppsConfigActivity` → *No restrictions* |
| ColorOS / Realme UI | `com.coloros.safecenter/.startupapp.StartupAppListActivity`<br>(older builds: `com.coloros.safecenter/.permission.startup.StartupAppListActivity`) |
| Funtouch | `com.vivo.permissionmanager/.activity.BgStartUpManagerActivity` |
| One UI | Settings → Battery → *Background usage limits* → **Never sleeping apps** |

```kotlin
fun openOemAutostart(ctx: Context) {
    for (c in oemComponents) {                    // table above, by Build.MANUFACTURER
        try { ctx.startActivity(Intent().setComponent(c)); return }
        catch (_: ActivityNotFoundException) { }  // component renamed — try the next
    }
    ctx.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                             Uri.parse("package:${ctx.packageName}")))
}
```

**4. Assume you lose anyway, and recover on relaunch.** This is where the
existing architecture already pays for itself. `engine/engine_controller.dart`
listens to `nowPlayingProvider` with `fireImmediately: true`, so a restarted
process re-reads desired state from the backend and resumes the correct mood
with no recovery code of its own. Keep it that way: **never drive the engine
from a button press.** The moment a tap is the only thing that starts audio, a
killed process stays silent until a human intervenes.

---

## T1.2 — Bundled cleaner or phone-manager kills on a schedule

**Xiaomi Security, Samsung Device Care, Oppo/Realme Phone Manager,
vivo iManager, Huawei Phone Manager.**

### Why this is not a duplicate of T1.1

It lives in a different settings tree, which is why it gets missed — but the
important difference is technical. The cleaner issues a **force-stop**, not a
kill. A force-stop puts the package into the *stopped state*:

- `START_STICKY` does **not** restart the service.
- Scheduled `AlarmManager` alarms are cancelled.
- Broadcasts are not delivered (absent `FLAG_INCLUDE_STOPPED_PACKAGES`).
- `WorkManager` jobs do not run.

**Nothing inside the app can recover from it.** The package stays stopped until
a human taps the icon. T1.1 you can self-heal from; T1.2 you cannot. That single
distinction should drive how you treat them.

### The fix

**Prevention — two one-time user actions:**

- **Lock the app in recents.** On MIUI/ColorOS, long-press the app card in the
  recents view → padlock. This is a *separate* mechanism from autostart, it is
  one tap, and it is the highest-yield fix on those devices. Put it in the
  install checklist with a screenshot, not as a sentence of prose.
- **Turn off scheduled auto-clean / deep clean** inside the cleaner app itself.

**Detection — because prevention is not guaranteed and recovery is impossible.**
The fleet has to notice on the device's behalf. The schema already supports it:
`devices.online` plus `zone_guardrails.offline_alert_minutes`.

> **Blocked today.** There is no telemetry ingest — nothing writes
> `zone_state.reported_*`, so a force-stopped player still reads as online
> forever and no alert fires. Until ingest lands, **T1.2 is completely silent**.
> That makes ingest a prerequisite for this case rather than a nice-to-have, and
> it is the strongest argument for building it.

---

## T1.3 — Shared device: audio focus contention

**Calls, WhatsApp, POS software and appointment systems on the same handset.**

### This one is the OS being right

T1.1 and T1.2 are the platform breaking its own contract. This is the platform
honouring it. A call *must* take the earpiece; a card terminal *must* beep. The
goal is not to win focus — it is to lose it gracefully and come back
automatically, with nobody present to press play.

### The contract, and the one row where the default is wrong

Request focus with `AudioAttributes(USAGE_MEDIA, CONTENT_TYPE_MUSIC)`:

| Event | Typical source | Standard media app | **Prism** |
|---|---|---|---|
| `LOSS_TRANSIENT_CAN_DUCK` | WhatsApp ping, POS beep | duck | **duck, never pause** |
| `LOSS_TRANSIENT` | phone or VoIP call | pause; resume on `GAIN` | same |
| `GAIN` | interruption over | resume | same |
| `LOSS` | another media app | **stop; wait for the user** | **pause, then retry with backoff** |

The last row is the deviation and it is deliberate. A music app stops on
permanent loss because a human will press play again. **In a venue there is no
human — the room is the user.** So on `LOSS`, pause but keep trying to
reacquire: 5 s, 15 s, 30 s, then every 60 s, resuming the moment focus is
granted. Cap the backoff so you never end up in a focus-fight loop with the
other app.

Two flags that bite:

- **Target SDK 31+ ducks automatically.** To control the duck level yourself you
  must set `setWillPauseWhenDucked(false)` and attenuate in the engine.
- **`setAcceptsDelayedFocusGain(true)`**, or launching during a call silently
  never starts audio at all.

### The change this forces in `engine_controller.dart`

Today `_onPlayback` and `_onTakeover` both call `_engine.resume()`, and neither
knows about audio focus. Add focus as a third input and they will contradict
each other — a mood change arriving mid-call would resume audio into the call.

Resolve it the way the backend already resolves desired-vs-reported: **three
inputs, one resolver, a single writer.**

```dart
bool get _shouldSound =>
    _desiredPlaying   // server truth: not paused, not taken over
    && _hasFocus      // OS: focus granted
    && !_ducked;      // OS: transient duck in effect

// Every listener sets exactly one field and calls this.
// Nothing else in the app touches the engine.
void _reconcile() => _shouldSound ? _engine.resume() : _engine.silence();
```

Focus is a *local* condition; mood and pause are *remote* truth. Keeping them as
separate inputs to one decision — rather than two callers racing — is what
prevents "the room came back silent and nobody can say why".

**Only auto-resume when `_desiredPlaying` is true.** If a manager paused the
room during a call, regaining focus must not un-pause it.

### Ducking needs hysteresis, or a POS strobes the room

A card terminal beeping once per transaction fires `CAN_DUCK` every few seconds.
Naïve ducking makes the music pulse all evening, which is worse than either
extreme:

- Ignore duck requests shorter than ~300 ms.
- Duck to a **defined floor** (−12 dB, or reuse the `quiet_hours_cap_pct` idea),
  never to silence.
- **Ramp**, do not snap: ~200 ms down, ~1–2 s back up.
- Hold the ducked level ~1 s after `GAIN` so back-to-back beeps do not retrigger
  the ramp.

### iOS equivalent

`AVAudioSession` category `.playback`. Handle `interruptionNotification`:
`.began` → silence; `.ended` → resume **only if** the payload carries
`.shouldResume`. Also handle `mediaServicesWereResetNotification` — rare, but it
tears down the entire audio stack, and an FFI engine must fully rebuild its core
rather than calling `resume()`. Missing that one presents as "audio never comes
back until the app is restarted", which is a miserable bug to chase.

### Surface it, and consider reusing Takeover

A manager needs to tell "quiet because someone is on a call" from "the player
died". That is `zone_state.reported_*` and `status_detail` — same ingest
dependency as T1.2.

A sustained focus loss **is** a local, involuntary takeover. The concept already
exists, staff already understand "someone is using the speakers", and
`endTakeover` semantics already exist. Rather than inventing a parallel state,
consider reporting focus loss beyond ~2 minutes in that same language. Short
interruptions stay invisible — nobody wants an alert because someone answered
the phone.

### A suggested `EngineStatus` addition

`prism_engine.dart` already distinguishes `unsupported` from `failed` so the UI
can explain itself instead of just looking broken. Focus loss deserves the same
treatment: `silenced` currently means both "deliberately silent" (pause,
takeover) and would come to mean "involuntarily silent" (focus lost). Split it —
add `interrupted` — so the Floor screen can say *why* the room is quiet.

---

## Cross-cutting

### Setup flow, run once per device

At zone pairing, ship a **"Set up this player"** step that:

1. Auto-checks what is checkable — battery-optimisation exemption, notification
   permission, media session active, audio focus obtainable.
2. Shows a per-OEM checklist, with screenshots, for what is not — autostart,
   recents lock, scheduled clean.
3. **Re-runs on every app start** and surfaces a persistent warning on the Floor
   screen while any item is unmet. Without this, a setting gets toggled off in
   six months and nobody connects it to the silence.

### The hardware answer

T1.1 and T1.2 are defeated by settings. **T1.3 cannot be — the contention is
legitimate.** Every mitigation above lowers the frequency and shortens recovery;
none removes the failure.

For devices Prism supplies, provision as **Android Enterprise device-owner** in
kiosk/lock-task mode: battery exemptions become programmatic, cleaner apps are
absent or disabled, and the device boots straight into the player. That makes
T1.1 and T1.2 *disappear* rather than being mitigated, and removes T1.3 entirely
by removing the other apps.

Where a customer insists on their own handset, say plainly what they are buying:
on a shared phone the room will go quiet sometimes, and Prism's job is to bring
it back within seconds without anyone noticing. On a dedicated device it does
not happen at all.

### What is and is not built

| | Status |
|---|---|
| Engine follows server state, so relaunch resumes automatically | **done** — `engine_controller.dart` |
| Engine is a silent no-op on web | **by design** — `prism_engine_stub.dart` |
| Audio focus handling | **not built** |
| Foreground service + MediaSession | **not built** |
| Setup / permissions flow | **not built** |
| Telemetry ingest, so a dead player is visible | **not built** — blocks detection for T1.2 and T1.3 |
| `offline_alert_minutes` guardrail | schema and API exist; nothing feeds them |
