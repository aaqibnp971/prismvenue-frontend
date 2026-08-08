import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/schedule_entry.dart';
import '../../data/repositories/schedule_repo.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/prism_icons.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/seg_toggle.dart';
import '../../shared/widgets/status_pill.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'daypart_sheet.dart';
import 'week_grid.dart';
import 'week_picker.dart';

const _monthNames = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// §2 S03 Schedule (manager + owner). S03-1 self-drive empty state ⇄ S03-2
/// custom weekly plan; §4: jump-week / add-daypart / edit-daypart are modals
/// that all return to custom.
class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});

  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  /// Monday of the displayed week (view state; the mock plan recurs weekly).
  late DateTime _weekStart = _mondayOf(DateTime.now());

  static DateTime _mondayOf(DateTime d) =>
      DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

  String get _rangeLabel {
    final end = _weekStart.add(const Duration(days: 6));
    return '${_monthNames[_weekStart.month - 1]} ${_weekStart.day} – '
        '${_monthNames[end.month - 1]} ${end.day}';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final header = ref.watch(venueHeaderProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects
    final mode =
        ref.watch(scheduleModeProvider).value ?? ScheduleMode.selfDrive;

    return Scaffold(
      body: Column(
        children: [
          PrismTopBar(
            title: header.title,
            subtitle: header.subtitle,
            statusDot: header.statusDot,
            user: user,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // S03-1 ⇄ S03-2 switch.
                  SegToggle(
                    options: const ['Self-drive', 'Custom plan'],
                    selected: mode == ScheduleMode.selfDrive ? 0 : 1,
                    // Awaited and caught: switching self-drive ⇄ custom decides
                    // whether the saved plan runs at all, so a failure that
                    // leaves the toggle looking switched is worse here than
                    // almost anywhere else in the app.
                    onChanged: (i) async {
                      try {
                        await ref.read(scheduleRepoProvider).setMode(i == 0
                            ? ScheduleMode.selfDrive
                            : ScheduleMode.custom);
                      } catch (e) {
                        if (context.mounted) showPrismError(context, e);
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  Expanded(
                    child: mode == ScheduleMode.selfDrive
                        ? const _SelfDriveCard()
                        : _WeekPlan(
                            weekStart: _weekStart,
                            rangeLabel: _rangeLabel,
                            onPrevWeek: () => setState(() => _weekStart =
                                _weekStart.subtract(const Duration(days: 7))),
                            onNextWeek: () => setState(() => _weekStart =
                                _weekStart.add(const Duration(days: 7))),
                            onPickWeek: () async {
                              final picked = await showWeekPicker(context,
                                  selected: _weekStart);
                              if (picked != null) {
                                setState(
                                    () => _weekStart = _mondayOf(picked));
                              }
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// S03-1 "Self-drive — Prism reads the room, no fixed schedule": centered
/// card (bg `surface`, border, r14), "Prism is self-driving" 17/700 + sub.
class _SelfDriveCard extends StatelessWidget {
  const _SelfDriveCard();

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Center(
      child: Container(
        width: 420,
        padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 28),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Prism is self-driving',
                style: PrismType.body.copyWith(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: palette.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Prism reads the room — crowd, time of day, noise — and picks '
              'the vibe on its own. Switch to a custom plan to pin moods to '
              'dayparts.',
              textAlign: TextAlign.center,
              style: PrismType.meta
                  .copyWith(fontSize: 11.5, color: palette.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

/// S03-2 "Custom weekly plan — dayparts & moods, add any time": week header
/// (date range + chevrons + "+ Add" accent button) over day columns of
/// daypart rows (time range 11/700, mood dot + name; tap → S03-5 edit).
class _WeekPlan extends ConsumerWidget {
  const _WeekPlan({
    required this.weekStart,
    required this.rangeLabel,
    required this.onPrevWeek,
    required this.onNextWeek,
    required this.onPickWeek,
  });

  final DateTime weekStart;
  final String rangeLabel;
  final VoidCallback onPrevWeek;
  final VoidCallback onNextWeek;
  final VoidCallback onPickWeek;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    // Keyed by the week on screen. Before this the provider took no week, so
    // the arrows moved the header label and nothing else — every week rendered
    // the same dayparts, and "+ Add" added to the recurring plan regardless.
    final plan =
        ref.watch(weekPlanProvider(weekStart)).value ?? const <Daypart>[];

    // A week is entirely a fork or entirely the recurring plan, never a mix, so
    // the first row answers it for the whole week.
    final forked = plan.isNotEmpty && plan.first.weekStart != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _ChevronButton(
                direction: ChevronDirection.left, onTap: onPrevWeek),
            const SizedBox(width: 8),
            // S03-3: tap the date to open the calendar popover.
            GestureDetector(
              onTap: onPickWeek,
              child: Text(rangeLabel,
                  style: PrismType.bodySm
                      .copyWith(fontSize: 14, color: palette.textPrimary)),
            ),
            const SizedBox(width: 8),
            _ChevronButton(
                direction: ChevronDirection.right, onTap: onNextWeek),
            if (forked) ...[
              const SizedBox(width: 8),
              // Says out loud that this week has stopped following the
              // recurring plan. Without it the divergence is invisible, and the
              // failure mode is a manager changing "every week" in March and
              // wondering why one week in the calendar ignored it.
              const StatusPill(text: 'Just this week', tone: PillTone.amber),
            ],
            const Spacer(),
            Pressable(
              onTap: () => showDaypartSheet(context, ref, weekStart: weekStart),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
                decoration: BoxDecoration(
                  color: palette.accent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('+ Add',
                    style: PrismType.bodySm
                        .copyWith(fontSize: 12.5, color: palette.chipInk)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(child: WeekGrid(weekStart: weekStart, plan: plan)),
      ],
    );
  }
}

class _ChevronButton extends StatelessWidget {
  const _ChevronButton({required this.direction, required this.onTap});

  final ChevronDirection direction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.tile,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(8),
        ),
        child: PrismChevron(
            direction: direction, size: 13, color: palette.textPrimary),
      ),
    );
  }
}
