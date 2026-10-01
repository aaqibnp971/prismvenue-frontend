import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api/api_exception.dart';
import '../../data/models/schedule_entry.dart';
import '../../data/repositories/schedule_repo.dart';
import '../../shared/widgets/day_chips.dart';
import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_toast.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/seg_toggle.dart';
import '../settings/widgets/time_field.dart';
import 'confirm_delete_daypart_dialog.dart';
import 'replace_daypart_dialog.dart';
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// S03-4 "Add a daypart — pick day, time & mood" / S03-5 "Edit a daypart —
/// same controls, plus Delete". BottomSheet: day chips row, time fields,
/// mood picker grid (6 tiles small), CTA; edit adds a full-width
/// "Delete daypart" `red` text button at the bottom.
/// [weekStart] is the Monday of the week on screen, and [alreadyForked] says
/// whether that week has its own plan already.
///
/// Together they decide whether the sheet has to ask "every week or just this
/// one": a week that has already diverged has nothing to ask — every edit
/// stays in that week — and a week still on the recurring plan does, because
/// forking is permanent in one direction and must never happen by accident.
/// [dayIndex] and [startMinutes] pre-fill the sheet — finding #11. The add
/// sheet always opened on Monday at 6pm, so building a week meant correcting
/// the day on every one of thirty-five saves. Tapping an empty patch of
/// Thursday afternoon should mean Thursday afternoon.
Future<void> showDaypartSheet(
  BuildContext context,
  WidgetRef ref, {
  Daypart? existing,
  DateTime? weekStart,
  bool alreadyForked = false,
  int? dayIndex,
  int? startMinutes,
}) async {
  final result = await showPrismSheet<_DaypartResult>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: _DaypartSheet(
      existing: existing,
      canChooseScope: weekStart != null && !alreadyForked,
      forkedWeek: alreadyForked,
      initialDay: dayIndex,
      initialStart: startMinutes,
    ),
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
      case _Save(:final daypart, :final justThisWeek, :final days):
        // Fork FIRST, then write. Forking copies the recurring plan into the
        // week and gives every row a new id, so an edit applied beforehand
        // would either be copied into the fork twice or be aimed at an id the
        // week no longer contains.
        if (justThisWeek && weekStart != null) {
          await repo.forkWeek(weekStart);
        }
        final scopeToWeek = justThisWeek || alreadyForked;
        var scoped = scopeToWeek
            ? daypart.copyWith(weekStart: weekStart)
            : daypart.copyWith(clearWeekStart: true);

        // Re-aim the edit at the COPY the fork just made.
        //
        // This is the half the comment above described and the code did not
        // do. Forking duplicates every recurring row into the week under a new
        // id; `existing.id` still names the recurring row it was copied FROM.
        // Sending that id meant `PATCH /dayparts/{id}` — which never writes
        // `week_start` — rewrote the recurring plan, so adjusting one Tuesday
        // changed every Tuesday, and the server answered 200 because nothing
        // about the request was invalid.
        //
        // Matched on the ORIGINAL day and times, because the fork is a copy of
        // the plan as it was before this edit. A daypart is unique within a
        // plan by (day, start) — migration 013 makes that a constraint — so the
        // match is exact rather than a best guess.
        if (justThisWeek && weekStart != null && existing != null) {
          scoped = scoped.copyWith(
              id: await _idInForkedWeek(repo, weekStart, existing));
        }
        // Finding #11: adding writes one row per selected day. Editing is
        // still one row — an existing daypart is a single row, and spreading
        // it over a week is a different verb ("Copy day to…").
        if (existing == null && days.length > 1) {
          if (!context.mounted) return;
          await _addAcrossDays(context, ref, repo, scoped, days);
          return;
        }

        Future<void> write({required bool replace}) => existing == null
            ? repo.addDaypart(scoped, replace: replace)
            : repo.updateDaypart(scoped, replace: replace);

        // Try, then ask. The server owns the answer — another iPad may have
        // taken the slot a second ago — so a local pre-check would be both
        // slower to write and wrong more often. A 409 here is not a failure to
        // report, it is a question to put.
        // Finding #14: a save used to close the sheet and say nothing. The
        // grid does redraw, but only once the stream refreshes, and a block
        // that moved by five minutes looks exactly like one that did not.
        void saved() {
          if (context.mounted) {
            showPrismToast(
                context, existing == null ? 'Daypart added' : 'Daypart saved');
          }
        }

        try {
          await write(replace: false);
          saved();
        } on ApiException catch (e) {
          if (e.code != 'daypart_slot_taken') rethrow;
          if (!context.mounted) return;

          // Best effort: the 409 does not say what was in the way, so the
          // occupant is looked up in the plan the screen already holds. Null
          // when it cannot be found, and the copy drops the name rather than
          // guessing at one.
          // Keyed by the week the SCREEN is showing, not by the daypart's own
          // weekStart. They differ: a row on the recurring plan has a null
          // weekStart while the screen is watching a specific Monday, and
          // reading the other family member gets a provider nobody has
          // subscribed to — freshly created, therefore empty.
          final plan = ref.read(weekPlanProvider(weekStart)).value;
          final clash = plan
              ?.where((d) =>
                  d.id != scoped.id &&
                  d.dayIndex == scoped.dayIndex &&
                  d.startMinutesOfDay == scoped.startMinutesOfDay)
              .firstOrNull;

          final confirmed = await showReplaceDaypartDialog(
            context,
            timeLabel: TimeField.timeLabel(scoped.startMinutesOfDay),
            dayName: _dayNames[scoped.dayIndex],
            newMoodName: moodById(scoped.moodId).name,
            replacedMoodName:
                clash == null ? null : moodById(clash.moodId).name,
          );
          if (confirmed != true) return;
          await write(replace: true);
          saved();
        }
      case _Delete(:final id, justThisWeek: final deleteJustThisWeek):
        // Fork first, then delete the COPY. The comment here used to name the
        // hazard — "the id being deleted belongs to the recurring plan and the
        // deletion would hit every week" — and the code then did precisely
        // that, because forking does not renumber the row the sheet was opened
        // with. Deleting one Tuesday deleted every Tuesday.
        var targetId = id;
        if (deleteJustThisWeek && weekStart != null) {
          await repo.forkWeek(weekStart);
          if (existing != null) {
            targetId = await _idInForkedWeek(repo, weekStart, existing);
          }
        }
        await repo.deleteDaypart(targetId);
        if (context.mounted) showPrismToast(context, 'Daypart deleted');
    }
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
  }
}

/// Writes one daypart onto several days, asking once about whatever was
/// already there. Finding #11.
///
/// The repository writes every day it can and reports the ones whose slot was
/// taken, rather than stopping at the first. A manager laying a block across
/// Mon–Fri usually has something on exactly one of those days, and aborting
/// the batch for it would make the fast path fail more often than the five
/// separate saves it replaces.
Future<void> _addAcrossDays(
  BuildContext context,
  WidgetRef ref,
  ScheduleRepo repo,
  Daypart daypart,
  List<int> days,
) async {
  final clashed = await repo.addDayparts(
    [for (final day in days) daypart.copyWith(dayIndex: day)],
  );
  if (!context.mounted) return;
  if (clashed.isEmpty) {
    showPrismToast(context, 'Added to ${days.length} days');
    return;
  }

  // One question for the whole batch, naming the days. Asking per day would
  // reintroduce exactly the tapping this feature exists to remove.
  final plan = ref.read(weekPlanProvider(daypart.weekStart)).value;
  final replaced = <String>{
    for (final day in clashed)
      ...?plan
          ?.where((d) =>
              d.dayIndex == day &&
              d.startMinutesOfDay == daypart.startMinutesOfDay)
          .map((d) => moodById(d.moodId).name),
  };

  final confirmed = await showReplaceDaypartDialog(
    context,
    timeLabel: TimeField.timeLabel(daypart.startMinutesOfDay),
    dayName: clashed.map((d) => _dayNames[d]).join(', '),
    newMoodName: moodById(daypart.moodId).name,
    replacedMoodName: replaced.length == 1 ? replaced.first : null,
  );
  if (confirmed != true) return;

  await repo.addDayparts(
    [for (final day in clashed) daypart.copyWith(dayIndex: day)],
    replace: true,
  );
  if (context.mounted) showPrismToast(context, 'Added to ${days.length} days');
}

/// The id of this daypart's copy inside a week that has just been forked.
///
/// Forking duplicates every recurring row under a **new** id, so the id the
/// sheet was opened with names the row the copy was made FROM. Writing to it
/// edits or deletes the recurring plan — every week — which is the opposite of
/// what "just this week" means. The server cannot catch it either: the request
/// is perfectly valid, so it answers 200, and `PATCH /dayparts/{id}` does not
/// write `week_start` at all.
///
/// Matched on day and times rather than by position, because the fork is a copy
/// of the plan as it stood before this change and a daypart is unique within a
/// plan by (day, start) — migration 013 makes that a constraint.
Future<String> _idInForkedWeek(
  ScheduleRepo repo,
  DateTime weekStart,
  Daypart original,
) async {
  final forked = await repo.watchWeekPlan(weekStart).first;
  final copy = forked
      .where((d) =>
          d.dayIndex == original.dayIndex &&
          d.startMinutesOfDay == original.startMinutesOfDay &&
          d.endMinutesOfDay == original.endMinutesOfDay)
      .firstOrNull;
  if (copy == null) {
    // Refusing beats falling back to the recurring id, which IS the blocker:
    // a change that silently rewrites every week is far worse than one that
    // says it could not be applied.
    throw const ApiException(
      statusCode: 0,
      code: 'fork_copy_missing',
      message: 'That week could not be given its own plan. Nothing was changed.',
    );
  }
  return copy.id;
}

const _dayNames = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

sealed class _DaypartResult {}

class _Save extends _DaypartResult {
  _Save(this.daypart, {this.justThisWeek = false, List<int>? days})
      : days = days ?? [daypart.dayIndex];
  final Daypart daypart;

  /// Every day the block should land on — finding #11. Always at least one,
  /// and always exactly one when editing. [daypart] carries the first of them,
  /// so a single-day save reads as it always did.
  final List<int> days;

  /// True when the manager chose "Just this week" on a week that had not
  /// diverged yet — the only thing that ever creates a fork.
  final bool justThisWeek;
}

class _Delete extends _DaypartResult {
  _Delete(this.id, {this.justThisWeek = false});
  final String id;
  final bool justThisWeek;
}

class _DaypartSheet extends StatefulWidget {
  const _DaypartSheet({
    this.existing,
    this.canChooseScope = false,
    this.forkedWeek = false,
    this.initialDay,
    this.initialStart,
  });

  final Daypart? existing;

  /// Whether to offer "Every week / Just this week".
  ///
  /// False once the week has already forked: every edit stays in that week and
  /// there is nothing left to decide, so asking again would imply the choice
  /// still meant something.
  final bool canChooseScope;

  /// The week on screen has already forked. Mutually exclusive with
  /// [canChooseScope]: one offers the decision, the other reports it.
  final bool forkedWeek;

  /// Where the manager tapped — finding #11. Ignored when editing, which
  /// takes its day and time from the row.
  final int? initialDay;
  final int? initialStart;

  @override
  State<_DaypartSheet> createState() => _DaypartSheetState();
}

class _DaypartSheetState extends State<_DaypartSheet> {
  /// Finding #11: a set, because one block usually belongs on several days.
  /// Editing keeps exactly one — an existing daypart is one row.
  late Set<int> _days = {
    widget.existing?.dayIndex ?? widget.initialDay ?? 0,
  };

  /// Whether the manager has touched the day chips yet.
  ///
  /// The day the sheet opens on is a guess — Monday, or wherever the grid was
  /// tapped — so the FIRST chip tap replaces it rather than adding to it, and
  /// every tap after that toggles. Without this, picking one day meant two
  /// taps (choose it, then unpick the guess), which is a tax on the common
  /// case to pay for the rarer one.
  var _daysTouched = false;
  late String _moodId = widget.existing?.moodId ?? moods.first.id;

  // `open_questions.md` #18 flagged that no time picker was designed and the
  // field was free text. It reuses the S05-12 dial the open-hours flow already
  // uses, so no new visual language is introduced — and the backend gets real
  // times, without which it cannot compute what plays when.
  //
  // Minutes past midnight, and the dial is opened at [_minuteStep]. A daypart
  // boundary is a business decision — a kitchen that turns over at 6:30, a bar
  // that lifts at 9:45 — and rounding it to the hour was a limit of the write
  // path, never of the column: `dayparts.start_local` is a Postgres `time`.
  late int _start =
      widget.existing?.startMinutesOfDay ?? widget.initialStart ?? 18 * 60;
  late int _end = widget.existing?.endMinutesOfDay ??
      ((widget.initialStart ?? 18 * 60) + 3 * 60).clamp(0, 24 * 60 - 1);

  /// Five minutes. Fine enough that nobody reaches for a keyboard, coarse
  /// enough that the wheel is twelve flickable items rather than sixty.
  static const _minuteStep = 5;

  /// Defaults to "Every week". The recurring plan is the normal case, and the
  /// destructive-ish option should be the one you pick on purpose.
  var _justThisWeek = false;

  /// Why the range is unusable, or null when it is fine.
  ///
  /// Blocks the save rather than warning after the fact: the sheet has already
  /// popped by the time the write runs, so a server rejection would have no
  /// dialog to report into.
  String? get _rangeError {
    if (_days.isEmpty) return 'Pick at least one day.';
    if (_end == _start) return 'Start and end cannot be the same time.';
    if (_end < _start) return 'End time must be after the start time.';
    return null;
  }

  /// Lowest selected day. The one the [Daypart] itself carries, so a
  /// single-day save is byte-identical to what it was before finding #11.
  int get _firstDay => (_days.toList()..sort()).first;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final editing = widget.existing != null;

    return PrismBottomSheet(
      title: editing ? 'Edit daypart' : 'Add a daypart',
      sub: 'Pick day, time & mood.',
      // Says how many rows the button is about to write. "Add daypart" on a
      // tap that creates five is the app being coy about what it did.
      primaryLabel: editing
          ? 'Save'
          : _days.length > 1
              ? 'Add to ${_days.length} days'
              : 'Add daypart',
      // There was no cross-field check here and the server validated each hour
      // only as 0–23, so "Starts 9pm / Ends 7am" saved cleanly, as did a
      // zero-length 6pm–6pm. These decide what actually plays in the room, and
      // neither shape has a meaning the scheduler can act on. Both ends are
      // compared as minutes, so 6:00–6:30 is allowed and 6:30–6:00 is not.
      onPrimary: _rangeError != null
          ? null
          : () => Navigator.of(context).pop(_Save(
                Daypart(
                  id: widget.existing?.id ?? '',
                  dayIndex: _firstDay,
                  startHour: _start ~/ 60,
                  endHour: _end ~/ 60,
                  startMinute: _start % 60,
                  endMinute: _end % 60,
                  moodId: _moodId,
                ),
                justThisWeek: _justThisWeek,
                days: _days.toList()..sort(),
              )),
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 16),
        // Day chips row — §3 DayChips (12/700). Multi-select when adding
        // (finding #11 — the widget already held a Set), single when editing.
        DayChips(
          selected: _days,
          onToggle: (i) => setState(() {
            if (editing || !_daysTouched) {
              _daysTouched = true;
              _days = {i};
            } else if (!_days.remove(i)) {
              _days.add(i);
            }
          }),
        ),
        if (!editing) ...[
          const SizedBox(height: 7),
          Text(
            _days.length > 1
                ? 'The same block will be added to ${_days.length} days.'
                : 'Tap more days to add the same block to each of them.',
            style:
                PrismType.microHelper.copyWith(color: palette.textSecondary),
          ),
        ],
        if (widget.canChooseScope) ...[
          const SizedBox(height: 14),
          Text('Applies to',
              style: PrismType.label.copyWith(color: palette.textSecondary)),
          const SizedBox(height: 8),
          SegToggle(
            options: const ['Every week', 'Just this week'],
            selected: _justThisWeek ? 1 : 0,
            onChanged: (i) => setState(() => _justThisWeek = i == 1),
          ),
          const SizedBox(height: 7),
          Text(
            _justThisWeek
                // The cost, said before it is paid rather than discovered
                // later. A forked week stops tracking the recurring plan
                // permanently, and nothing else on screen would reveal that.
                ? 'This week gets its own copy of the plan and stops following '
                    'later changes to every week.'
                : 'Changes the plan every week follows.',
            style: PrismType.microHelper
                .copyWith(color: palette.textSecondary),
          ),
        ] else if (widget.forkedWeek) ...[
          // The choice is gone, so the consequence has to be stated instead.
          // Silence here is what let an edit look like it had not saved: the
          // week is already its own copy, so the change is real and correct and
          // simply does not reach any other week — and nothing said so.
          const SizedBox(height: 14),
          Text('Applies to',
              style: PrismType.label.copyWith(color: palette.textSecondary)),
          const SizedBox(height: 6),
          Text(
            'This week only. It has its own copy of the plan and no longer '
            'follows the one every week uses.',
            style: PrismType.microHelper
                .copyWith(color: palette.textSecondary),
          ),
        ],
        const SizedBox(height: 14),
        Text('Time',
            style: PrismType.label.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TimeField(
                label: 'Starts',
                minutes: _start,
                minuteStep: _minuteStep,
                dialTitle: 'Start time',
                onChanged: (m) => setState(() => _start = m),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TimeField(
                label: 'Ends',
                minutes: _end,
                minuteStep: _minuteStep,
                dialTitle: 'End time',
                onChanged: (m) => setState(() => _end = m),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        // Says why the save is unavailable. A disabled button with no reason
        // reads as a broken sheet.
        Text(
          _rangeError ?? 'Tap a time to set it on the dial.',
          style: PrismType.microHelper.copyWith(
              color: _rangeError != null
                  ? palette.red
                  : palette.textSecondary),
        ),
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
            // Confirmed, like "Remove zone". A daypart is not recoverable from
            // the UI -- no undo, no history -- and the sheet is opened by
            // tapping a block in a grid, so picking the wrong one is exactly
            // the mistake worth catching.
            onTap: () async {
              final confirmed = await showConfirmDeleteDaypartDialog(
                context,
                dayName: DayChips.labels[_firstDay],
                // Minutes past midnight in, hours and minutes out. This passed
                // the raw minute counts as hours, so the dialog offered to
                // delete "12 – 12 pm" whatever the block actually was — a
                // confirmation naming the wrong thing is worse than none.
                rangeLabel: Daypart.formatRange(
                  _start ~/ 60,
                  _end ~/ 60,
                  startMinute: _start % 60,
                  endMinute: _end % 60,
                ),
                moodName: moodById(_moodId).name,
              );
              if (confirmed != true) return;
              if (!context.mounted) return;
              Navigator.of(context).pop(_Delete(widget.existing!.id,
                  justThisWeek: _justThisWeek));
            },
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
