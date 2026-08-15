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

  // The typed mirror of [_hour] and [_minute]. Held in controllers rather than
  // rebuilt from state on every frame, because rebuilding a TextField's text
  // while it has focus fights the caret.
  late final TextEditingController _hourField =
      TextEditingController(text: '$_display12');
  late final TextEditingController _minuteField =
      TextEditingController(text: _mm);
  final _hourFocus = FocusNode();
  final _minuteFocus = FocusNode();

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
  void initState() {
    super.initState();
    // Commit on blur as well as on submit. Typing 9 and tapping Set without
    // leaving the field would otherwise save the old hour, which is the
    // silent-wrong-value failure this sheet exists to avoid.
    _hourFocus.addListener(() {
      if (!_hourFocus.hasFocus) _commitHour();
    });
    _minuteFocus.addListener(() {
      if (!_minuteFocus.hasFocus) _commitMinute();
    });
  }

  @override
  void dispose() {
    _wheel.dispose();
    _hourField.dispose();
    _minuteField.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  /// Pushes state back into the fields after the slider, wheel or a chip moves.
  void _syncFields() {
    _hourField.text = '$_display12';
    _minuteField.text = _mm;
  }

  /// 12-hour, because that is what the field shows and what the AM/PM toggle
  /// beside it means. Out-of-range or unparseable input reverts rather than
  /// being coerced: silently turning 47 into 4 or 11 is a worse answer than
  /// leaving the time alone and letting someone look at it.
  void _commitHour() {
    final typed = int.tryParse(_hourField.text.trim());
    if (typed != null && typed >= 1 && typed <= 12) {
      final base = typed % 12;
      setState(() => _hour = _pm ? base + 12 : base);
    }
    _syncFields();
  }

  /// Snapped onto the wheel's grid so the two controls cannot disagree — with
  /// a 5-minute step, typing :07 gives :05 and the wheel moves there.
  void _commitMinute() {
    final typed = int.tryParse(_minuteField.text.trim());
    if (typed != null && typed >= 0 && typed <= 59) {
      final snapped = _snap(typed);
      setState(() => _minute = snapped);
      if (_hasMinutes && _wheel.hasClients) {
        _wheel.jumpToItem(snapped ~/ _step);
      }
    }
    _syncFields();
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
        onChanged: (i) {
          setState(() {
            if (i == 0 && _pm) _hour -= 12;
            if (i == 1 && !_pm) _hour += 12;
          });
          // The field shows a 12-hour number, so flipping the meridiem does
          // not change the digits — but _commitHour reads the toggle, and a
          // stale field would fight the next edit.
          _syncFields();
        },
      ),
      primaryLabel: 'Set $_label',
      onPrimary: widget.onSet == null
          ? null
          : () => widget.onSet!(_hour * 60 + _minute),
      onCancel: widget.onCancel,
      children: [
        const SizedBox(height: 18),
        // Readout: "7:00" 58/800 + "AM" 22/700 textSecondary — and typable.
        //
        // The dial is quick for "somewhere around 8" and slow for "23:05
        // exactly", which is the case that actually turns up: a manager
        // copying a time off a rota does not want to hunt for it on a track.
        // The numerals were already the biggest thing on the sheet, so they
        // become the field rather than growing a second one beside it.
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              _NumeralField(
                controller: _hourField,
                focusNode: _hourFocus,
                width: 96,
                align: TextAlign.right,
                semanticLabel: 'Hour',
                onSubmitted: _commitHour,
                onEditingComplete: _commitHour,
              ),
              Text(':',
                  style: PrismType.numeralDial
                      .copyWith(color: palette.textPrimary)),
              _NumeralField(
                controller: _minuteField,
                focusNode: _minuteFocus,
                width: 96,
                align: TextAlign.left,
                semanticLabel: 'Minutes',
                onSubmitted: _commitMinute,
                onEditingComplete: _commitMinute,
              ),
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
          onChanged: (h) {
            setState(() => _hour = h);
            _syncFields();
          },
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
            onChanged: (m) {
              setState(() => _minute = m);
              _syncFields();
            },
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
      onTap: () {
        setState(() => _hour = target);
        _syncFields();
      },
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

/// One half of the big readout, as an editable field.
///
/// Styled to be indistinguishable from the numerals it replaces: no border, no
/// fill, no underline. It is the display until you tap it, which is the point —
/// growing a second, smaller "or type it here" input beside a 58pt readout
/// would have said the big number was not the real one.
class _NumeralField extends StatelessWidget {
  const _NumeralField({
    required this.controller,
    required this.focusNode,
    required this.width,
    required this.align,
    required this.semanticLabel,
    required this.onSubmitted,
    required this.onEditingComplete,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Fixed, so the colon between the two halves does not slide about as the
  /// digits change.
  final double width;
  final TextAlign align;
  final String semanticLabel;
  final VoidCallback onSubmitted;
  final VoidCallback onEditingComplete;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: align,
        keyboardType: TextInputType.number,
        // Selects the whole value on focus, so typing replaces rather than
        // appending to it — "9" after tapping 11 should be 9, not 119.
        onTap: () => controller.selection = TextSelection(
            baseOffset: 0, extentOffset: controller.text.length),
        onSubmitted: (_) => onSubmitted(),
        onEditingComplete: onEditingComplete,
        style: PrismType.numeralDial.copyWith(color: palette.textPrimary),
        cursorColor: palette.accent,
        decoration: InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.zero,
          border: InputBorder.none,
          focusedBorder: InputBorder.none,
          enabledBorder: InputBorder.none,
          labelText: null,
          hintText: null,
          counterText: '',
        ),
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
