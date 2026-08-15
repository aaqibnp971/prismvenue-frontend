import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'prism_bottom_sheet.dart';
import 'seg_toggle.dart';

/// Time dial — §2 S05-12: header title + AM/PM seg (pill, item padding 6×14);
/// readout 58/800 + meridiem 22/700 `textSecondary`; slider track h6 r999
/// `tile2` with accent fill (hour/24 — 7:00 → 29%) and a 26 white thumb with
/// a 4px accent ring + shadow; tick labels 12 am · 6 am · Noon · 6 pm ·
/// 12 am (10.5/600 `textTertiary`); quick chips 7:00–10:00 (gap 7,
/// padding-v 9, r9; selected: `accentSoft` bg, accent border, `accentText`);
/// Cancel / "Set 7:00 AM".
///
/// ## Two granularities, one widget
///
/// [minuteStep] decides whether minutes exist at all:
///
/// * **60** (the default) is the frames exactly as drawn — the slider is the
///   whole control, the readout always ends in `:00`, and no minute wheel is
///   built. Open hours and open-hours exceptions use this, and must: the
///   contract stores them as `open_hour`/`close_hour` smallints, so a minute a
///   manager could pick here is one the server would silently drop.
/// * **Anything smaller** adds the minute wheel below the chips. Dayparts use
///   it, because `dayparts.start_local` is a Postgres `time` and always was —
///   it was the *write* path that floored everything to the hour.
///
/// The slider stays the hour control in both modes. A finger dragging across
/// a 24-hour track cannot reliably express five minutes (a step would be a few
/// pixels wide), so precision lives in the wheel where it can be hit exactly,
/// and the slider keeps doing the thing it is good at.
class TimeDialSheet extends StatefulWidget {
  const TimeDialSheet({
    super.key,
    required this.title,
    required this.initialMinutes,
    this.minuteStep = 60,
    this.onSet,
    this.onCancel,
  });

  /// e.g. "Opening time".
  final String title;

  /// Minutes past midnight, 0–1439.
  final int initialMinutes;

  /// Granularity of the minute wheel. 60 hides it entirely.
  final int minuteStep;

  /// Reports minutes past midnight.
  final ValueChanged<int>? onSet;
  final VoidCallback? onCancel;

  @override
  State<TimeDialSheet> createState() => _TimeDialSheetState();
}

class _TimeDialSheetState extends State<TimeDialSheet> {
  late int _hour = (widget.initialMinutes ~/ 60).clamp(0, 23);
  late int _minute = _snap(widget.initialMinutes % 60);

  late final FixedExtentScrollController _wheel =
      FixedExtentScrollController(initialItem: _minute ~/ _step);

  int get _step => widget.minuteStep.clamp(1, 60);
  bool get _hasMinutes => _step < 60;

  /// Rounds onto the wheel's grid, so a value stored at a finer granularity —
  /// by an earlier build, or by another client — still selects a real item
  /// instead of leaving the wheel pointing at nothing.
  int _snap(int minute) => ((minute / _step).round() * _step).clamp(0, 59);

  List<int> get _minuteValues =>
      [for (var m = 0; m < 60; m += _step) m];

  bool get _pm => _hour >= 12;
  int get _display12 => _hour % 12 == 0 ? 12 : _hour % 12;
  String get _mm => _minute.toString().padLeft(2, '0');
  String get _label => '$_display12:$_mm ${_pm ? 'PM' : 'AM'}';

  @override
  void dispose() {
    _wheel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;

    return PrismBottomSheet(
      title: widget.title,
      headerTrailing: SegToggle(
        options: const ['AM', 'PM'],
        selected: _pm ? 1 : 0,
        pill: true,
        itemPadding: const EdgeInsets.symmetric(vertical: 6, horizontal: 14),
        onChanged: (i) => setState(() {
          if (i == 0 && _pm) _hour -= 12;
          if (i == 1 && !_pm) _hour += 12;
        }),
      ),
      primaryLabel: 'Set $_label',
      onPrimary: widget.onSet == null
          ? null
          : () => widget.onSet!(_hour * 60 + _minute),
      onCancel: widget.onCancel,
      children: [
        const SizedBox(height: 18),
        // Readout: "7:00" 58/800 + "AM" 22/700 textSecondary.
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('$_display12:$_mm',
                  style: PrismType.numeralDial
                      .copyWith(color: palette.textPrimary)),
              const SizedBox(width: 8),
              Text(_pm ? 'PM' : 'AM',
                  style: PrismType.body.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: palette.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 18),
        _DialSlider(
          hour: _hour,
          onChanged: (h) => setState(() => _hour = h),
        ),
        const SizedBox(height: 6),
        // Tick labels under the track.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final t in const ['12 am', '6 am', 'Noon', '6 pm', '12 am'])
              Text(t,
                  style: PrismType.microHelper
                      .copyWith(color: palette.textTertiary)),
          ],
        ),
        const SizedBox(height: 16),
        // Quick chips. They set the hour and leave the minutes alone, so
        // picking :30 and then tapping "9:00" gives 9:30 rather than throwing
        // the minute away.
        Row(
          children: [
            for (final (i, h) in const [7, 8, 9, 10].indexed) ...[
              if (i > 0) const SizedBox(width: 7),
              Expanded(child: _quickChip(palette, h)),
            ],
          ],
        ),
        if (_hasMinutes) ...[
          const SizedBox(height: 16),
          _MinuteWheel(
            controller: _wheel,
            values: _minuteValues,
            selected: _minute,
            onChanged: (m) => setState(() => _minute = m),
          ),
        ],
      ],
    );
  }

  Widget _quickChip(PrismPalette palette, int h12) {
    // Chips apply within the current meridiem.
    final target = _pm ? h12 + 12 : h12;
    final on = _hour == target;
    return GestureDetector(
      onTap: () => setState(() => _hour = target),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? palette.accentSoft : palette.tile,
          border: Border.all(color: on ? palette.accent : palette.border),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text('$h12:$_mm',
            style: PrismType.button.copyWith(
                fontSize: 12,
                color: on ? palette.accentText : palette.textSecondary)),
      ),
    );
  }
}

/// The minute scroller — a horizontal wheel of `:00 :05 :10 …`.
///
/// Horizontal rather than vertical because this sheet is wide and short on the
/// iPad landscape it is designed for: a vertical wheel would either crowd the
/// slider or push the Set button off the bottom, while a horizontal one sits in
/// the same band the chips already occupy.
///
/// [ListWheelScrollView] is rotated a quarter turn to get that, with each item
/// rotated back so the numerals stay upright. The rotation is why the children
/// are built by a delegate rather than laid out directly — the wheel measures
/// its items along its own axis, which after rotation is the screen's
/// horizontal one.
class _MinuteWheel extends StatelessWidget {
  const _MinuteWheel({
    required this.controller,
    required this.values,
    required this.selected,
    required this.onChanged,
  });

  final FixedExtentScrollController controller;
  final List<int> values;
  final int selected;
  final ValueChanged<int> onChanged;

  static const _itemExtent = 76.0;
  static const _height = 54.0;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Minutes',
            style: PrismType.microHelper.copyWith(color: palette.textTertiary)),
        const SizedBox(height: 6),
        SizedBox(
          height: _height,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // The selection window, so it is obvious which numeral is live
              // even mid-flick.
              Center(
                child: Container(
                  width: _itemExtent,
                  height: _height,
                  decoration: BoxDecoration(
                    color: palette.accentSoft,
                    border: Border.all(color: palette.accent),
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
              ),
              RotatedBox(
                quarterTurns: -1,
                child: ListWheelScrollView.useDelegate(
                  controller: controller,
                  itemExtent: _itemExtent,
                  // A wheel's perspective foreshortening reads as a smooth
                  // fade at the edges here rather than as a drum, which is the
                  // point: it says "there is more either way" without pretending
                  // to be a physical dial.
                  diameterRatio: 2.2,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: (i) => onChanged(values[i]),
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: values.length,
                    builder: (context, i) {
                      final value = values[i];
                      final on = value == selected;
                      return RotatedBox(
                        quarterTurns: 1,
                        child: Center(
                          child: Text(
                            ':${value.toString().padLeft(2, '0')}',
                            style: PrismType.button.copyWith(
                              fontSize: on ? 20 : 17,
                              color: on
                                  ? palette.accentText
                                  : palette.textSecondary,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Track h6 r999 `tile2`, accent fill = hour/24, thumb 26 white with 4px
/// accent ring + shadow. Drag snaps to whole hours; see the class doc on
/// [TimeDialSheet] for why the minutes are not on this track.
class _DialSlider extends StatelessWidget {
  const _DialSlider({required this.hour, required this.onChanged});

  final int hour;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final fraction = hour / 24;

        void handle(Offset local) {
          final h = (local.dx / w * 24).round().clamp(0, 23);
          if (h != hour) onChanged(h);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => handle(d.localPosition),
          onHorizontalDragUpdate: (d) => handle(d.localPosition),
          child: SizedBox(
            height: 26,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: palette.tile2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Container(
                  height: 6,
                  width: w * fraction,
                  decoration: BoxDecoration(
                    color: palette.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Positioned(
                  left: (w * fraction - 13).clamp(0, w - 26),
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFFFF),
                      shape: BoxShape.circle,
                      border: Border.all(color: palette.accent, width: 4),
                      boxShadow: const [
                        BoxShadow(
                          offset: Offset(0, 2),
                          blurRadius: 6,
                          color: Color.fromRGBO(0, 0, 0, .3),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
