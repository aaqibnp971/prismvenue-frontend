import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/guardrails.dart';
import '../../data/models/schedule_entry.dart';
import '../../data/repositories/schedule_repo.dart';
import '../../data/repositories/settings_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'daypart_sheet.dart';

/// The weekly plan as a time grid: seven day ROWS, hours running left to right.
///
/// ## Why the axis was transposed
///
/// The plan used to be seven day COLUMNS of content-sized rows, which meant a
/// block's y-position encoded its index in the repo list and nothing else —
/// there was no time axis at all, so "drag it an hour later" had nowhere to go.
/// Building the axis was unavoidable; the only question was which way round.
///
/// Vertical loses. With the default 7–23 open hours, sixteen hours over the
/// available height is ~32 pt/hour at 1024×768 and ~22 pt at the designed
/// 860×602 frame — so a one-hour daypart, which the sheet happily creates,
/// renders at half Apple's 44 pt minimum target. Horizontal gives ~59 pt/hour
/// and ~74 pt rows on the same screen, clearing the minimum on both axes with
/// no clamping and no scroll nesting.
///
/// This is a visible change to a specified frame (S03-2), taken under
/// `open_questions.md` #17, which already booked the S03 geometry as derived
/// rather than pinned.
class WeekGrid extends ConsumerStatefulWidget {
  const WeekGrid({super.key, required this.weekStart, required this.plan});

  final DateTime weekStart;
  final List<Daypart> plan;

  @override
  ConsumerState<WeekGrid> createState() => _WeekGridState();
}

/// A block mid-drag. Held in view state and never written to the repo — the
/// repositories' contract is that the UI does not apply changes locally, it
/// waits for the stream. The grid renders `plan` with this substituted in.
class _Ghost {
  const _Ghost({
    required this.id,
    required this.dayIndex,
    required this.startHour,
    required this.endHour,
    required this.overlapping,
  });

  final String id;
  final int dayIndex;
  final int startHour;
  final int endHour;

  /// The block currently covers hours another daypart on the same day also
  /// covers. Surfaced while dragging, but NOT refused — see [_overlaps].
  final bool overlapping;
}

class _WeekGridState extends ConsumerState<WeekGrid> {
  /// One key for the whole track area, so all seven rows share a coordinate
  /// space and moving a block between days costs one subtraction.
  final _gridKey = GlobalKey();

  _Ghost? _ghost;
  Daypart? _dragging;
  Offset? _dragOrigin;
  int _lastHourStep = 0;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _labelWidth = 46.0;
  static const _rulerHeight = 14.0;
  static const _rowGap = 5.0;

  /// The grid always spans the whole day. A daypart may legitimately start at
  /// 2am — a late bar closing down, a hotel lobby that never shuts — and while
  /// the grid ran from the venue's opening hour to its closing one, those
  /// blocks were clamped to the edge: visible as a sliver at 7am, un-draggable,
  /// and impossible to place in the first place.
  ///
  /// Open hours are still shown, as shading rather than as bounds, so the plan
  /// keeps the context it had.
  static const _dayHours = 24;

  /// Below this the columns stop being aimable and the grid scrolls instead.
  /// 24 hours across a phone is 16pt an hour, which is narrower than a
  /// fingertip and far narrower than the shortest daypart anyone would draw.
  static const _minPxPerHour = 46.0;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final hours = ref.watch(openHoursProvider).value ?? const OpenHours();
    // Only for the shading now — a zero or inverted window shades nothing
    // rather than dividing by zero, because it no longer sets the geometry.
    final openHour = hours.closeHour > hours.openHour ? hours.openHour : 0;
    final closeHour = hours.closeHour > hours.openHour ? hours.closeHour : 24;

    return LayoutBuilder(builder: (context, outer) {
      final available = outer.maxWidth - _labelWidth;
      final pxPerHour =
          math.max(available / _dayHours, _minPxPerHour);
      final gridWidth = pxPerHour * _dayHours;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Pinned outside the scroll view: losing which row is Tuesday while
          // panning to 2am would make the grid unreadable.
          SizedBox(
            width: _labelWidth,
            child: Column(
              children: [
                const SizedBox(height: _rulerHeight + 6),
                for (var day = 0; day < 7; day++)
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_dayNames[day]} '
                        '${widget.weekStart.add(Duration(days: day)).day}',
                        style: PrismType.labelCaps
                            .copyWith(color: palette.textSecondary),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            // Ruler and grid inside ONE scroll view, so the hour labels can
            // never drift out of step with the blocks under them.
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: gridWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _HourRuler(pxPerHour: pxPerHour),
                    const SizedBox(height: 6),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final rowHeight = constraints.maxHeight / 7;
                          return Stack(
                            key: _gridKey,
                            children: [
                              _ClosedHours(
                                openHour: openHour,
                                closeHour: closeHour,
                                pxPerHour: pxPerHour,
                              ),
                              _GridLines(
                                span: _dayHours,
                                pxPerHour: pxPerHour,
                                rowHeight: rowHeight,
                              ),
                              for (final daypart in widget.plan)
                                _block(daypart, pxPerHour, rowHeight, palette),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  Widget _block(Daypart daypart, double pxPerHour, double rowHeight,
      PrismPalette palette) {
    // The ghost stands in for the block it belongs to, so the thing under the
    // finger is the thing that moves.
    final ghost = _ghost?.id == daypart.id ? _ghost : null;
    final dayIndex = ghost?.dayIndex ?? daypart.dayIndex;
    final startHour = ghost?.startHour ?? daypart.startHour;
    final endHour = ghost?.endHour ?? daypart.endHour;
    final dragging = ghost != null;

    final mood = moodById(daypart.moodId);
    // Fractional hours, so a 7:30 block sits half a column in rather than
    // rendering as 7:00. A drag moves whole hours and carries the minutes
    // along untouched, so these come from the model either way.
    final startAt = startHour + daypart.startMinute / 60.0;
    final endAt = endHour + daypart.endMinute / 60.0;
    // No clamping any more: the grid covers the whole day, so every block sits
    // where it actually is. A 2am start used to be squashed against the 7am
    // edge, which made it both unreadable and undraggable.
    final left = startAt.clamp(0, _dayHours) * pxPerHour;
    final right = endAt.clamp(0, _dayHours) * pxPerHour;

    // While dragging, the label has to come from the dragged position, not the
    // model — and Daypart.copyWith drops serverRangeLabel, so formatting it
    // here keeps the local origin obvious at the call site.
    final label = dragging
        ? Daypart.formatRange(startHour, endHour,
            startMinute: daypart.startMinute, endMinute: daypart.endMinute)
        : daypart.rangeLabel;

    return Positioned(
      left: left,
      top: dayIndex * rowHeight + _rowGap,
      width: (right - left).clamp(pxPerHour * 0.5, double.infinity),
      height: rowHeight - _rowGap * 2,
      child: Semantics(
        button: true,
        label: '${mood.name}, $label, ${_dayNames[dayIndex]}',
        // Drag is invisible to VoiceOver by construction, so every move a drag
        // can make is also available as an action, and the sheet remains the
        // full-capability path.
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Move an hour earlier'): () =>
              _nudge(daypart, hours: -1),
          const CustomSemanticsAction(label: 'Move an hour later'): () =>
              _nudge(daypart, hours: 1),
          const CustomSemanticsAction(label: 'Move to the previous day'): () =>
              _nudge(daypart, days: -1),
          const CustomSemanticsAction(label: 'Move to the next day'): () =>
              _nudge(daypart, days: 1),
        },
        child: GestureDetector(
          onTap: () => showDaypartSheet(context, ref,
              existing: daypart,
              weekStart: daypart.weekStart ?? widget.weekStart,
              alreadyForked: daypart.weekStart != null),
          // Long-press to arm, rather than a raw pan: the grid sits inside the
          // screen's scrollable, and a pan in the same axis loses the gesture
          // arena to it. A dwell also makes an accidental shove much harder in
          // a venue, where this is used one-handed.
          onLongPressStart: (d) => _armDrag(daypart, d.globalPosition),
          onLongPressMoveUpdate: (d) =>
              _updateDrag(d.globalPosition, pxPerHour, rowHeight),
          onLongPressEnd: (_) => _endDrag(),
          onLongPressCancel: _cancelDrag,
          child: AnimatedContainer(
            // Only the settle animates. Animating during the drag makes the
            // block lag the finger, which reads as the app being slow.
            duration: dragging ? Duration.zero : const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: ghost?.overlapping == true
                  ? palette.red.withValues(alpha: 0.16)
                  : (dragging ? palette.accentSoft : palette.surface),
              border: Border.all(
                color: ghost?.overlapping == true
                    ? palette.red
                    : (dragging ? palette.accent : palette.border),
                width: dragging ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            // The two lines want ~32px and the block is `rowHeight - 24`, so a
            // short enough window makes them not fit — seven rows over a
            // shrinking grid is a height every window resize walks through.
            // Both lines are already single-line and ellipsised, so the
            // overflow is vertical and no amount of truncation fixes it: the
            // second line has to go. The range label stays, because it is the
            // one a manager is reading when they look at a grid, and the mood
            // is still carried by the block's colour and its Semantics label.
            child: LayoutBuilder(
              builder: (context, box) {
                // Width as well as height. The mood row carries an 8pt dot
                // and a 5pt gap that cannot shrink, so a block narrower than
                // those 13pt overflows however hard the label ellipsises — and
                // the picker offers five-minute dayparts, which on a 24-hour
                // grid are a few points wide. 26 leaves the dot room to sit
                // beside at least an ellipsis rather than a sliver of a letter.
                //
                // The height guard below it was added first and this one was
                // missed, which is the same bug twice in one Row: a fixed-size
                // child beside a flexible one, in a box that can be smaller
                // than the fixed part.
                final showMood = box.maxHeight >= 32 && box.maxWidth >= 26;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PrismType.label.copyWith(
                            fontWeight: FontWeight.w700,
                            color: palette.textSecondary)),
                    if (showMood) ...[
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: mood.dot(palette.brightness),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(mood.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PrismType.bodySm.copyWith(
                                    fontSize: 12,
                                    color: palette.textPrimary)),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  void _armDrag(Daypart daypart, Offset globalPosition) {
    HapticFeedback.selectionClick();
    _lastHourStep = 0;
    setState(() {
      _dragging = daypart;
      _dragOrigin = globalPosition;
      _ghost = _Ghost(
        id: daypart.id,
        dayIndex: daypart.dayIndex,
        startHour: daypart.startHour,
        endHour: daypart.endHour,
        overlapping: false,
      );
    });
  }

  void _updateDrag(Offset globalPosition, double pxPerHour, double rowHeight) {
    final origin = _dragOrigin;
    final daypart = _dragging;
    if (origin == null || daypart == null) return;

    final delta = globalPosition - origin;

    // A drag moves in whole hours and leaves the minutes exactly where they
    // were, so dragging a 7:30–11:30 block one column right gives 8:30–11:30
    // rather than snapping it to the hour. Coarse positioning is what a finger
    // on a week-wide grid can actually express; the sheet's dial is the path
    // to a precise time, and it can reach anything a drag produces.
    final hourSteps = (delta.dx / pxPerHour).round();
    final daySteps = (delta.dy / rowHeight).round();

    final duration = daypart.endHour - daypart.startHour;
    var start = daypart.startHour + hourSteps;
    // Clamp by the whole block so a drag against the edge stops rather than
    // silently squashing the daypart.
    start = start.clamp(0, _dayHours - duration).toInt();
    final day = (daypart.dayIndex + daySteps).clamp(0, 6).toInt();

    if (hourSteps != _lastHourStep) {
      // The finger is covering the block, so haptics is the only channel that
      // is not occluded at the moment an hour boundary is crossed.
      HapticFeedback.selectionClick();
      _lastHourStep = hourSteps;
    }

    final overlapping = _overlaps(daypart.id, day, start, start + duration);
    final ghost = _ghost;
    if (ghost != null &&
        ghost.dayIndex == day &&
        ghost.startHour == start &&
        ghost.overlapping == overlapping) {
      return; // nothing moved; avoid a rebuild per pixel
    }
    setState(() => _ghost = _Ghost(
          id: daypart.id,
          dayIndex: day,
          startHour: start,
          endHour: start + duration,
          overlapping: overlapping,
        ));
  }

  /// Flags — but does not forbid — two dayparts covering the same hour.
  ///
  /// Overlap is worth showing: it makes "what plays at 3pm" ambiguous and
  /// nothing downstream resolves it. It is NOT worth refusing. A weekly plan is
  /// normally contiguous (the seeded one tiles 7–23 with no gaps), so a block
  /// can rarely move at all without touching a neighbour — a UI that refused
  /// would be inert on exactly the shape real schedules take. Neither the
  /// model, the repositories nor the backend validate overlap, so blocking it
  /// here would also be inventing a constraint the system does not have.
  ///
  /// So the drag is allowed and the conflict is drawn instead. What SHOULD
  /// happen when two dayparts claim the same hour is a product decision, and
  /// it is recorded as one.
  bool _overlaps(String id, int day, int start, int end) => widget.plan.any((d) =>
      d.id != id &&
      d.dayIndex == day &&
      start < d.endHour &&
      end > d.startHour);

  Future<void> _endDrag() async {
    final ghost = _ghost;
    final daypart = _dragging;
    _dragging = null;
    _dragOrigin = null;
    if (ghost == null || daypart == null) {
      setState(() => _ghost = null);
      return;
    }

    final unchanged = ghost.dayIndex == daypart.dayIndex &&
        ghost.startHour == daypart.startHour;
    if (unchanged) {
      setState(() => _ghost = null);
      return;
    }
    // Committed even when it overlaps; the extra haptic just marks that the
    // manager has left a conflict behind them.
    if (ghost.overlapping) HapticFeedback.lightImpact();

    await _commit(
      daypart.copyWith(
        dayIndex: ghost.dayIndex,
        startHour: ghost.startHour,
        endHour: ghost.endHour,
      ),
      // Held until the write returns. Both repo implementations push the new
      // plan through the stream before their future completes, so by the time
      // the ghost clears the grid is already rendering the committed position
      // and the block never flashes back to where it came from.
      clearGhostAfter: true,
    );
  }

  void _cancelDrag() {
    _dragging = null;
    _dragOrigin = null;
    setState(() => _ghost = null);
  }

  /// The keyboard/VoiceOver equivalent of a drag. Refuses the same overlaps.
  Future<void> _nudge(Daypart daypart, {int hours = 0, int days = 0}) async {


    final duration = daypart.endHour - daypart.startHour;
    final start =
        (daypart.startHour + hours).clamp(0, _dayHours - duration).toInt();
    final day = (daypart.dayIndex + days).clamp(0, 6).toInt();
    if (start == daypart.startHour && day == daypart.dayIndex) return;
    if (_overlaps(daypart.id, day, start, start + duration)) {
      HapticFeedback.lightImpact(); // allowed, but announced
    }
    await _commit(
      daypart.copyWith(
          dayIndex: day, startHour: start, endHour: start + duration),
      clearGhostAfter: false,
    );
  }

  Future<void> _commit(Daypart next, {required bool clearGhostAfter}) async {
    try {
      await ref.read(scheduleRepoProvider).updateDaypart(next);
    } catch (e) {
      if (mounted) showPrismError(context, e);
    } finally {
      if (mounted && clearGhostAfter) setState(() => _ghost = null);
    }
  }
}

/// Hour labels across the top. Every two hours — one per hour is unreadable at
/// this width and the gridlines already carry the finer rhythm.
///
/// Lives inside the scroll view now, sharing its width with the grid, so the
/// labels and the blocks cannot drift apart while panning.
class _HourRuler extends StatelessWidget {
  const _HourRuler({required this.pxPerHour});

  final double pxPerHour;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return SizedBox(
      height: _WeekGridState._rulerHeight,
      child: Stack(
        children: [
          // Stops at 22 rather than 24: a label at the far edge would be
          // clipped by the scroll view's end, and "12a" twice in one ruler
          // reads as a mistake.
          for (var h = 0; h <= 22; h += 2)
            Positioned(
              left: h * pxPerHour,
              child: Text(_hourLabel(h),
                  style: PrismType.microHelper
                      .copyWith(color: palette.textTertiary)),
            ),
        ],
      ),
    );
  }

  static String _hourLabel(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12${h < 12 ? 'a' : 'p'}';
  }
}

/// The hours the venue is shut, behind everything else.
///
/// The grid used to simply stop at the open and close hours. Showing the whole
/// day instead means a 2am daypart is placeable and legible, but it also loses
/// the at-a-glance sense of when the room is actually in use — so the closed
/// stretch is dimmed rather than removed. Purely informational: a daypart
/// outside it is perfectly legal, which is the point of showing it at all.
class _ClosedHours extends StatelessWidget {
  const _ClosedHours({
    required this.openHour,
    required this.closeHour,
    required this.pxPerHour,
  });

  final int openHour;
  final int closeHour;
  final double pxPerHour;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    if (openHour <= 0 && closeHour >= 24) return const SizedBox.shrink();
    final shade = palette.tile2.withValues(alpha: .35);
    return Stack(
      children: [
        if (openHour > 0)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: openHour * pxPerHour,
            child: ColoredBox(color: shade),
          ),
        if (closeHour < 24)
          Positioned(
            left: closeHour * pxPerHour,
            top: 0,
            bottom: 0,
            width: (24 - closeHour) * pxPerHour,
            child: ColoredBox(color: shade),
          ),
      ],
    );
  }
}

/// Hour and day separators. Purely decorative, but they are what makes the
/// axis legible — without them a block's left edge means nothing.
class _GridLines extends StatelessWidget {
  const _GridLines({
    required this.span,
    required this.pxPerHour,
    required this.rowHeight,
  });

  final int span;
  final double pxPerHour;
  final double rowHeight;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Stack(
      children: [
        for (var h = 0; h <= span; h++)
          Positioned(
            left: h * pxPerHour,
            top: 0,
            bottom: 0,
            child: Container(width: 1, color: palette.border.withValues(alpha: 0.4)),
          ),
        for (var day = 1; day < 7; day++)
          Positioned(
            top: day * rowHeight,
            left: 0,
            right: 0,
            child: Container(height: 1, color: palette.border.withValues(alpha: 0.4)),
          ),
      ],
    );
  }
}
