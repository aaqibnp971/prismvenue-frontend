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
    await hours.setEverydayHours(openHour: result.$1, closeHour: result.$2);
  }
}

Future<(int, int)> hoursOf(WidgetRef ref) async {
  final h = await ref.read(settingsRepoProvider).watchOpenHours().first;
  return (h.openHour, h.closeHour);
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
  late int _open = widget.initialOpen;
  late int _close = widget.initialClose;

  int get _openDuration => (_close - _open) % 24;

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
                minutes: _open * 60,
                big: true,
                dialTitle: 'Opening time',
                // The dial reports minutes; with the default 60-minute step
                // that is always a whole hour, and `open_hour`/`close_hour`
                // are what the wire carries.
                onChanged: (m) => setState(() => _open = m ~/ 60),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TimeField(
                label: 'Closes',
                minutes: _close * 60,
                big: true,
                dialTitle: 'Closing time',
                // The dial reports minutes; with the default 60-minute step
                // that is always a whole hour, and `open_hour`/`close_hour`
                // are what the wire carries.
                onChanged: (m) => setState(() => _close = m ~/ 60),
              ),
            ),
          ],
        ),
        const SizedBox(height: 9),
        // Helper copy is elided in the README ("…open 16 hours.").
        Text('Open $_openDuration hours.',
            style:
                PrismType.microHelper.copyWith(color: palette.textSecondary)),
      ],
    );
  }
}
