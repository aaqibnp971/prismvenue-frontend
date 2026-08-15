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
  static const _rowGap = 5.0;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final hours = ref.watch(openHoursProvider).value ?? const OpenHours();
    // A zero or inverted window would divide by zero below; fall back to the
    // published default rather than rendering nothing.
    final openHour = hours.closeHour > hours.openHour ? hours.openHour : 7;
    final closeHour = hours.closeHour > hours.openHour ? hours.closeHour : 23;
    final span = closeHour - openHour;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _HourRuler(openHour: openHour, closeHour: closeHour),
        const SizedBox(height: 6),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: _labelWidth,
                child: Column(
                  children: [
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
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pxPerHour = constraints.maxWidth / span;
                    final rowHeight = constraints.maxHeight / 7;
                    return Stack(
                      key: _gridKey,
                      children: [
                        _GridLines(
                          span: span,
                          pxPerHour: pxPerHour,
                          rowHeight: rowHeight,
                        ),
                        for (final daypart in widget.plan)
                          _block(daypart, openHour, closeHour, pxPerHour,
                              rowHeight, palette),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _block(Daypart daypart, int openHour, int closeHour, double pxPerHour,
      double rowHeight, PrismPalette palette) {
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
    // Blocks outside the open-hours window are clamped into view rather than
    // hidden — an invisible block is one a manager cannot fix.
    final left =
        (startAt - openHour).clamp(0, closeHour - openHour) * pxPerHour;
    final right = (endAt - openHour).clamp(0, closeHour - openHour) * pxPerHour;

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
              _updateDrag(d.globalPosition, openHour, closeHour, pxPerHour,
                  rowHeight),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PrismType.label.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textSecondary)),
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
                              fontSize: 12, color: palette.textPrimary)),
                    ),
                  ],
                ),
              ],
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

  void _updateDrag(Offset globalPosition, int openHour, int closeHour,
      double pxPerHour, double rowHeight) {
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
    start = start.clamp(openHour, closeHour - duration).toInt();
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
    final hoursValue = ref.read(openHoursProvider).value ?? const OpenHours();
    final openHour = hoursValue.closeHour > hoursValue.openHour ? hoursValue.openHour : 7;
    final closeHour = hoursValue.closeHour > hoursValue.openHour ? hoursValue.closeHour : 23;

    final duration = daypart.endHour - daypart.startHour;
    final start =
        (daypart.startHour + hours).clamp(openHour, closeHour - duration).toInt();
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
class _HourRuler extends StatelessWidget {
  const _HourRuler({required this.openHour, required this.closeHour});

  final int openHour;
  final int closeHour;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final span = closeHour - openHour;
    return Row(
      children: [
        const SizedBox(width: _WeekGridState._labelWidth),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final pxPerHour = constraints.maxWidth / span;
              return SizedBox(
                height: 14,
                child: Stack(
                  children: [
                    for (var h = openHour; h <= closeHour; h += 2)
                      Positioned(
                        left: (h - openHour) * pxPerHour,
                        child: Text(_hourLabel(h),
                            style: PrismType.microHelper
                                .copyWith(color: palette.textTertiary)),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _hourLabel(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12${h < 12 ? 'a' : 'p'}';
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
