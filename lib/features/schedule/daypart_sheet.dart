import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/schedule_entry.dart';
import '../../data/repositories/schedule_repo.dart';
import '../../shared/widgets/day_chips.dart';
import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../settings/widgets/time_field.dart';
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// S03-4 "Add a daypart — pick day, time & mood" / S03-5 "Edit a daypart —
/// same controls, plus Delete". BottomSheet: day chips row, time fields,
/// mood picker grid (6 tiles small), CTA; edit adds a full-width
/// "Delete daypart" `red` text button at the bottom.
Future<void> showDaypartSheet(BuildContext context, WidgetRef ref,
    {Daypart? existing}) async {
  final result = await showPrismSheet<_DaypartResult>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: _DaypartSheet(existing: existing),
  );
  if (result == null) return;
  final repo = ref.read(scheduleRepoProvider);
  // The sheet has already popped by the time these run, so a failure has no
  // dialog to report into and nothing in lib/ installs a global error handler —
  // without this the edit silently does not happen and the grid just keeps
  // showing the old block. Same shape as showExceptionSheet and the Floor
  // screen's mutations.
  try {
    switch (result) {
      case _Save(:final daypart):
        if (existing == null) {
          await repo.addDaypart(daypart);
        } else {
          await repo.updateDaypart(daypart);
        }
      case _Delete(:final id):
        await repo.deleteDaypart(id);
    }
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
  }
}

sealed class _DaypartResult {}

class _Save extends _DaypartResult {
  _Save(this.daypart);
  final Daypart daypart;
}

class _Delete extends _DaypartResult {
  _Delete(this.id);
  final String id;
}

class _DaypartSheet extends StatefulWidget {
  const _DaypartSheet({this.existing});

  final Daypart? existing;

  @override
  State<_DaypartSheet> createState() => _DaypartSheetState();
}

class _DaypartSheetState extends State<_DaypartSheet> {
  late int _day = widget.existing?.dayIndex ?? 0;
  late String _moodId = widget.existing?.moodId ?? moods.first.id;

  // `open_questions.md` #18 flagged that no time picker was designed and the
  // field was free text. It reuses the S05-12 hour dial the open-hours flow
  // already uses, so no new visual language is introduced — and the backend
  // gets real times, without which it cannot compute what plays when.
  late int _start = widget.existing?.startHour ?? 18;
  late int _end = widget.existing?.endHour ?? 21;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final editing = widget.existing != null;

    return PrismBottomSheet(
      title: editing ? 'Edit daypart' : 'Add a daypart',
      sub: 'Pick day, time & mood.',
      primaryLabel: editing ? 'Save' : 'Add daypart',
      onPrimary: () => Navigator.of(context).pop(_Save(Daypart(
        id: widget.existing?.id ?? '',
        dayIndex: _day,
        startHour: _start,
        endHour: _end,
        moodId: _moodId,
      ))),
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 16),
        // Day chips row — §3 DayChips (12/700), single-select for S03-4.
        DayChips(
          selected: {_day},
          onToggle: (i) => setState(() => _day = i),
        ),
        const SizedBox(height: 14),
        Text('Time',
            style: PrismType.label.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TimeField(
                label: 'Starts',
                hour: _start,
                dialTitle: 'Start time',
                onChanged: (h) => setState(() => _start = h),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TimeField(
                label: 'Ends',
                hour: _end,
                dialTitle: 'End time',
                onChanged: (h) => setState(() => _end = h),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text('Tap a time to set it on the dial.',
            style:
                PrismType.microHelper.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 14),
        Text('Mood',
            style: PrismType.label.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 7),
        // Mood picker grid — 6 small tiles.
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              for (var col = 0; col < 3; col++) ...[
                if (col > 0) const SizedBox(width: 8),
                Expanded(
                  child: Builder(builder: (context) {
                    final mood = moods[row * 3 + col];
                    final selected = mood.id == _moodId;
                    return GestureDetector(
                      onTap: () => setState(() => _moodId = mood.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 10),
                        decoration: BoxDecoration(
                          color: selected ? palette.accentSoft : palette.tile,
                          border: Border.all(
                              color:
                                  selected ? palette.accent : palette.border),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: mood.dot(palette.brightness),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(mood.name,
                                  overflow: TextOverflow.ellipsis,
                                  style: PrismType.bodySm.copyWith(
                                      fontSize: 11.5,
                                      color: palette.textPrimary)),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ],
          ),
        ],
        if (editing) ...[
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () =>
                Navigator.of(context).pop(_Delete(widget.existing!.id)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              child: Text('Delete daypart',
                  style: PrismType.button
                      .copyWith(fontSize: 13, color: palette.red)),
            ),
          ),
        ],
      ],
    );
  }
}
