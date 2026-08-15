import 'package:flutter/material.dart';

import '../../data/models/schedule_entry.dart';
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'status_pill.dart';

/// Today's-schedule rail on Floor — §2 S01-1: w268 fixed, border-left 1px
/// `border`, bg `surface`, padding 18. Header mb14: "TODAY'S SCHEDULE"
/// labelCaps + "Auto" chip. Rows gap 16: time 11/700 `textSecondary` w34 +
/// mood dot 8 + name 12. Past rows opacity .42. Current row: bg `accentSoft`,
/// border 1px `accent`, r10, padding 8×9, margin-h −3, time `accentText` 800,
/// name 12.5/700, trailing NOW badge. Next row: trailing "up next" 10
/// `textTertiary`.
class ScheduleRail extends StatelessWidget {
  const ScheduleRail({
    super.key,
    required this.entries,
    required this.nowIndex,
    this.nextIndex = -1,
    this.selfDrive = false,
    this.offSchedule = false,
    this.horizontal = false,
  });

  final List<ScheduleEntry> entries;
  final int nowIndex;

  /// First entry still to come, or -1 when the day is done. Drives "up next"
  /// and, with [nowIndex], which rows are over.
  final int nextIndex;

  /// S03-1: Prism is picking the vibe itself, so the saved plan is not
  /// running. Listing dayparts with a highlighted "NOW" row would claim a
  /// schedule is in charge when nothing is following it — the rail shows the
  /// self-drive state instead.
  final bool selfDrive;

  /// A human overrode the plan, so neither "Auto" nor "Self-drive" is true
  /// right now. Without this the rail keeps announcing Auto over a room
  /// somebody has taken off its schedule, contradicting the hero card two
  /// inches away.
  final bool offSchedule;

  /// §6-A1 portrait: the rail "moves below the mood grid as a horizontal
  /// strip" — same header + rows rendered as a scrollable strip (derived;
  /// portrait is not drawn).
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final b = palette.brightness;

    if (horizontal) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 15),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Flexible so the header yields rather than the row
                // overflowing: "Off schedule" is a wider pill than "Auto", and
                // the rail is a fixed 268.
                Flexible(
                  child: Text(_header,
                      overflow: TextOverflow.ellipsis,
                      style: PrismType.labelCaps
                          .copyWith(color: palette.textSecondary)),
                ),
                StatusPill(
                    text: offSchedule
                        ? 'Off schedule'
                        : (selfDrive ? 'Self-drive' : 'Auto'),
                    tone: offSchedule ? PillTone.amber : PillTone.accent),
              ],
            ),
            const SizedBox(height: 10),
            if (selfDrive)
              _selfDriveNote(palette)
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < entries.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      _stripEntry(palette, b, i),
                    ],
                  ],
                ),
              ),
          ],
        ),
      );
    }

    Widget row(int i) {
      final entry = entries[i];
      final mood = moodById(entry.moodId);
      final current = i == nowIndex;
      // Over: earlier than the next one still to come, and not the one
      // playing. `i < nowIndex` was only right while something was underway —
      // in a gap it dimmed nothing, so a block that ended hours ago read as
      // upcoming. A day with nothing left (nextIndex -1) is entirely past.
      final past = !current && (nextIndex < 0 || i < nextIndex);
      final next = i == nextIndex;

      final content = Row(
        children: [
          SizedBox(
            // The frame pinned w34 for bare "7:00" labels; the meridiem
            // ("11:00 pm") exists because 07:00 and 19:00 rendered
            // identically once evening dayparts arrived, and it needs the
            // extra room.
            width: 52,
            child: Text(
              entry.timeLabel,
              style: PrismType.label.copyWith(
                fontSize: 11,
                fontWeight: current ? FontWeight.w800 : FontWeight.w700,
                color: current ? palette.accentText : palette.textSecondary,
              ),
            ),
          ),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: mood.dot(b), shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              mood.name,
              style: current
                  ? PrismType.button
                      .copyWith(fontSize: 12.5, color: palette.textPrimary)
                  : PrismType.meta.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary),
            ),
          ),
          if (current)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('NOW',
                  style: PrismType.nowBadge.copyWith(color: palette.chipInk)),
            )
          else if (next)
            // §1.4 micro band floor is 600 — no 10px/400 style exists.
            Text('up next',
                style: PrismType.micro.copyWith(
                    fontWeight: FontWeight.w600, color: palette.textTertiary)),
        ],
      );

      // CSS margin-h −3 on the current row: the rail pads 15 and normal rows
      // add 3, so the current row bleeds 3px past its siblings on both sides.
      if (current) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 9),
          decoration: BoxDecoration(
            color: palette.accentSoft,
            border: Border.all(color: palette.accent),
            borderRadius: BorderRadius.circular(10),
          ),
          child: content,
        );
      }
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Opacity(opacity: past ? .42 : 1, child: content),
      );
    }

    return Container(
      width: 268,
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 15),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(left: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(_header,
                      overflow: TextOverflow.ellipsis,
                      style: PrismType.labelCaps
                          .copyWith(color: palette.textSecondary)),
                ),
                StatusPill(
                    text: offSchedule
                        ? 'Off schedule'
                        : (selfDrive ? 'Self-drive' : 'Auto'),
                    tone: offSchedule ? PillTone.amber : PillTone.accent),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (selfDrive)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: _selfDriveNote(palette),
            )
          else
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) const SizedBox(height: 16),
              row(i),
            ],
        ],
      ),
    );
  }

  /// "TODAY'S SCHEDULE" describes a plan that is running; on self-drive there
  /// is no plan to describe.
  String get _header => selfDrive ? 'RIGHT NOW' : "TODAY'S SCHEDULE";

  /// The rail's self-drive state. Mirrors the S03-1 empty state's language so
  /// the two screens agree, and names Schedule as the place to change it —
  /// otherwise a manager wondering where their dayparts went has nowhere to
  /// look.
  Widget _selfDriveNote(PrismPalette palette) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Prism is picking the vibe',
            style: PrismType.bodySm.copyWith(color: palette.textPrimary)),
        const SizedBox(height: 6),
        Text(
          'It reads the room — time of day, how busy it is, how loud — and '
          'changes the mood as the day moves.',
          style: PrismType.meta.copyWith(
              fontWeight: FontWeight.w400,
              height: 1.45,
              color: palette.textSecondary),
        ),
        const SizedBox(height: 10),
        Text(
          entries.isEmpty
              ? 'Build a custom plan in Schedule to pin moods to times.'
              : 'Your saved plan is paused. Switch to Custom plan in Schedule '
                  'to run it.',
          style: PrismType.micro.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.45,
              color: palette.textTertiary),
        ),
      ],
    );
  }

  /// One compact chip of the portrait strip: time + dot + name (+ NOW).
  Widget _stripEntry(PrismPalette palette, Brightness b, int i) {
    final entry = entries[i];
    final mood = moodById(entry.moodId);
    final current = i == nowIndex;
    final past = !current && (nextIndex < 0 || i < nextIndex);

    final chip = Container(
      padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 10),
      decoration: BoxDecoration(
        color: current ? palette.accentSoft : palette.tile,
        border:
            Border.all(color: current ? palette.accent : palette.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            entry.timeLabel,
            style: PrismType.label.copyWith(
              fontSize: 11,
              fontWeight: current ? FontWeight.w800 : FontWeight.w700,
              color: current ? palette.accentText : palette.textSecondary,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: mood.dot(b), shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            mood.name,
            style: current
                ? PrismType.button
                    .copyWith(fontSize: 12.5, color: palette.textPrimary)
                : PrismType.meta.copyWith(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary),
          ),
          if (current) ...[
            const SizedBox(width: 7),
            Container(
              padding:
                  const EdgeInsets.symmetric(vertical: 2, horizontal: 7),
              decoration: BoxDecoration(
                color: palette.accent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text('NOW',
                  style:
                      PrismType.nowBadge.copyWith(color: palette.chipInk)),
            ),
          ],
        ],
      ),
    );
    return Opacity(opacity: past ? .42 : 1, child: chip);
  }
}
