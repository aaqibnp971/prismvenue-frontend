# Test plan — QA audit blockers B-01 … B-05

Five shipping blockers from the QA audit (commit `82c7cff`), and the two
adjacent defects that were fixed alongside them. This document is written for
whoever has to **verify the fixes**, so each entry has the same three parts:

1. **The bug** — what was actually wrong, in one paragraph.
2. **Reproduce it** — the exact steps. Every one of these reproduced on the
   *old* build; if a step no longer behaves as described, that is the fix
   working.
3. **Expected now** — the pass condition. Anything else is a regression.

None of these were caught by `flutter analyze` or the test suite before the fix.
That is worth knowing while testing: **the automated suite is not a safety net
for this class of defect**, so these have to be walked by hand at least once.

---

## Before you start

| | |
|---|---|
| Branch | `fix/qa-audit-blockers` (frontend and backend) |
| Backend | The deployed Deno/Edge build. `dart_config.json` already points at it |
| Run | `flutter run -d <device> --dart-define-from-file=dart_config.json` |
| Sign in | Manager account — credentials from the team, not recorded here |

**B-03 is the exception**: it can only be reproduced against the **Python**
backend on `:8000`, because that is the backend that was missing the endpoints.
Its own section says how.

A note on the mock build. `--dart-define=PRISM_USE_MOCKS=true` will not exercise
B-03 or B-05 at all — both are real-network defects. Test those against a
server.

---

## B-01 · The password-reset confirm field was never read

**Severity:** Blocker — data loss (account lockout)

### The bug

`_confirm` was declared, wired to a text field, and disposed — and never
compared to anything. `_save()` sent `_password.text` straight to the server.
There was no length check either, and above the button sat a green tick reading
*"At least 8 characters · both match"* as **static copy, shown unconditionally**,
even when neither was true.

So the one control on the screen whose entire job is catching a typo did
nothing, while a green tick actively asserted that it had.

### Reproduce it

1. Sign-in screen → **Forgot Password**.
2. Enter a real address for an account you control → **Send verification code**.
3. Enter the emailed code → **Verify**.
4. In **New password** type `correct-horse`.
5. In **Confirm password** type `correct-hoarse` — deliberately different.
6. Note the green tick still says "both match".
7. Tap **Save new password**.

**Old behaviour:** saved successfully, returned to sign-in, and the account's
password was now `correct-horse` while the user believed it was whatever they
thought they had typed twice. Locked out.

### Expected now

- Step 6: the tick and its label are **grey**, not green, until both conditions
  actually hold.
- Step 7: the save is refused with **"Those two passwords do not match."**
- Make the two fields match but shorter than 8 characters → **"Use at least 8
  characters."**
- Make them match and ≥ 8 characters → tick turns **green**, save succeeds,
  returns to sign-in, and the new password works.

`lib/features/auth/reset_password_screen.dart`

---

## B-02 · The reset screen shipped with a real person's email pre-filled

**Severity:** Blocker — security

### The bug

`ResetEmailNotifier.build()` returned `'priya@marinacafe.com'`. The frame draws
that field *filled* to illustrate a filled state; it was shipped as the
production default. The field arrived pre-populated, with the accent "focused"
border that makes it look deliberate.

Anyone opening "Forgot Password" and tapping the button without clearing the
field mailed a password-reset code to that person's inbox — and the next screen
then told them, in bold, that the code had gone there.

### Reproduce it

1. Sign-in screen → **Forgot Password**.
2. **Do not type anything.**
3. Tap **Send verification code**.

**Old behaviour:** advanced to the code screen, which read *"We sent a code to
**priya@marinacafe.com**"*. A real reset code had been sent to a real inbox.

### Expected now

- Step 1: the field is **empty**, showing the placeholder `you@venue.com`.
- Step 3: nothing is sent. The screen shows **"Enter your email address."** and
  stays put.
- Type a valid address → sending works, and the code screen names **that**
  address.

> Also check: no screen anywhere in the reset flow displays
> `priya@marinacafe.com` unless you typed it.

`lib/features/auth/reset_email_screen.dart`

---

## B-03 · Three buttons called endpoints the Python backend did not have

**Severity:** Blocker — HTTP 404 in the documented local setup

### The bug

The app calls `PATCH /open-hours/exceptions/{id}`,
`DELETE /open-hours/exceptions/{id}` and
`POST /zones/{id}/takeover/remove-auto-return`. The Deno backend implemented all
three. **The FastAPI backend implemented none of them** — and FastAPI on `:8000`
is both the app's hardcoded default `PRISM_API_BASE_URL` and the target
`RUNNING.md` walks you through. The repo README claims both backends "serve the
same wire contract"; they had drifted.

Because of B-04 these also failed *silently*, so the buttons simply did nothing.

### Reproduce it

This one needs the **Python** backend:

```bash
cd prismvenue-backend && .venv/Scripts/python -m uvicorn app.main:app --reload --port 8000
```

```bash
cd prismvenue-frontend && flutter run -d chrome --web-port=8080 --dart-define-from-file=dart_config.local.json
```

Then, as a manager:

1. **Settings → Open hours →** tap an existing exception → change a day → **Save**.
2. Same sheet → **Delete**.
3. **Takeover →** start one → **Extend →** *"Remove auto-return instead"*.

**Old behaviour:** all three returned 404 and, thanks to B-04, nothing appeared
on screen. The exception stayed exactly as it was; the countdown kept running.

### Expected now

- (1) the exception updates and the list reflects it.
- (2) the exception disappears from the list.
- (3) the countdown stops and **Extend** disappears; the takeover stays active
  and **Return to Prism** still ends it.

Repeat all three against the deployed Deno backend (`dart_config.json`) — they
should behave identically. That parity is the actual fix.

`prismvenue-backend/app/routers/settings.py` · `prismvenue-backend/app/routers/playback.py`

---

## B-04 · Nine mutations had no error handling

**Severity:** Blocker — silent failure

### The bug

Four call sites wrapped failures in `showPrismError`. Nine did not: the future
was fired and dropped, so a rejection surfaced as an unhandled async exception
in a console nobody reads, and **nothing at all on screen**. The failure mode
was identical every time — the user taps, nothing happens, no reason given, so
they tap again.

Two of the nine were fixed before this branch (daypart edits, schedule mode).
The five remaining were:

| Control | Screen |
|---|---|
| **Start takeover** — S02's primary CTA | Takeover |
| **Return to Auto** | Venue detail |
| **Return to Auto** | Owner portfolio |
| **Remove zone** | Zone detail |
| **Add venue** | Add venue |

### Reproduce it

The cleanest trigger is to make the request fail. Either **turn off Wi-Fi /
enable airplane mode** just before tapping, or point the app at a dead port
(`PRISM_API_BASE_URL=http://localhost:9/v1`).

1. Airplane mode on.
2. **Takeover → Start takeover.**
3. **Venues →** a venue with an off-schedule zone → **Return to Auto**.
4. **Venues → +Venue →** name it → **Add venue**.
5. **Venues →** a zone → **Remove zone**.

**Old behaviour:** every one of these did nothing visible. No spinner, no error,
no state change.

### Expected now

Every one shows a **red error message** naming the failure.

**Also check the takeover conflict path**, which is the case that mattered most
and was the most invisible — it needs no network trickery:

1. Device A (or a second browser tab, signed in as another user): start a
   takeover on a zone.
2. Device B: same zone → **Start takeover**.

Expected: B shows **"Someone is already using the speakers here."** Previously B
showed nothing at all and the user had no way to know why the speakers had not
changed hands.

`takeover_screen.dart` · `venue_screen.dart` · `portfolio_screen.dart` ·
`zone_detail_screen.dart` · `add_venue_screen.dart`

---

## B-05 · Simultaneous token refreshes could sign staff out mid-shift

**Severity:** Blocker — race

### The bug

`ApiClient._refresh()` had no single-flight guard. The Floor screen mounts three
watchers plus a 5-second poller, so when the hour-long access token expires
several requests 401 in the same instant and **each posted the same refresh
token**. Supabase rotates refresh tokens on use, so the first call won and the
rest got a 401 back — which drove `tokens.clear()` and `onSessionLost()`.

The iPad dropped to the sign-in screen in the middle of service: the exact
failure the refresh endpoint was added to prevent. Supabase's reuse-grace window
hid it much of the time, which made it **intermittent rather than rare** — the
worst shape for a bug like this.

### Reproduce it

The honest version takes an hour: sign in, sit on the **Floor** screen, and wait
for the access token to expire (default 1h) without touching the device. The
Floor screen is the one that matters because it is the only screen with four
concurrent readers.

Faster, if you can: shorten the Supabase project's JWT expiry to ~60 seconds
(Authentication → Settings), sign in, and sit on Floor for two minutes.

**Old behaviour:** at the expiry boundary the app dropped to the sign-in screen,
sometimes. Repeat several times — it did not happen every time.

### Expected now

- The app stays signed in across the expiry boundary, every time.
- The Floor screen keeps updating — mood, noise meter and takeover state all
  keep flowing without interruption.
- Run it through **five** consecutive expiries before calling this passed. One
  clean pass proves nothing; the bug was intermittent by nature.

`lib/data/api/api_client.dart`

---

## Fixed alongside

### H-04 · "Remove zone" deleted immediately, with no confirmation

**The bug.** One tap, no dialog, no undo. The app puts a modal in front of
*changing the music* on the grounds that a mis-tap in a busy venue is expensive
— and then deleted a room's entire speaker configuration on a single tap.

**Reproduce.** Venues → a zone → **Remove zone**.

**Expected now.** A confirm dialog appears, **naming the zone** ("Removing
**Main floor** takes its schedule, guardrails and playback settings with it").
**Cancel** leaves everything untouched. **Remove zone** in the dialog deletes it
and returns you to the venue.

> Known, unfixed, and worth watching for while testing: if you remove the zone
> you are *currently operating*, the session still points at the dead id and the
> Floor tab breaks until sign-out. That is the second half of H-04 and is **not**
> fixed on this branch.

### M-06 · Empty venue name silently did nothing

**The bug.** `if (name.isEmpty) return;` — the CTA read as broken rather than as
a validation message. There was also no busy guard, so a slow network invited a
double-submit, and each tap mints a fresh idempotency key: **a recovered
connection created the venue twice.**

**Reproduce.**
1. Venues → **+Venue** → leave the name blank → **Add venue**.
2. Then: fill in a name, throttle the network hard, and tap **Add venue**
   repeatedly.

**Expected now.**
1. **"Give the venue a name."**
2. The button reads **"Adding…"** and is inert until the request settles.
   Exactly **one** venue is created. Check the portfolio for duplicates.

---

## Regression sweep

These paths were touched and should be walked once even though nothing about
them was reported broken:

- Sign in → Floor → change a mood → pause → resume.
- Start a takeover → extend it → end it.
- Add an open-hours exception (the create path shares helpers with the new
  edit/delete).
- Sign out → sign back in.

## What this branch does **not** fix

The audit lists 38 defects. This branch closes 5 blockers plus H-04 and M-06.
**31 remain** — 9 High, 9 Medium, 13 frame gaps. The ones most likely to be
mistaken for new bugs while testing:

- **H-02** — the portfolio's "Needs attention" chip is decorative; the list is
  in `created_at` order, so an offline venue can sit below healthy ones.
- **H-05** — the Floor noise meter shows `62%` when nothing has reported.
- **H-06** — an API error on Floor, Venue or Zone-detail paints a **blank
  screen** rather than an error state.
- **H-09** — the schedule's week arrows move the label only; every week shows
  the same plan.
- **H-01** — every new zone is pre-named "Back patio".

Please do not re-file those; they are known and triaged.
