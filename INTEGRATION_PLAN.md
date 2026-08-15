# Prism Venues — frontend ⇄ backend integration plan

**Status:** ✅ implemented. All six decisions below were confirmed and built.
**Date:** 2026-07-28
**Frontend baseline verified:** `flutter test` → 32/32 passing, on mocks, before any change.
**After integration:** `flutter analyze` clean · `flutter test` 77/77 · backend `pytest` 116/116.

---

## Outcome

| Decision | Resolution |
|---|---|
| §6 Scope | Thin vertical slice first, then every remaining flow. All five repositories are now API-backed. |
| §5.4 Auth model | FastAPI proxies Supabase Auth. RLS enforced by the database via `SET LOCAL ROLE` + JWT claims per transaction. |
| §5.1 Reset security | Fixed. `verifyResetCode` returns a single-use token; `saveNewPassword` requires it. Contract and Dart interface both changed. |
| §4.1 Zone scoping | Client-held `currentZoneIdProvider`, seeded from a `context` object the server returns at sign-in. No repository signature or widget test changed. |
| §5.3 "At close" | Its own `takeover_alert_at_close` boolean, not a sentinel minute value. |
| §5.2 Daypart times | Real time picker, reusing the existing S05-12 dial with a 5-minute wheel added (`minuteStep`; open hours keep the hour-only default, their wire fields being `open_hour`/`close_hour` smallints). `start_local`/`end_local` are the source of truth; `range_label` is derived server-side. |
| §5.5 Error states | Minimal inline surface built from existing palette tokens — `ErrorNote` for forms, a snackbar for mutations. Marked as a placeholder for the designer. |

Everything below is the analysis as written before implementation, kept
unedited as the record of what was found and why each call was made.

---

## 0. The headline finding — read this first

**There is no backend.** Not stubbed, not partial — it does not exist.

I searched the entire `D:\ANP` tree for FastAPI or Supabase code. What I found:

| Location | What it actually is |
|---|---|
| `D:\ANP\Prismvenue_frontend` | The Flutter app. Runs on in-memory mocks. No HTTP client, no auth token handling, no `.env`. |
| `~\Downloads\schema.sql` | A **specification**. Runnable DDL, but never run — no database exists. |
| `~\Downloads\api-contract.md` | A **specification**. 30 endpoints described. Zero implemented. |
| `D:\ANP\Dashboard For Business\supabase\` | A different product entirely (Maintenance Business Tracker). Not Prism. |
| `D:\ANP\prism-core`, `prism-render`, `prism-scenes` | The C++ audio engine and its scene JSON. The other half of Prism — not the venue control plane. |

So the objective as written — "wire the frontend to the backend" — has a missing prerequisite: **the backend has to be built first.** The two documents you attached are a good, coherent design for it, but they are drawings, not a building.

This changes the shape of the work, so I've stopped here rather than assume which way you want to go. See §6 for the decision.

---

## 1. What the frontend actually is (verified, not assumed)

Confirmed against the repo — this matches what you described:

- **Flutter** 3.44.6 / Dart 3.12.2, Riverpod 3.3.2, go_router 17.3.0. iPad-landscape first, dark default.
- **Repository seam is real and clean.** Five abstract interfaces in `lib/data/repositories/`, each with a Riverpod provider constructing a mock. Swapping in an API implementation is a provider override in `main.dart` — exactly as `BACKEND_INTEGRATION.md` describes.
- **30 repo methods across 5 interfaces.** I counted them independently: Auth 4, Playback 9, Schedule 7, Venue 5, Settings 5 = 30. The api-contract's claim of a 1:1 match with 30 endpoints is **correct**.
- **10 of those methods are streams** (`watch*`), 20 are one-shot futures.
- **Three-rung control model** (Auto / Mood Nudge / Takeover) is present as: schedule `auto` flag + mood grid + `/takeover` flow.

### What is *not* true of the frontend

Three things worth correcting up front, because they change the plan:

1. **The repo interfaces are not zone-scoped.** `watchNowPlaying()`, `watchGuardrails()`, `watchToday()` take **no arguments**. Every corresponding endpoint is `/v1/zones/{id}/...`. There is no zone picker anywhere in the UI. See §4.1 — this is the single biggest structural gap.
2. **Mock seed data is wired into eight production screens**, not just the mocks. `Seed.venueName` ("Marina Café") and `Seed.venueStatus` ("Main floor · online") are rendered directly in the top bar of Floor, Schedule, Takeover, Active takeover, Settings, Volume policy, Transitions, Open hours, Zone detail, and Venue screens. `lib/app/router.dart:179` routes managers to `Seed.managerVenueId`. Deleting the mocks is not enough — this is real app code that must change.
3. **There is no token handling of any kind.** No storage, no `Authorization` header, no refresh, no rehydration. `sessionProvider` is in-memory, so a page reload signs the user out. `AuthRepo.signIn` returns a `User` with **no field for a token** — the contract's `token` has nowhere to go.

---

## 2. Backend state — what exists, stubbed, missing

| Area | State |
|---|---|
| Database schema | **Spec only.** `schema.sql` defines 12 tables + RLS + column grants. Never executed. No Supabase project referenced anywhere in the repo. |
| Migrations | **Missing.** The spec names a 4-migration order (001–004) but no migration files exist. |
| REST API | **Missing entirely.** 30 endpoints specified, 0 written. No FastAPI project, no `requirements.txt`/`pyproject.toml`, no `main.py`. |
| Realtime transport | **Missing and unspecified.** The contract says `now`/`noise`/`takeover` "should be backed by a stream (SSE or WebSocket)" but names no endpoint for it. This is a 31st endpoint that has to be invented. |
| Auth | **Missing + architecturally ambiguous.** See §5.4. |
| Telemetry ingest | **Missing.** `zone_state.reported_*` columns and the `prism_ingest` role exist in the spec, but nothing writes them. Without an ingest path, every zone is permanently "pending" (`in_sync` false) and `noise`/`context_line` are always null. |
| Device/MQTT layer | **Out of scope** per both docs. Fine — but it means `device_online` is always false and `status` is always `pending_device` until `prism-core` devices are wired. |

**Consequence worth stating plainly:** even a perfectly built backend from this spec will serve a system where no device ever reports. The app will render, mutations will be accepted and persisted, but "is it actually playing in the room" stays unanswerable until the device/ingest side exists. That's expected at this stage — I just don't want "end-to-end" to imply audio comes out of a speaker.

---

## 3. Screen → repo method → endpoint map

Flags: **MATCH** (shapes line up) · **MISMATCH** (exists but needs mapping or a decision) · **MISSING** (no endpoint, or client cannot supply what the endpoint needs).

### AuthRepo

| # | Repo method | Screen | Endpoint | Flag | Note |
|---|---|---|---|---|---|
| 1 | `signIn` | `sign_in_screen` | `POST /v1/auth/sign-in` | **MISMATCH** | Body/response shapes match (`role` is already `floor\|manager\|owner`, no mapping layer needed). But the response `token` has nowhere to live — `User` has no token field and there is no storage. App-level change required. |
| 2 | `sendResetCode` | `reset_email_screen` | `POST /v1/auth/reset/send-code` | MATCH | |
| 3 | `verifyResetCode` | `reset_code_screen` | `POST /v1/auth/reset/verify` | **MISMATCH** | Returns `{}` — no proof-of-verification token. See §5.1. |
| 4 | `saveNewPassword` | `reset_password_screen` | `POST /v1/auth/reset/save-password` | **MISMATCH — security** | Takes `{email, password}` with no proof the code was ever verified. See §5.1. |

### PlaybackRepo — all zone-scoped, see §4.1

| # | Repo method | Screen | Endpoint | Flag | Note |
|---|---|---|---|---|---|
| 5 | `watchNowPlaying` | `floor_screen` hero | `GET /v1/zones/{id}/now` | **MISMATCH** | Field shapes MATCH (`mood_id`, `paused`, `paused_by`, `context_line`). Missing zone id + no stream transport. |
| 6 | `watchNoise` | `noise_meter` | `GET /v1/zones/{id}/noise` | **MISMATCH** | Same. Backed by `zone_state.reported_noise_pct` — null until telemetry exists. |
| 7 | `setMood` | `mood_grid`, `confirm_vibe_dialog` | `POST /v1/zones/{id}/mood` | **MISMATCH** | Zone id. Also `rejected` responses have no UI (§5.5). |
| 8 | `pause` | `hero_card` | `POST /v1/zones/{id}/pause` | **MISMATCH** | Zone id. Body `{by: "Priya"}` — client sends a display name the server should arguably derive from the token instead (§5.6). |
| 9 | `resume` | `hero_card` | `POST /v1/zones/{id}/resume` | **MISMATCH** | Zone id only. |
| 10 | `watchTakeover` | `takeover_screen`, `active_takeover_screen` | `GET /v1/zones/{id}/takeover` | **MISMATCH** | Shapes MATCH. Client must tick the countdown locally between events — the repo owns that clock. |
| 11 | `startTakeover` | `takeover_screen` | `POST /v1/zones/{id}/takeover` | **MISMATCH** | `Duration` → `hand_back_after_minutes`: all four UI options (15/30/60/120 min) are whole minutes, so this is lossless. 409/403 have no UI (§5.5). |
| 12 | `extendTakeover` | `extend_sheet` | `POST /v1/zones/{id}/takeover/extend` | **MISMATCH** | Zone id. "Adds, not replaces" semantics MATCH the UI's expectation. |
| 13 | `endTakeover` | `confirm_return_dialog`, auto-return | `POST /v1/zones/{id}/takeover/end` | **MISMATCH** | Zone id. Idempotency required — the local countdown hitting zero calls this, and so can the user. |

### ScheduleRepo — zone-scoped

| # | Repo method | Screen | Endpoint | Flag | Note |
|---|---|---|---|---|---|
| 14 | `watchToday` | `floor_screen` rail | `GET /v1/zones/{id}/today` | **MISMATCH** | Shapes MATCH. Zone id. `now_index` server-computed — but see §5.2, the server can't actually compute it. |
| 15 | `watchMode` | `schedule_screen` | `GET /v1/zones/{id}/mode` | **MISMATCH** | `self_drive\|custom` ↔ `ScheduleMode.selfDrive\|custom`, clean. Zone id. |
| 16 | `setMode` | `schedule_screen` | `POST /v1/zones/{id}/mode` | **MISMATCH** | Zone id. |
| 17 | `watchWeekPlan` | `schedule_screen`, `week_picker` | `GET /v1/zones/{id}/dayparts` | **MISMATCH** | Shapes MATCH (`id`, `day_index`, `range_label`, `mood_id`). Zone id. |
| 18 | `addDaypart` | `daypart_sheet` | `POST /v1/zones/{id}/dayparts` | **MISMATCH** | Client sends `id: ''` for new rows; server assigns. Zone id. |
| 19 | `updateDaypart` | `daypart_sheet` edit | `PATCH /v1/dayparts/{id}` | MATCH | Client sends the whole object; contract expects that. |
| 20 | `deleteDaypart` | `daypart_sheet` delete | `DELETE /v1/dayparts/{id}` | MATCH | |

### VenueRepo

| # | Repo method | Screen | Endpoint | Flag | Note |
|---|---|---|---|---|---|
| 21 | `watchVenues` | `portfolio_screen` | `GET /v1/venues` | MATCH | Mock sorts "needs attention first" **inside the repo**; I'll keep that in the API repo so behaviour is identical regardless of server order. |
| 22 | `watchVenue` | `venue_screen` | `GET /v1/venues/{id}` | MATCH | 404 → `null`, which the screen already handles. |
| 23 | `returnZoneToAuto` | `venue_screen`, `portfolio_screen` | `POST /v1/zones/{zone_id}/return-to-auto` | MATCH | Signature takes `venueId` too; endpoint doesn't need it. Harmless. |
| 24 | `addVenue` | `add_venue_screen` | `POST /v1/venues` | MATCH | `org_id` derived server-side from the caller. Owner-only. |
| 25 | `removeZone` | `zone_detail_screen` | `DELETE /v1/zones/{zone_id}` | MATCH | Acts immediately, no confirm — matches the contract's note. |

Two sub-gaps inside otherwise-matching endpoints:
- `Venue.hoursLabel` ("Every day · 7am–11pm") has **no column** in `schema.sql`. Server must compute it from `open_hours`. Undefined what it should say when exceptions exist.
- `Zone.statusDetail` ("Off schedule · auto in 42 min") has **no column and no derivable source** — nothing stores when a zone returns to auto. The contract's own examples all show `status_detail: null`. The amber countdown copy cannot be produced. **MISSING.**
- Zone `status` wire values: examples show `"auto"` and `"offline"`; prose references `off_schedule`. Needs pinning to exactly `auto | off_schedule | offline`.

### SettingsRepo

| # | Repo method | Screen | Endpoint | Flag | Note |
|---|---|---|---|---|---|
| 26 | `watchGuardrails` | `settings_screen`, `volume_policy_screen`, `transitions_screen` | `GET /v1/zones/{id}/guardrails` | **MISMATCH ×3** | See §5.3 — alert indices, "At close", and two fields the model doesn't carry. |
| 27 | `updateGuardrails` | same three | `PUT /v1/zones/{id}/guardrails` | **MISMATCH ×3** | Whole-object PUT will silently null `quiet_hours_start_local` / `quiet_hours_cap_pct` unless the repo preserves them. |
| 28 | `watchOpenHours` | `open_hours_screen` | `GET /v1/venues/{id}/open-hours` | **MISMATCH** | Venue-scoped, no venue id in the signature. `exceptions[].id` and `.label` have no home in `HoursException`. |
| 29 | `setEverydayHours` | `everyday_hours_sheet` | `PUT /v1/venues/{id}/open-hours` | **MISMATCH** | Venue id only. |
| 30 | `addException` | `exception_sheet` | `POST /v1/venues/{id}/open-hours/exceptions` | **MISMATCH** | Client cannot send `label` (no field in the model or the sheet) and cannot send `on_date` when "Just this once" is picked. Server must default. |

### UI with no endpoint behind it

| Control | Where | Status |
|---|---|---|
| "Zone name" text field | `zone_detail_screen.dart:89` | **Dead.** No repo method, no endpoint, no save affordance. Typing in it does nothing — already flagged as `open_questions.md` #24. |
| Sign out | `account_menu` → `SessionNotifier.signOut()` | Local only. No `/auth/sign-out`. Acceptable (token just discarded) but worth a conscious decision on server-side revocation. |
| Exception edit/delete | `open_hours_screen` | Consistently absent on both sides — no UI, no endpoint. Not a gap. |

---

## 4. Structural decisions the integration forces

### 4.1 Zone scoping — the biggest one

`PlaybackRepo`, `ScheduleRepo` and `SettingsRepo` are written as if the app operates on **one implicit zone**. The API is explicitly per-zone. Marina Café has two zones (Main floor, Terrace) and the Floor screen shows **one** hero card with no way to switch.

`BACKEND_INTEGRATION.md` claims "nothing in the UI needs to change". That is true for the *widget tree*, but a zone identity has to come from somewhere. Three options:

- **(A) Server-resolved current zone.** Add `GET /v1/me/context` returning the caller's default venue + zone; API repos call zone-scoped endpoints using it. **No interface changes, no UI changes.** Cheapest path to working; a zone switcher can come later.
- **(B) Client-held current zone.** Add a `currentZoneProvider`, set after sign-in, read by the API repos. Same interface, but the app gains a real concept of "current zone" that a future picker plugs into.
- **(C) Change the interfaces** to take zone ids. Most correct long-term, but breaks the "no UI changes" promise, touches every screen, and rewrites the 32 tests.

**My recommendation: (B)**, with the server supplying the default via the sign-in response. It keeps every interface and test intact, but puts the zone concept in the app where the eventual picker needs it, rather than hiding it behind an endpoint you'd have to unwind later.

### 4.2 Realtime transport — 10 streams, no specified mechanism

The contract requires every `watch*()` to **emit immediately on subscribe, then on every change**, and to tolerate repeated subscription (providers are `autoDispose`). `everyday_hours_sheet.dart:31` calls `watchOpenHours().first` — if the stream doesn't emit immediately, that sheet hangs forever.

Options: Supabase Realtime direct from the client (bypasses FastAPI, needs client-side RLS), SSE from FastAPI, WebSocket, or polling.

**My recommendation:** a single SSE channel per zone (`GET /v1/zones/{id}/events` — a 31st endpoint, an addition to the contract) plus the plain GETs for initial value. Each `watch*()` = "GET now, then filter the SSE channel". Polling as a fallback behind a flag. This keeps one connection per zone rather than ten, and keeps all auth in one place (FastAPI) rather than splitting it with Supabase.

### 4.3 `moodById` crashes on unknown mood

`lib/theme/moods.dart:135` — `moods.firstWhere((m) => m.id == id)` with no `orElse`. An unrecognised `mood_id` from the server throws `StateError` **during widget build**, i.e. a red screen, not a fallback. The docs say "will not render"; it's worse than that. I'd harden this to fall back to a known mood while integrating.

---

## 5. Contradictions and ambiguities — explicit list

Numbered so you can answer by number. **B** = blocking (I need your call), **N** = non-blocking (I'll proceed as noted unless you object).

### 5.1 [B] Password reset has no proof-of-verification — security
`POST /auth/reset/save-password` takes `{email, password}` and nothing else. `verifyResetCode` returns `{}`. So **anyone who can reach the API can set any user's password** by calling save-password directly with their email — the verify step is unenforced. The Dart signature `saveNewPassword(String email, String password)` has no room for a token either, so this cannot be fixed on the server alone.

Also note `router.dart:50` treats any `/reset/*` path as public, so `/reset/new` is reachable directly without passing through verify.

**Fix requires a contract + interface change:** `verify` returns a short-lived single-use `reset_token`; `save-password` requires it. That means changing `AuthRepo.saveNewPassword`'s signature (or stashing the token in a provider). I will not guess here.

### 5.2 [B] The custom weekly plan cannot actually drive playback
`Daypart` carries only `rangeLabel` — free text, e.g. `"7 – 11 am"`, typed into a plain text field (`daypart_sheet.dart:99`). `schema.sql` keeps `start_local`/`end_local` nullable and explicitly says nothing populates them.

But `GET /zones/{id}/today` must return a **server-computed `now_index`**, and the whole point of a custom plan is deciding what plays when. With only a free-text label, the server cannot compute either. So: a user can build a weekly plan in the app that the backend fundamentally cannot execute.

Options: (a) parse `range_label` server-side (fragile — accepts "7 – 11 am", "7-11am", "seven to eleven"…); (b) ship a real time picker in `daypart_sheet` (the app already has `time_dial_sheet.dart` used by open hours — reusable); (c) accept that custom mode is display-only for now and `now_index` is computed from `self_drive` only. This is a product call, not a technical one.

### 5.3 [B] Guardrails: "At close" cannot be stored as minutes
`Guardrails.takeoverAlertOptions = ['1 hour', '2 hours', '4 hours', 'At close']`. The API and schema store `takeover_alert_minutes` as an integer (`smallint not null default 120`). **"At close" is not a duration** — it's a reference to the venue's closing time. Index 3 cannot round-trip.

Options: sentinel value (e.g. `-1` or `0` = at close), a separate `takeover_alert_at_close boolean`, or drop the option from the UI. Needs your call — a sentinel is cheap but it's exactly the kind of implicit encoding the schema author was trying to eliminate.

*(The sibling case is clean: `offlineAlertOptions = ['2 min','5 min','15 min','30 min']` → `[2,5,15,30]` maps losslessly both ways.)*

### 5.4 [B] Auth architecture: Supabase Auth or FastAPI-issued JWT?
`schema.sql` is built on Supabase: it references `auth.users`, `auth.uid()`, and RLS policies that only work if the request carries a Supabase user identity. But `api-contract.md` specifies a custom `POST /v1/auth/sign-in` returning an opaque `token`, with FastAPI in front.

These two only coexist if you pick one:
- **FastAPI proxies Supabase Auth** — sign-in forwards to Supabase, returns the Supabase JWT, and the API forwards it per-request so RLS applies. RLS does real work; FastAPI stays thin.
- **FastAPI issues its own JWT** and connects to Postgres as `prism_api`, enforcing tenancy in application code. Then `auth.uid()`-based RLS is dead weight and the cross-tenant guarantees move into code you have to test yourself.

The schema's column-level grants (`prism_api` / `prism_ingest`) suggest the second; the RLS policies suggest the first. **They pull in opposite directions and I won't pick silently.** My recommendation is the first — you get cross-tenant isolation from the database rather than from discipline, which matters more the first time a bug ships.

### 5.5 [B] No loading, empty, or error states exist anywhere
Every screen reads `provider.value ?? <fallback>`. On mocks (zero latency) this is invisible. Against a real network it means:
- During load, Settings shows **fabricated defaults** (26–70% band) that aren't the venue's real values — indistinguishable from real data.
- A **failed write is completely silent.** `updateGuardrails` throwing leaves the UI showing the old value with no indication anything went wrong.
- The contract's `rejected`, `409 takeover_already_active`, and `403` responses have **no UI at all** — the contract itself flags this.

Their own docs call this "the single biggest thing standing between this build and production". It needs design input. My proposal for the interim: a minimal non-designed error surface (a toast/snackbar using existing palette tokens) so failures are at least visible, clearly marked as a placeholder for the designer. Confirm you want that rather than silent failure.

### 5.6 [N] `pause({by})` trusts a client-supplied display name
`floor_screen.dart:66` sends `user.name.split(' ').first`. The server knows who the caller is from the token. **I'll send it as the contract specifies** (the pill needs a first name and the server has no `staff_profiles` lookup wired into that response shape yet), but the server should treat it as a display hint, never as identity.

### 5.7 [N] Whole-object PUT will drop fields the model doesn't carry
`Guardrails` has no `quietHoursStartLocal` / `quietHoursCapPct` — `volume_policy_screen.dart:90` hardcodes the string "After 10:00 pm · cap at 55%". But `PUT /guardrails` sends the whole object on **every toggle**. A naive implementation nulls both columns the first time anyone moves a slider.

**I'll handle it** by having `ApiSettingsRepo` retain the last server values for unmapped fields and re-send them unchanged. Flagging it because it's invisible and would corrupt data silently — and because the real fix is adding the two fields to the model once there's UI for them.

### 5.8 [N] One-off exceptions have no date
"Just this once" sets `everyWeek: false`, but the sheet collects no date and `HoursException` has no date field. `schema.sql` expects `on_date` when `every_week = false`. **I'll have the server default to the next occurrence** of the selected day(s) and flag it in the API docs.

### 5.9 [N] Assorted small pins
- Zone `status` wire strings → `auto | off_schedule | offline`.
- `Venue.hoursLabel` computed server-side from `open_hours`, ignoring exceptions (matches the current mock's format).
- `Idempotency-Key` — the app has no UUID dependency; I'll generate v4 from `Random.secure()` rather than add a package.
- Portfolio sort kept **client-side** in the API repo, matching mock behaviour, so the server can stay order-agnostic.

---

## 6. The scope decision

Given §0, "wire the frontend to the backend" resolves to one of:

- **Option 1 — Build the backend, then wire.** Implement `schema.sql` as Supabase migrations + a FastAPI service covering all 30 endpoints (+ SSE), then swap the repos one at a time. This is the only path that produces a genuinely working end-to-end system. Substantially more work than "integration", and it needs a real Supabase project with credentials you supply.
- **Option 2 — Build the frontend's API layer only.** Write the five `Api*Repo` implementations, models' JSON mapping, HTTP client, auth/token storage, `.env` config — verified against a local mock server that replays the contract. Real backend lands later against a client that's already proven. Nothing talks to a real database.
- **Option 3 — Thin vertical slice first.** Auth + Settings end-to-end (real Supabase, real FastAPI, real token, two screens), then decide whether to continue on the same pattern. Smallest thing that proves the whole stack, including the decisions in §5.

**My recommendation: Option 3**, then Option 1's remaining flows in the order `BACKEND_INTEGRATION.md` already suggests (Settings → Venues → Auth → Schedule → Playback). It surfaces the auth-architecture question (§5.4) against reality in the first increment rather than at the end, and it fits your "small, verifiable increments" instruction — you'd see something actually working before committing to the full build.

---

## 7. Proposed increments (once decisions are made)

Each increment ends with `flutter analyze && flutter test` green plus a manual check you can run yourself.

| # | Increment | Proves |
|---|---|---|
| 0 | Backend skeleton: Supabase project, migrations 001–004, FastAPI app, `/health`, `.env.example` | The stack boots; RLS test suite passes cross-tenant checks |
| 1 | HTTP client + config + token storage + `ApiAuthRepo` + session rehydration | Real sign-in, role-correct landing, survives restart |
| 2 | `ApiSettingsRepo` (guardrails + open hours) | Smallest surface; whole-object PUT; the §5.3/5.7 mappings |
| 3 | `ApiVenueRepo` | Streams on two screens; zone status derivation |
| 4 | `ApiScheduleRepo` | CRUD + whatever §5.2 resolves to |
| 5 | `ApiPlaybackRepo` + SSE | Realtime, the takeover clock, idempotent auto-return |
| 6 | Seed-data removal from the 10 screens + router | No mock strings left in production paths |

Mocks stay in the tree throughout — the test suite depends on them and they're the reference for expected shapes.

---

## 8. Secrets and configuration

Nothing hardcoded. Nothing committed. You'd supply real values for:

| Variable | Where | What it is |
|---|---|---|
| `SUPABASE_URL` | backend | Project URL |
| `SUPABASE_SERVICE_ROLE_KEY` | **backend only, never the app** | Server-side admin key |
| `SUPABASE_ANON_KEY` | backend (and app, only if §4.2 picks direct Realtime) | Public key, RLS-gated |
| `SUPABASE_JWT_SECRET` | backend | To verify incoming tokens |
| `DATABASE_URL` | backend | Postgres connection as `prism_api` |
| `PRISM_API_BASE_URL` | app | e.g. `http://localhost:8000/v1` — via `--dart-define`, not a committed file |

I'll write `.env.example` with every key and empty values, add `.env` to `.gitignore`, and tell you exactly which to fill. The Flutter side takes config through `--dart-define` so nothing sensitive lands in the bundle.

---

## 9. What I could not verify

- **Whether a backend exists somewhere I can't see** — another machine, a private repo, a Supabase project. I searched this filesystem only. If one exists, §0 changes and I should read it before anything else.
- **Whether `schema.sql` and `api-contract.md` are final** or still drafts. §5 assumes they're the intended target.
- **The design handoff frames.** `design_handoff/` holds two standalone HTML documents I haven't opened; `open_questions.md` lists 27 unresolved derivations, several of which (#18 daypart times, #24 zone-detail persistence) directly affect §5.2 and the dead rename field.
- **Anything requiring real credentials.** No Supabase project, no API keys, so nothing has been run against a live service.
