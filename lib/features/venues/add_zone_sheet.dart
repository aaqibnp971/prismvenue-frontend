import 'package:flutter/material.dart';

import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/prism_field.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// S04-4 "Add a zone — name it, pick its player & hours". BottomSheet with
/// the **zone name field only** ("Back patio", accent border) + helper
/// "A zone is one area with its own speakers. Prism drives each zone on its
/// own." Cancel / "Add zone" (flex 1:2). Resolves with the zone name.
Future<String?> showAddZoneSheet(BuildContext context) {
  return showPrismSheet<String>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: const _AddZoneSheet(),
  );
}

class _AddZoneSheet extends StatefulWidget {
  const _AddZoneSheet();

  @override
  State<_AddZoneSheet> createState() => _AddZoneSheetState();
}

class _AddZoneSheetState extends State<_AddZoneSheet> {
  // The frame shows this field filled with "Back patio" to illustrate a filled
  // state. Seeded as a real default it meant "+ Add zone" → "Add zone" created
  // a zone actually called Back patio — the same class of defect as the reset
  // screen shipping with a real person's address in it. Hint, not value.
  final _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return PrismBottomSheet(
      title: 'Add a zone',
      primaryLabel: 'Add zone',
      // Empty returns null rather than creating an unnamed zone. The caller
      // already ignores null, so this reads as "nothing to add" rather than
      // failing somewhere later.
      onPrimary: () => Navigator.of(context)
          .pop(_name.text.trim().isEmpty ? null : _name.text),
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 16),
        PrismField(
            label: 'Zone name',
            controller: _name,
            hint: 'Back patio',
            focusedOverride: true),
        const SizedBox(height: 9),
        Text(
          'A zone is one area with its own speakers. Prism drives each zone '
          'on its own.',
          style:
              PrismType.microHelper.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}
