import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app/roles.dart';
import '../data/models/schedule_entry.dart';
import '../data/models/user.dart';
import '../theme/theme.dart';
import '../shared/widgets/account_menu.dart';
import '../shared/widgets/confirm_dialog.dart';
import '../shared/widgets/day_chips.dart';
import '../shared/widgets/energy_bars.dart';
import '../shared/widgets/eq_bars.dart';
import '../shared/widgets/mood_tile.dart';
import '../shared/widgets/noise_meter.dart';
import '../shared/widgets/otp_boxes.dart';
import '../shared/widgets/primary_button.dart';
import '../shared/widgets/prism_bottom_nav.dart';
import '../shared/widgets/prism_bottom_sheet.dart';
import '../shared/widgets/prism_dropdown_menu.dart';
import '../shared/widgets/prism_field.dart';
import '../shared/widgets/prism_icons.dart';
import '../shared/widgets/prism_toggle.dart';
import '../shared/widgets/prism_top_bar.dart';
import '../shared/widgets/schedule_rail.dart';
import '../shared/widgets/secondary_button.dart';
import '../shared/widgets/seg_toggle.dart';
import '../shared/widgets/settings_row.dart';
import '../shared/widgets/status_pill.dart';
import '../shared/widgets/auto_button.dart';
import '../shared/widgets/take_over_button.dart';
import '../shared/widgets/time_dial_sheet.dart';
import '../shared/widgets/venue_row.dart';
import '../shared/widgets/zone_row.dart';
import '../theme/moods.dart';
import '../theme/palette.dart';
import '../theme/typography.dart';

/// Hidden /_gallery debug route — every §3 component in its designed states,
/// rendered in BOTH themes side by side for fidelity eyeballing against the
/// frames. Not a designed screen; never linked from app navigation.
class WidgetGalleryScreen extends StatelessWidget {
  const WidgetGalleryScreen({super.key});

  // Marina Café sample data (README examples).
  static final _priya = User(
    id: 'u1',
    name: 'Priya Nair',
    role: Role.manager,
    initials: 'PN',
    avatarColor: const Color(0xFF84C44A),
  );

  static const _schedule = [
    ScheduleEntry(timeLabel: '7:00 am', moodId: 'morning-calm'),
    ScheduleEntry(timeLabel: '11:00 am', moodId: 'daytime-flow'),
    ScheduleEntry(timeLabel: '2:00 pm', moodId: 'afternoon-lift'),
    ScheduleEntry(timeLabel: '6:00 pm', moodId: 'evening-warmth'),
    ScheduleEntry(timeLabel: '9:00 pm', moodId: 'peak'),
  ];

  @override
  Widget build(BuildContext context) {
    final sections = <(String, WidgetBuilder)>[
      ('PrismTopBar — main / sub-screen', (context) {
        return Column(
          children: [
            PrismTopBar(
              title: 'Marina Café',
              subtitle: 'Main floor · online',
              statusDot: true,
              user: _priya,
            ),
            const SizedBox(height: 12),
            PrismTopBar(
              title: 'Marina Café',
              subtitle: 'Settings · Sound',
              showBack: true,
              user: _priya,
            ),
          ],
        );
      }),
      ('PrismBottomNav — floor role (locked) / manager', (context) {
        return Column(
          children: [
            const PrismBottomNav(
              active: NavTab.floor,
              lockedTabs: {NavTab.schedule, NavTab.venues, NavTab.settings},
            ),
            const SizedBox(height: 12),
            const PrismBottomNav(active: NavTab.settings),
          ],
        );
      }),
      ('SegToggle — pill (top bar / AM-PM) & boxed (durations)', (context) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                SegToggle(
                    options: const ['Dark', 'Light'], selected: 0, pill: true),
                const SizedBox(width: 12),
                SegToggle(
                  options: const ['AM', 'PM'],
                  selected: 1,
                  pill: true,
                  itemPadding:
                      const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const SegToggle(
              options: ['15 mins', '30 mins', '1 hour', '2 hours'],
              selected: 1,
            ),
          ],
        );
      }),
      ('MoodTile — idle / playing / paused', (context) {
        return Row(
          children: [
            Expanded(
                child: MoodTile(
                    mood: moodById('evening-warmth'), meta: '92 BPM')),
            const SizedBox(width: 12),
            Expanded(
                child: MoodTile(
                    mood: moodById('afternoon-lift'),
                    state: MoodTileState.playing,
                    meta: '110 BPM')),
            const SizedBox(width: 12),
            Expanded(
                child: MoodTile(
                    mood: moodById('afternoon-lift'),
                    state: MoodTileState.paused,
                    meta: '110 BPM')),
          ],
        );
      }),
      ('MoodTile — all six moods (idle)', (context) {
        return Column(
          children: [
            for (var row = 0; row < 2; row++) ...[
              if (row > 0) const SizedBox(height: 12),
              Row(
                children: [
                  for (var col = 0; col < 3; col++) ...[
                    if (col > 0) const SizedBox(width: 12),
                    Expanded(
                      child: MoodTile(
                        mood: moods[row * 3 + col],
                        meta: '${moods[row * 3 + col].bpm} BPM',
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        );
      }),
      ('EnergyBars 1–5 · EqBars animating / frozen', (context) {
        final palette = Theme.of(context).extension<PrismPalette>()!;
        return Row(
          children: [
            for (var e = 1; e <= 5; e++) ...[
              EnergyBars(energy: e, color: moods[e - 1].dot(palette.brightness)),
              const SizedBox(width: 14),
            ],
            const SizedBox(width: 16),
            EqBars(color: palette.accent),
            const SizedBox(width: 14),
            EqBars(color: palette.accent, animate: false),
          ],
        );
      }),
      ('NoiseMeter — 62% (read-only)', (context) {
        return const SizedBox(width: 360, child: NoiseMeter(value: 62));
      }),
      ('AutoButton — active / handing back', (context) {
        return Row(
          children: [
            const AutoButton(active: true),
            const SizedBox(width: 10),
            AutoButton(active: false, onTap: () {}),
          ],
        );
      }),
      ('TakeOverButton & StatusPill tones', (context) {
        return Row(
          children: [
            const TakeOverButton(),
            const SizedBox(width: 14),
            const StatusPill(text: 'Prism is driving', dot: true),
            const SizedBox(width: 10),
            const StatusPill(
                text: 'Paused by Priya · tap play to resume',
                tone: PillTone.amber),
            const SizedBox(width: 10),
            const StatusPill(text: 'Online', tone: PillTone.green),
          ],
        );
      }),
      ('ScheduleRail — past / NOW / up next', (context) {
        return Align(
          alignment: Alignment.centerLeft,
          child: ScheduleRail(entries: _schedule, nowIndex: 2),
        );
      }),
      ('Buttons — sheet (h46/r12) & auth (h54/r999)', (context) {
        return Column(
          children: [
            Row(
              children: [
                const Expanded(child: SecondaryButton(label: 'Cancel')),
                const SizedBox(width: 10),
                const Expanded(
                    flex: 2, child: PrimaryButton(label: 'Switch the vibe')),
              ],
            ),
            const SizedBox(height: 12),
            const PrimaryButton(label: 'Sign in', auth: true, expanded: true),
          ],
        );
      }),
      ('PrismField — auth idle / focused-filled / password · sheet', (context) {
        return Column(
          children: [
            const PrismField(
              auth: true,
              hint: 'Email',
              leading: Icon(LucideIcons.mail),
            ),
            const SizedBox(height: 14),
            PrismField(
              auth: true,
              controller: TextEditingController(text: 'priya@marinacafe.com'),
              focusedOverride: true,
              leading: const Icon(LucideIcons.mail),
            ),
            const SizedBox(height: 14),
            PrismField(
              auth: true,
              controller: TextEditingController(text: '••••••••'),
              obscure: true,
              leading: const Icon(LucideIcons.lock),
              trailing: const Icon(LucideIcons.eye),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: PrismField(
                    label: 'Opens',
                    controller: TextEditingController(text: '7:00 am'),
                    strongBorder: true,
                    leading: const Icon(LucideIcons.clock, size: 15),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: PrismField(
                    label: 'Zone name',
                    controller: TextEditingController(text: 'Back patio'),
                    focusedOverride: true,
                  ),
                ),
              ],
            ),
          ],
        );
      }),
      ('OtpBoxes — filled / next-empty / empty', (context) {
        return const SizedBox(width: 420, child: OtpBoxes(value: '83'));
      }),
      ('DayChips — Fri & Sat selected (S05-10)', (context) {
        return const DayChips(selected: {4, 5});
      }),
      ('PrismToggle — on / off', (context) {
        return const Row(
          children: [
            PrismToggle(on: true),
            SizedBox(width: 12),
            PrismToggle(on: false),
          ],
        );
      }),
      ('SettingsRow — value+chevron / sub / toggle', (context) {
        return Column(
          children: [
            const SettingsRow(title: 'Volume policy', value: '26–70%'),
            const SizedBox(height: 8),
            const SettingsRow(
                title: 'Zones & open hours',
                sub: 'Place',
                value: '2 · 7am–11pm'),
            const SizedBox(height: 8),
            SettingsRow(
              title: 'Quiet hours',
              sub: 'After 10:00 pm · cap at 55%',
              chevron: false,
              trailing: const PrismToggle(on: true),
            ),
          ],
        );
      }),
      ('PrismDropdownMenu — selected check', (context) {
        return const Align(
          alignment: Alignment.centerLeft,
          child: PrismDropdownMenu(
            options: ['2 min', '5 min', '15 min', '30 min'],
            selected: 1,
          ),
        );
      }),
      ('AccountMenu', (context) {
        return Align(
          alignment: Alignment.centerLeft,
          child: AccountMenu(user: _priya),
        );
      }),
      ('VenueRow — healthy / problem', (context) {
        return const Column(
          children: [
            VenueRow(name: 'Marina Café', sub: '2 zones · Afternoon lift'),
            SizedBox(height: 8),
            VenueRow(
              name: 'Dockside Bar',
              sub: 'Back patio offline · 12 min',
              status: ZoneStatus.offline,
            ),
            SizedBox(height: 8),
            VenueRow(
              name: 'Harbor House',
              sub: 'Off schedule · returns in 40 min',
              status: ZoneStatus.offSchedule,
              quickFixLabel: 'Return to Auto',
            ),
          ],
        );
      }),
      ('ZoneRow — ok / offline / off-schedule quick-fix', (context) {
        return const Column(
          children: [
            ZoneRow(name: 'Main floor', statusText: 'Afternoon lift · Auto'),
            SizedBox(height: 8),
            ZoneRow(
              name: 'Back patio',
              statusText: 'Offline · 12 min',
              status: ZoneStatus.offline,
            ),
            SizedBox(height: 8),
            ZoneRow(
              name: 'Terrace',
              statusText: 'Off schedule · returns in 40 min',
              status: ZoneStatus.offSchedule,
              quickFixLabel: 'Return to Auto',
            ),
          ],
        );
      }),
      ('ConfirmDialog — S01-3 vibe switch / S02-3 return', (context) {
        final palette = Theme.of(context).extension<PrismPalette>()!;
        final evening = moodById('evening-warmth');
        return Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            ConfirmDialog(
              icon: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: evening.dot(palette.brightness),
                  shape: BoxShape.circle,
                ),
              ),
              title: 'Switch to Evening warmth?',
              body: const TextSpan(
                  text: 'The room eases over ~40s. 92 BPM · energy 3/5.'),
              confirmLabel: 'Switch the vibe',
            ),
            ConfirmDialog(
              icon: Icon(LucideIcons.rotateCcw,
                  size: 20, color: palette.accentText),
              title: 'Return to Prism now?',
              body: TextSpan(children: [
                const TextSpan(
                    text: 'Prism takes the room back and resumes '),
                TextSpan(
                    text: 'Afternoon lift',
                    style: PrismType.dialogBody.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary)),
                const TextSpan(
                    text:
                        '. Your own audio will stop playing on the speakers.'),
              ]),
              confirmLabel: 'Return to Prism',
            ),
          ],
        );
      }),
      ('PrismBottomSheet — extend takeover (static)', (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: PrismBottomSheet(
            title: 'Extend takeover',
            sub: 'Your audio keeps playing, Prism just waits longer.',
            primaryLabel: 'Extend',
            children: const [
              SizedBox(height: 16),
              SegToggle(
                options: ['15 mins', '30 mins', '1 hour', '2 hours'],
                selected: 1,
              ),
            ],
          ),
        );
      }),
      ('TimeDialSheet — 7:00 AM (interactive)', (context) {
        return ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: TimeDialSheet(title: 'Opening time', initialHour: 7),
        );
      }),
      ('Icons — lucide picks + hand-ported chevrons/checks', (context) {
        final palette = Theme.of(context).extension<PrismPalette>()!;
        final c = palette.textPrimary;
        return Wrap(
          spacing: 14,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(LucideIcons.music, size: 20, color: c),
            Icon(LucideIcons.headphones, size: 20, color: c),
            Icon(LucideIcons.calendar, size: 20, color: c),
            Icon(LucideIcons.mapPin, size: 20, color: c),
            Icon(LucideIcons.settings, size: 20, color: c),
            Icon(LucideIcons.pause, size: 20, color: c),
            Icon(LucideIcons.play, size: 20, color: c),
            Icon(LucideIcons.mail, size: 19, color: c),
            Icon(LucideIcons.lock, size: 19, color: c),
            Icon(LucideIcons.eye, size: 18, color: c),
            Icon(LucideIcons.logOut, size: 15, color: c),
            Icon(LucideIcons.rotateCcw, size: 17, color: c),
            Icon(LucideIcons.clock, size: 15, color: c),
            PrismChevron(direction: ChevronDirection.left, size: 15, color: c),
            PrismChevron(direction: ChevronDirection.right, size: 15, color: c),
            PrismChevron(direction: ChevronDirection.down, size: 15, color: c),
            PrismCheck(size: 15, color: c),
          ],
        );
      }),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Widget gallery (debug)'),
        backgroundColor: const Color(0xFF111111),
        foregroundColor: const Color(0xFFEEEEEE),
      ),
      backgroundColor: const Color(0xFF0A0A0A),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        itemBuilder: (context, i) {
          final (title, builder) = sections[i];
          return Padding(
            padding: const EdgeInsets.only(bottom: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF999999))),
                const SizedBox(height: 8),
                _ThemePair(builder: builder),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Renders the same sample under the dark and light Prism themes, stacked.
class _ThemePair extends StatelessWidget {
  const _ThemePair({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    Widget panel(PrismPalette palette, String label) {
      return Theme(
        data: buildPrismTheme(palette),
        child: Builder(
          builder: (themed) => Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: palette.screen,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: palette.textTertiary)),
                const SizedBox(height: 10),
                builder(themed),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        panel(PrismPalette.dark, 'DARK'),
        const SizedBox(height: 8),
        panel(PrismPalette.light, 'LIGHT'),
      ],
    );
  }
}
