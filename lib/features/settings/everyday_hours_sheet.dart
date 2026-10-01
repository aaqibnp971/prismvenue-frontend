import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/settings_repo.dart';
import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'widgets/time_field.dart';

/// S05-11 "Everyday hours — set the default open & close time". Sub "The
/// default for Mon–Sun. Add exceptions for days that differ."; Opens /
/// Closes fields (16/800) → S05-12 dial; "…open 16 hours." helper;
/// Cancel / "Save hours".
Future<void> showEverydayHoursSheet(BuildContext context, WidgetRef ref) async {
  final hours = ref.read(settingsRepoProvider);
  final current = await hoursOf(ref);
  if (!context.mounted) return;
  final result = await showPrismSheet<(int, int)>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: _EverydayHoursSheet(
        initialOpen: current.$1, initialClose: current.$2),
  );
  if (result != null) {
    // Minutes past midnight in, hour + minute out — finding #18.
    await hours.setEverydayHours(
      openHour: result.$1 ~/ 60,
      openMinute: result.$1 % 60,
      closeHour: result.$2 ~/ 60,
      closeMinute: result.$2 % 60,
    );
  }
}

/// Opening and closing time, each as minutes past midnight.
Future<(int, int)> hoursOf(WidgetRef ref) async {
  final h = await ref.read(settingsRepoProvider).watchOpenHours().first;
  return (h.openMinutes, h.closeMinutes);
}

class _EverydayHoursSheet extends StatefulWidget {
  const _EverydayHoursSheet(
      {required this.initialOpen, required this.initialClose});

  final int initialOpen;
  final int initialClose;

  @override
  State<_EverydayHoursSheet> createState() => _EverydayHoursSheetState();
}

class _EverydayHoursSheetState extends State<_EverydayHoursSheet> {
  /// The same step a daypart uses. Five minutes is finer than any venue has
  /// ever asked for and coarse enough that the wheel is still a flick.
  static const _minuteStep = 5;

  /// Minutes past midnight, both of them.
  late int _open = widget.initialOpen;
  late int _close = widget.initialClose;

  /// Finding #18: minutes exist now, so the helper line has to survive a span
  /// that is not a whole number of hours. "16 hours" stays "16 hours";
  /// 10:30–19:45 reads "9 hours 15 minutes" rather than rounding to a number
  /// that contradicts the two fields above it.
  String get _openDuration {
    final span = (_close - _open) % (24 * 60);
    final h = span ~/ 60;
    final m = span % 60;
    final hours = h == 1 ? '1 hour' : '$h hours';
    if (m == 0) return hours;
    return '$hours ${m == 1 ? '1 minute' : '$m minutes'}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return PrismBottomSheet(
      title: 'Everyday hours',
      sub: 'The default for Mon–Sun. Add exceptions for days that differ.',
      primaryLabel: 'Save hours',
      onPrimary: () => Navigator.of(context).pop((_open, _close)),
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: TimeField(
                label: 'Opens',
                minutes: _open,
                big: true,
                dialTitle: 'Opening time',
                minuteStep: _minuteStep,
                onChanged: (m) => setState(() => _open = m),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TimeField(
                label: 'Closes',
                minutes: _close,
                big: true,
                dialTitle: 'Closing time',
                minuteStep: _minuteStep,
                onChanged: (m) => setState(() => _close = m),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        // Helper copy is elided in the README ("…open 16 hours.").
        Text('Open $_openDuration.',
            style:
                PrismType.microHelper.copyWith(color: palette.textSecondary)),
      ],
    );
  }
}
