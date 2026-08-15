import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/prism_top_bar.dart';
import '../../../shared/widgets/prism_bottom_sheet.dart';
import '../../../shared/widgets/time_dial_sheet.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// Labelled tappable time field — S05-10 "Opens 7:00 am (borderStrong +
/// accent clock icon)"; S05-11 uses the same fields with 16/800 values.
/// Tap opens the S05-12 time dial and resolves the picked time.
///
/// Works in minutes past midnight throughout, and passes [minuteStep] to the
/// dial. Leaving the step at 60 gives back exactly the hour-only field the
/// open-hours screens have always had — their wire fields are
/// `open_hour`/`close_hour` smallints, so a minute picked here would be a
/// minute the server drops. Dayparts pass a finer step; see [TimeDialSheet].
class TimeField extends StatelessWidget {
  const TimeField({
    super.key,
    required this.label,
    required this.minutes,
    required this.dialTitle,
    required this.onChanged,
    this.minuteStep = 60,
    this.big = false,
  });

  final String label;

  /// Minutes past midnight, 0–1439.
  final int minutes;

  /// "Opening time" / "Closing time" (S05-12 header).
  final String dialTitle;

  /// Reports minutes past midnight. With [minuteStep] at 60 this is always a
  /// whole hour, so an hour-only caller can divide it out exactly.
  final ValueChanged<int> onChanged;

  /// Passed straight through to the dial's minute wheel; 60 hides it.
  final int minuteStep;

  /// S05-11 variant: value 16/800.
  final bool big;

  /// "7:00 am" / "7:30 am". Minutes are always shown — a field that hid them
  /// would read as a whole hour while storing something else.
  static String timeLabel(int minutesOfDay) {
    final h = (minutesOfDay ~/ 60) % 24;
    final m = minutesOfDay % 60;
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12:${m.toString().padLeft(2, '0')} ${h < 12 ? 'am' : 'pm'}';
  }

  /// Convenience for the hour-only callers, which hold an hour rather than a
  /// minute count.
  static String hourLabel(int h) => timeLabel(h * 60);

  Future<void> _openDial(BuildContext context) async {
    final picked = await showPrismSheet<int>(
      context,
      topBarHeight: PrismTopBar.height,
      sheet: Builder(
        builder: (sheetContext) => TimeDialSheet(
          title: dialTitle,
          initialMinutes: minutes,
          minuteStep: minuteStep,
          onSet: (m) => Navigator.of(sheetContext).pop(m),
          onCancel: () => Navigator.of(sheetContext).pop(),
        ),
      ),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: PrismType.label.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 7),
        GestureDetector(
          onTap: () => _openDial(context),
          child: Container(
            padding: EdgeInsets.symmetric(
                vertical: big ? 12 : 10, horizontal: 13),
            decoration: BoxDecoration(
              color: palette.tile,
              border: Border.all(color: palette.borderStrong),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(LucideIcons.clock, size: 15, color: palette.accent),
                const SizedBox(width: 9),
                Text(
                  timeLabel(minutes),
                  style: big
                      ? PrismType.body.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: palette.textPrimary)
                      : PrismType.bodySm
                          .copyWith(fontSize: 13, color: palette.textPrimary),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
