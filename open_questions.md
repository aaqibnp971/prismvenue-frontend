# Open questions — Prism Venues build

Running log of anything the README's §6-B doesn't cover that came up during
implementation. Per the handoff rules: nothing here was invented in code —
each item either follows a §6-A assumption (flagged) or is left unresolved.

The README's own §6-B list (1–12) is not repeated here; this file only adds
NEW items encountered during the build. Finalized in Phase 5.

## Phase 5 — Drag-to-reschedule (S03-2)

32. **The weekly grid was transposed, resolving item 17.** It had no time axis
    at all: a block's y-position was its index in the repo list, so "drag it an
    hour later" had nowhere to land. Building the axis was unavoidable. It runs
    horizontally — seven day ROWS, hours left to right — because vertically,
    sixteen open hours give ~32 pt/hour at 1024×768 and ~22 pt at the designed
    860×602 frame, so a one-hour daypart (which the sheet happily creates)
    would render at half the 44 pt minimum target. Horizontal gives ~59 pt/hour
    and ~74 pt rows. This is a visible change to a specified frame, taken under
    item 17's existing "S03 geometry is derived, not pinned".

33. **Overlapping dayparts are drawn, not refused — and nobody has decided what
    they mean.** A weekly plan is normally contiguous; the seeded one tiles
    7–23 with no gaps. So a block can rarely move without touching a neighbour,
    and a UI that refused overlap would be inert on exactly the shape real
    schedules take. Neither the model, the repositories nor the backend
    validates overlap, so refusing would also invent a constraint the system
    does not have. The drag therefore commits and the conflict is shown. But
    what actually plays when two dayparts both claim 3pm is undefined
    everywhere — it needs a product answer, and possibly a boundary-drag
    (resize) interaction rather than a move, which is the operation a
    contiguous plan really wants.

34. **Drag snaps to the hour; the sheet reaches five minutes.** ~~because that
    is all the model can say~~ — resolved on the model side: `Daypart` carries
    `startMinute`/`endMinute`, the wire sends them, and the dial's minute wheel
    picks them. The *drag* still steps in whole hours and carries the minutes
    along untouched (7:30–11:30 dragged one column right is 8:30–11:30), because
    a finger crossing a week-wide grid cannot express five minutes — a step
    would be a few pixels. The sheet is the precise path, and it can edit
    anything a drag produces. Whether the grid should also offer a fine-snap
    modifier is still open.

35. **First use of Semantics and haptics in the codebase.** Neither appeared
    anywhere in `lib/` before this. Drag-and-drop is invisible to VoiceOver by
    construction, so each block carries a label plus custom actions (move an
    hour earlier/later, previous/next day) and the sheet remains the
    full-capability path. Haptics mark arming, each hour crossing, and landing
    on a conflict — on a block your finger is covering, it is the only channel
    that is not occluded. Both are new API surface and should be reviewed
    rather than assumed.

## Phase 5 — Back to Auto (Floor)

28. **Floor now carries a return-to-auto, and Venues does the same thing
    without a confirm.** S01-3 exists because switching the vibe changes what
    the room audibly plays and must not happen by mis-tap. Handing the room
    back changes it just as much, so the Floor control confirms
    ("Let Prism take it from here?"). But `venue_screen.dart` performs the
    identical action from a zone row with no confirmation at all. One of the
    two is wrong and the frames pin neither — flagging rather than silently
    aligning them, since removing a confirm and adding one are both design
    decisions.

29. **The control is reachable by floor staff, who cannot reach Venues.**
    Floor is all-roles (§2 S01) while `/venues` is manager+owner and the router
    redirects floor staff away from it. So floor staff can already take the room
    off schedule from the mood grid, but until now had no way to put it back —
    only a manager could. Giving them the hand-back seems clearly right (an app
    that lets someone break the schedule but not repair it is worse), but it is
    a role-surface change and belongs beside item 16, not slipped in.

30. **"Off schedule" needs a server field on `/zones/{id}/now`.** The flag is
    parsed as `off_schedule`, defaulting to false when absent, so the control
    simply never appears against a backend that does not send it. The data
    exists: `zone_state.desired_mode` is `auto | manual | takeover | paused`,
    and `desired_mode_before_pause` preserves `auto | manual` across a pause —
    so the derivation is `desired_mode == 'manual'`, or, while paused,
    `desired_mode_before_pause == 'manual'`. Needs adding to the endpoint.

31. **No countdown is promised, deliberately.** The zone rows say "auto in
    42 min", but that string is a hardcoded mock seed with no server source
    (INTEGRATION_PLAN.md records `status_detail` as MISSING). The Floor pill
    therefore states the fact only. If a real return-to-auto deadline is
    intended, it needs a column before any UI can show one.

## Phase 4 — Polish

27. **§6-A1/A2/A3 derivations** — portrait breakpoint chosen at 900px body
    width, between iPad portrait (744–834) and landscape (≥1024) (§6-B2
    leaves real breakpoints open); the portrait rail strip's
    chip design (time + dot + name + NOW in tile/accentSoft chips inside a
    r14 card) is invented from the rail's row anatomy; pressed states use
    the 92%-scale option (not +6% darken) with a 90ms ease and the row
    flash renders `tile2` at 45% over the row; disabled 40% currently
    surfaces only on Primary/Secondary buttons (the only controls that can
    be disabled today). Screen transitions are instant per §4; sheets keep
    the 200ms slide.

## Phase 3 — Section 05 (Settings)

23. **Derived copy/geometry** — group icons (volume-2 / lock / map-pin /
    bell / sun-moon) are Lucide picks; sub-screen top-bar context lines
    follow the §2.0 pinned pattern (venue name stays in the title slot) but
    the exact context copy beyond the pinned examples ("Settings · Sound",
    "Open hours") is derived — transitions reuses "Settings · Sound", zone
    detail uses the zone name; the owner sub variant ("you're the owner"); elided
    helper copy ("Auto and staff stay inside this band.", "Open 16 hours.");
    the S05-3 footer note; sheet titles "Everyday hours"/"Add an exception";
    dropdown popover anchoring; alert dropdown defaults (5 min / 2 hours).
    All flagged as derived — confirm against frames.
24. **S05-5 zone detail** — the README gives one line ("zone form + Remove
    zone red"), so the form is derived: name field (edits don't persist —
    no save affordance is designed), display-only rows for hours / player
    ("Prism Player 01" invented) / vibe / volume, and Remove zone acts
    immediately without a confirm dialog (none designed). Routed as
    /venues/zones/:id from S04-1 rows; the §4 "settings home → zone-detail"
    edge has no obvious S05-1 row (the Place row opens Open hours), so it's
    reachable via Venues only.
25. **Blocked floor takeover UX** — when "Who can take over" is
    Manager-only, the floor role's Takeover tab renders locked (reusing the
    §2.0 locked-tab pattern) and /takeover redirects to /floor; the hero
    "Take over" button then bounces. No dedicated blocked state is designed.
26. **Open-hours exceptions** — rows are display-only (no edit/delete flow
    is designed, only "Add an exception"); S05-6's seg has its single
    "Everyday timings" option per the frame.

## Phase 3 — Section 04 (Venues)

20. **Portfolio seed & chrome** — the README names no venues beyond Marina
    Café, so Dockside (offline zone) and Harbor House ("1 zone · Peak", from
    the S04-2 example sub) are invented to exercise the triage range; the
    portfolio top bar ("Your venues · n venues") and the S04-1 venue header
    (name 17/700 + address 11) are derived since §2.0 assumes a single
    venue. Marina Café's 2 zones are named Main floor + Terrace (count from
    S05-1; the Terrace name is invented). The drill-in top bar binds to the
    routed venue with a derived status line — "{first zone} · online" with
    the green dot, or "{zone} · offline" without it when any zone is
    offline — since §2.0 only shows the healthy Marina Café case.
21. **Row derivations** — quiet zone-row sub ("Auto · {mood}"), portfolio
    problem-row sub ("{zone} · {status}"), off-schedule countdown copy
    ("Off schedule · auto in 42 min"), and offline rows getting a chevron
    instead of "Return to Auto" (nothing to fix remotely) are all derived
    readings of the one-line S04 specs.
22. **S04-3 details** — "Home address (two-col)" implemented as Street/City
    fields under one label; the Open-hours row is display-only until S05-6
    lands; zone chips styling and the "Add a venue / New location" top-bar
    copy are derived. Zone-row chevrons (→ S05-5 zone detail) wire up in
    Section 05.

## Phase 3 — Section 03 (Schedule)

17. **S03 sparse geometry** — §2 gives S03 one line per frame, so several
    values are derived from the app's own patterns rather than pinned:
    self-drive card sub copy + card width; mode switch rendered as the §3
    boxed SegToggle ("Self-drive · Custom plan"); week-grid day-column
    headers ("Mon 21" labelCaps), daypart-row styling (surface r10 padding
    8×9, range 11/700, dot 8 + name 12), "+ Add" button geometry; calendar
    popover anchor, size, shadow and its month chevrons. Check all against
    the frames.
18. **Daypart time editing** — S03-4 shows "time fields" but the §4 edge
    list has no set-time modal for schedule (unlike open-hours). The sheet's
    Time field is free-text for now; frames may intend the S05-11 dial.
19. **Weekly plan seed** — dayparts seeded from the rail's 5 rows on every
    day within the S05-6 default hours (7am–11pm); range label format
    ("7 – 11 am") is invented. The mock plan recurs weekly, so jumping weeks
    shows the same plan; sheet titles "Add a daypart"/"Edit daypart"/"Save"
    and sub "Pick day, time & mood." derive from the frame captions.

## Phase 3 — Section 02 (Takeover)

12. **S02-1 CTA label** — the README only says "Primary CTA starts takeover";
    implemented as "Start takeover". Confirm against the frame.
13. **"Just change the vibe" card** — flow already open (§6-B4); additionally
    its sub copy isn't in the README, so the card renders title-only and
    inert. Card icons (headphones / music) are Lucide picks, unverified.
14. **S02-2 banner text style** — the README pins the banner box (amber@12%
    bg, amber@34% border, r13, h56) and copy but not the text size/weight;
    implemented 13.5/600 amber. Bottom-row button sizing (equal flex, gap 10)
    is also derived, not pinned.
15. **S02-4 sheet sub** — "Your audio keeps playing, Prism just waits
    longer." is taken from the frame caption; confirm it appears inside the
    sheet.
16. **Floor-staff takeover guardrail** — §2 gates floor staff behind S05-4
    ("Who can take over"); until Section 05 lands SettingsRepo, the default
    "Managers + floor" applies, so takeover is open to all roles.

## Phase 3 — Section 00 (Auth)

8. **S00-3 helper copy** — the spec only says "helper shows the email in 700
   `textPrimary`", not the sentence around it. Implemented as "Enter the
   6-digit code we sent to **priya@marinacafe.com**." — confirm the real copy
   from the frame.
9. **Password reveal (eye icon)** — no behavior specified; implemented as a
   standard obscure/reveal toggle (eye ↔ eye-off). Flag if the frames intend
   it as decorative.
10. **S00-4 match-hint row** — rendered statically green as in the frame
    (validation itself is undesigned, §6-B9).
11. **Mock role mapping** — the backend "lands the user in their role"
    (S00-1); the mock maps email → role: contains "floor" → floor staff,
    "owner"/"arjun" → owner, anything else → manager. Purely mock-seed
    behavior, replace with the real backend contract later.

## Phase 1 (shared widgets)

1. **Nav / misc icon glyphs** — §1.8 sanctions Lucide but the README never
   names which glyph each nav tab (or field/dialog) uses. Current picks:
   Floor=music, Takeover=headphones, Schedule=calendar, Venues=map-pin,
   Settings=settings; email=mail, password=lock, reveal=eye, sign-out=log-out,
   return=rotate-ccw, time=clock. Please eyeball the `/_gallery` icon strip
   against the frames and correct any wrong picks.
2. **Chevron stroke** — spec wants 2.2 (chevrons/back) and 2.6 (checks);
   Lucide fonts bake 2.0, so chevrons and checks are hand-ported painters at
   the exact strokes. Other glyphs are Lucide at 2.0 per the base spec.
3. **MoodTile paused chip** — S01-2 only says "no eq animation" for the
   paused tile. Implemented as playing visuals with frozen bars and the chip
   still reading "Playing". If the frames show different chip copy (e.g.
   "Paused"), say so.
4. **MoodTile meta line content** — §3 gives "meta 11.5" but not its copy.
   `meta` is a prop; the gallery shows "{bpm} BPM" as sample content.
5. **Micro-layout inside MoodTile** — dot/energy-bars top row arrangement and
   name/meta bottom anchoring are derived, not numerically specified —
   eyeball in gallery.
6. **ConfirmDialog / sheet-handle / dropdown minutiae** — dialog text
   alignment (left assumed), handle color (borderStrong assumed), dropdown
   option text size (13 assumed), account-menu avatar font scale (11×38/32)
   — all unspecified micro-values, flagged for gallery eyeballing.
7. **ScheduleRail row times** — the 5 rows' time labels/format aren't in the
   README; gallery uses 7:00/11:00/2:00/6:00/9:00 with the mood order from
   §1.3. Confirm against frames before Phase 3 seeds the mock repo.

## Phase 0 (scaffold)

- None so far. Notes on interpretation (not questions):
  - §1.4 gives ranges for body/bodySm/meta/label/labelCaps/micro; theme layer
    exposes the range base plus the per-use values the spec pins explicitly
    (button 14/700, dialog body 13.5/400 lh 1.5, NOW badge 10/800, helper
    10.5/600). Per-widget values within the stated ranges are applied at the
    component level in Phase 1 from §2/§3's exact numbers.
  - Two-value paddings ("24×22", "13×15", "12,16") are read as CSS shorthand:
    vertical × horizontal.
