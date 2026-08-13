# Test plan — QA audit fixes

The QA audit found **38 defects**. This branch closes **16**: all 5 blockers,
all 11 High, plus two Medium that were adjacent enough to fix alongside.

Written for whoever has to **verify the fixes**, so every entry has the same
three parts:

1. **The bug** — what was actually wrong.
2. **Reproduce it** — exact steps. Every one reproduced on the *old* build; if
   a step no longer behaves as described, that is the fix working.
3. **Expected now** — the pass condition. Anything else is a regression.

None of these were caught by `flutter analyze` or the test suite before the
fix. Worth holding onto while testing: **the automated suite is not a safety
net for this class of defect.** The suite is now 111 tests (was 94) and the
backend 121 (was 116), but these still have to be walked by hand once.

---

## Before you start

| | |
|---|---|
| Branch | `fix/qa-audit-blockers`, both repos |
| Backend | The deployed Deno/Edge build. `dart_config.json` already points at it |
| Run | `flutter run -d <device> --dart-define-from-file=dart_config.json` |
| Sign in | Manager account — credentials from the team, not recorded here |

**Two exceptions.** B-03 can only be reproduced against the **Python** backend
on `:8000` — its own section says how. B-05 needs a token expiry, so budget
time or shorten the JWT lifetime.

`--dart-define=PRISM_USE_MOCKS=true` will not exercise B-03, B-05 or any of the
server-side halves. Test those against a server.

---

# Blockers

## B-01 · The password-reset confirm field was never read

**Blocker — data loss (account lockout)**

**The bug.** `_confirm` was declared, wired to a text field, and disposed —
never compared to anything. `_save()` sent `_password.text` straight to the
server, with no length check, under a green tick reading *"At least 8
characters · both match"* shown **unconditionally**. The one control whose
whole job is catching a typo did nothing, while a tick asserted it had.

**Reproduce.** Forgot Password → real address → code → Verify. New password
`correct-horse`, confirm `correct-hoarse`. Note the tick still says "both
match". Save.

*Old:* saved successfully. The account's password was now something the user
never intended. Locked out.

**Expected now.**
- The tick and label are **grey** until both conditions actually hold.
- Save is refused: **"Those two passwords do not match."**
- Matching but under 8 characters → **"Use at least 8 characters."**
- Matching and ≥ 8 → tick turns **green**, save succeeds.

`lib/features/auth/reset_password_screen.dart`

---

## B-02 · The reset screen shipped with a real person's email pre-filled

**Blocker — security**

**The bug.** `ResetEmailNotifier.build()` returned `'priya@marinacafe.com'`.
The frame draws that field *filled* to illustrate a filled state; it shipped as
the production default, with the accent "focused" border that makes it look
deliberate.

**Reproduce.** Forgot Password → type nothing → **Send verification code**.

*Old:* advanced to the code screen reading *"We sent a code to
**priya@marinacafe.com**"*. A real reset code, to a real inbox.

**Expected now.**
- The field is **empty**, placeholder `you@venue.com`.
- Nothing is sent: **"Enter your email address."**
- Type an address → the code screen names **that** address.

> Also check: `priya@marinacafe.com` appears nowhere in the reset flow unless
> you typed it.

`lib/features/auth/reset_email_screen.dart`

---

## B-03 · Three buttons called endpoints the Python backend did not have

**Blocker — HTTP 404 in the documented local setup**

**The bug.** The app calls `PATCH` and `DELETE /open-hours/exceptions/{id}` and
`POST /zones/{id}/takeover/remove-auto-return`. Deno implemented all three;
**FastAPI implemented none** — and `:8000` is the app's hardcoded default and
the target `RUNNING.md` walks you through. Because of B-04 they also failed
*silently*.

**Reproduce.** Needs the **Python** backend:

```bash
cd prismvenue-backend && .venv/Scripts/python -m uvicorn app.main:app --reload --port 8000
```

```bash
cd prismvenue-frontend && flutter run -d chrome --web-port=8080 --dart-define-from-file=dart_config.local.json
```

1. Settings → Open hours → tap an exception → change a day → Save.
2. Same sheet → Delete.
3. Takeover → start one → Extend → *"Remove auto-return instead"*.

*Old:* all three 404'd and nothing appeared on screen.

**Expected now.** (1) updates, (2) disappears, (3) countdown stops and Extend
disappears while the takeover stays active. **Repeat all three against the
deployed Deno backend** — identical behaviour is the actual fix.

`prismvenue-backend/app/routers/settings.py` · `.../playback.py`

---

## B-04 · Nine mutations had no error handling

**Blocker — silent failure**

**The bug.** The future was fired and dropped, so a rejection surfaced as an
unhandled async exception in a console nobody reads and **nothing on screen**.
Two were already fixed; these five were not: Start takeover, both Return to
Auto copies, Remove zone, Add venue.

**Reproduce.** Airplane mode on, then: Takeover → Start takeover · Venues →
Return to Auto · Venues → +Venue → Add venue · a zone → Remove zone.

*Old:* every one did nothing visible.

**Expected now.** Each shows a red error message.

**Also check the takeover conflict** — the case that mattered most and was the
most invisible, and it needs no network trickery:

1. Device A: start a takeover on a zone.
2. Device B: same zone → Start takeover.

Expected: B shows **"Someone is already using the speakers here."** Previously
B showed nothing and had no way to know why the speakers had not changed hands.

---

## B-05 · Simultaneous token refreshes could sign staff out mid-shift

**Blocker — race**

**The bug.** `ApiClient._refresh()` had no single-flight guard. Floor mounts
three watchers plus a 5-second poller, so on expiry several requests posted the
**same** refresh token. Supabase rotates them: the first won, the rest got 401s,
which drove `tokens.clear()`. The iPad dropped to sign-in mid-service — the
exact failure the refresh endpoint exists to prevent.

**Reproduce.** Sign in, sit on **Floor**, wait out the access token (default
1h) without touching the device. Floor is the screen that matters — it is the
only one with four concurrent readers. Faster: drop the Supabase JWT expiry to
~60s and sit there two minutes.

*Old:* dropped to sign-in at the expiry boundary, **sometimes**.

**Expected now.** Stays signed in, every time; Floor keeps updating. **Run five
consecutive expiries before calling this passed** — the bug was intermittent by
nature and one clean pass proves nothing.

`lib/data/api/api_client.dart`

---

# High

## H-01 · Every new zone was called "Back patio"

**The bug.** The add-zone sheet seeded its controller with the frame's
illustrative value.

**Reproduce.** Venues → +Venue → **+ Add zone** → **Add zone** without typing.

*Old:* created a zone named Back patio.

**Expected now.** The field is empty with "Back patio" as a **hint**. Adding
with an empty name adds nothing. Type a name → that zone appears.

---

## H-02 · The portfolio was not sorted by what needs attention

**The bug.** S04-2 exists so problems shout. The screen drew a "Needs
attention" chip over a list in whatever order the API returned — `created_at`.
Nothing sorted on either side.

**Reproduce.** As an owner, arrange an estate where a healthy venue was created
before a problem one. Open the portfolio.

*Old:* the offline venue sat below healthy ones, under a label claiming
otherwise.

**Expected now.** Order is **offline → off-schedule → healthy**. Offline
outranks off-schedule: a room nobody can reach needs someone to walk to it,
an overridden one is a tap away. Within a group the server's order is kept, so
**the list must not reshuffle on refresh** — pull to refresh a few times and
watch for jumping rows.

---

## H-03 · The zone name field discarded every edit

**The bug.** A fully interactive field with no save affordance and no write
path behind it.

**Reproduce.** Venues → a zone → change **Zone name** → navigate back.

*Old:* the edit was gone.

**Expected now.**
- Saves **on blur** (tap elsewhere, or navigate away). The new name shows in
  the venue's zone list.
- Renaming to a **sibling zone's name** is refused: *"Another zone in this
  venue already uses that name."* and the field returns to the server's value.
- Re-saving an **unchanged** name is a silent no-op, not an error.
- As a **floor** user the rename is refused with a 403 message, not a silent
  revert.

New endpoint `PATCH /v1/zones/{id}` on both backends.

---

## H-05 · Invented values were shown as live data

**The bug.** The hero rendered `noise.value ?? 62`, so a zone whose sensor had
never reported showed a confident **62%**. Settings showed `?? 2` zones and
`?? '7am–11pm'`.

**Reproduce.** Open Floor on a zone with no telemetry (all of them today —
there is no ingest layer). Open Settings before the venue fetch lands.

*Old:* a plausible 62% and "2 · 7am–11pm", indistinguishable from real values.

**Expected now.**
- The noise meter shows an **empty track and a dash**, no thumb.
- Settings' "Zones & open hours" shows **—** until the real value arrives.
- Once a real value exists it renders normally.

---

## H-06 · Failures rendered as a blank screen

**The bug.** Floor, Venue detail and Zone detail mapped both `loading` and
`error` to `SizedBox.shrink()`. An API failure painted an empty screen with a
nav bar, no message and no retry — and it looked identical to a venue that
genuinely had no zones.

**Reproduce.** Airplane mode, then open Floor. Also: navigate to
`/venues/does-not-exist` and `/venues/zones/does-not-exist`.

*Old:* blank.

**Expected now.**
- Floor shows an error with a **Try again** that actually refetches.
- Venue detail: *"That venue could not be loaded."*
- Zone detail: *"That zone is no longer available."*
- While a fetch is genuinely in flight you get a **spinner**, not the error —
  loading and failure are now distinguishable.

---

## H-07 · Guardrail writes failed silently and snapped back

**The bug.** `_flushGuardrails` caught the failed PUT, swallowed it, and
refreshed — so the revert was the only signal. Defensible for a volume slider;
not for **"Who can take over"**, which decides whether floor staff can seize the
speakers.

**Reproduce.** Airplane mode → Settings → **Who can take over** → change it.

*Old:* the value flipped back and nothing said why.

**Expected now.** The value still reverts (the server is the authority) **and**
a red error appears. Check the same on Volume policy and Transition smoothness
— one listener covers all three screens.

---

## H-08 · Dayparts accepted end ≤ start

**The bug.** Each hour was validated only as 0–23, so "Starts 9pm / Ends 7am"
saved cleanly, as did a zero-length 6pm–6pm. Neither has a meaning the
scheduler can act on: it matches `start <= now < end`, so a zero-length block
never plays and a reversed one is read as a past-midnight range it was never
meant to be.

**Reproduce.** Schedule → Custom plan → **+ Add** → set Starts to 10pm against
a 9pm end.

*Old:* saved.

**Expected now.**
- Helper text turns red: **"End time must be after the start time."**
- Equal hours: **"Start and end cannot be the same hour."**
- **Add daypart is inert** while either holds — blocked rather than warned
  after the fact, because the sheet has already popped by the time the write
  runs and a server rejection would have no dialog to report into.
- Both backends reject it too, so a hand-rolled request gets a 422.

---

## H-09 · Week navigation was cosmetic — now it is real

**The largest change on this branch. Test it hardest.**

**The bug.** The chevrons and calendar popover moved a label and nothing else.
`weekPlanProvider` was not parameterised by week, so **every week rendered the
same dayparts** and "+ Add" added to the same recurring plan regardless.

**The model now.** The plan is **recurring** — one set every week shows. A week
can be **forked** into its own copy, and only when someone deliberately picks
**"Just this week"**. Nothing forks by accident. A fork is a complete copy, not
a diff.

**Reproduce / verify.**

1. Schedule → **Custom plan**. Note this week's dayparts.
2. Chevron to **next week**. It shows the same plan — correct, it is the
   recurring plan.
3. Tap a daypart. The sheet now has **"Applies to: Every week / Just this
   week"**, defaulting to Every week, with helper text explaining each.
4. Pick **Every week**, change the mood, Save. Go back and forward a week —
   **every** week reflects the change.
5. Chevron forward again, edit another daypart, pick **Just this week**, Save.
6. That week's header now carries an amber **"Just this week"** pill.
7. Go back to the recurring weeks — **they are unchanged**.
8. Now edit a daypart with **Every week** on an unforked week. Return to the
   forked week: **it does not receive that change.** This is intended and
   permanent, and is exactly what the sheet's helper text warned about.
9. On the forked week, the sheet **no longer offers the choice** — every edit
   stays in that week.

**Also verify the engine follows the fork.** This is the half that would be an
ugly bug: set a fork whose current-hour daypart differs from the recurring
plan, wait for the minute-boundary cron tick, and confirm the room plays the
**fork's** mood, not the recurring one. If the Floor hero and the Schedule
screen ever disagree, that is the failure to report.

**Edge cases worth a try:**
- Fork the same week twice (tap "Just this week" on two edits). The plan must
  **not** duplicate — forking is idempotent.
- Delete a daypart with "Just this week" on an unforked week: the week must
  fork *first*, so the deletion hits only that week.

---

## H-10 · The theme choice was not persisted

**The bug.** In-memory, so every relaunch reverted to dark. On a device that
lives on a bright bar counter, a daily annoyance.

**Reproduce.** Switch to **Light**, force-quit the app, reopen.

*Old:* dark again.

**Expected now.** Light survives the restart, **with no dark flash** during
launch — the choice is read before the first frame. Check on a cold start, not
just a resume.

> **Still unfixed (was in the audit, out of scope here):** picking "System
> device" in Settings leaves the top-bar toggle showing "Light" regardless of
> the actual OS theme.

---

# Also fixed

## H-04 · "Remove zone" deleted immediately, with no confirmation

**Reproduce.** Venues → a zone → **Remove zone**.

**Expected now.** A dialog appears **naming the zone**. Cancel leaves
everything untouched; confirming deletes and returns to the venue.

> **Known and unfixed:** removing the zone you are *currently operating* leaves
> the session pointing at a dead id and the Floor tab breaks until sign-out.
> That is the second half of H-04 and is **not** fixed on this branch.

## M-06 · Empty venue name silently did nothing

**Reproduce.** Venues → +Venue → blank name → Add venue. Then: fill a name,
throttle the network hard, tap Add venue repeatedly.

**Expected now.** (1) **"Give the venue a name."** (2) The button reads
**"Adding…"** and is inert until the request settles; exactly **one** venue is
created. Check the portfolio for duplicates.

---

# Regression sweep

Touched paths, worth walking once even though nothing about them was reported
broken:

- Sign in → Floor → change a mood → pause → resume.
- Start a takeover → extend → end.
- Add an open-hours exception (shares helpers with the new edit/delete).
- Self-drive ⇄ Custom plan, both directions.
- Sign out → sign back in.
- Rotate to portrait on a phone: the hero must not show a red error screen.

---

# What this branch does **not** fix

**22 findings remain** — 9 Medium, 13 frame gaps, and one High deferred by
decision. Please do not re-file these.

**H-11 (deferred)** — the session token travels in the SSE query string. Mostly
moot: the deployed backend answers `/zones/{id}/events` with 410 and the app is
on 5-second polling, so realtime is degraded-but-working by design.

**Medium, most likely to be mistaken for new bugs:**

- **M-01** — polling never upgrades back to SSE; one dropped frame degrades the
  screen for as long as you stay on it.
- **M-02** — a portfolio row can read "Terrace · Offline" beside a Return to
  Auto button that fixes **Main floor**.
- **M-03** — "Delete daypart" has no confirmation.
- **M-04** — off-schedule zones cannot be opened; the rows you most want to
  inspect are the ones you cannot tap.
- **M-05** — "Resend code" gives no feedback at all.
- **M-07** — dropdown popovers are not clamped to the screen.
- **M-09** — no accessibility layer; several tap targets under 44pt.

**Frame gaps** — 13 controls in the v3.1 frames that do not exist in the app
(time-of-day grid, bulk day selection, stat tiles, Troubleshoot, Floor PIN,
named/dated exceptions, and more). The app was built to
`design_handoff/README.md`, an older summary. That is a scoping decision, not a
bug list.
