import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';

/// Confirms removing a zone (S05-5).
///
/// The app already puts a modal in front of *changing the music* — S01-3, on
/// the grounds that a mis-tap in a busy venue is expensive. Removing a zone took
/// its schedule, its guardrails and its playback state with it on a single
/// undoable tap, with no dialog and no undo. That asymmetry was the defect: the
/// cheaper action was guarded and the destructive one was not.
///
/// The name is echoed back rather than described generically, because on the
/// zone-detail screen every row looks alike and "this zone" is not enough to
/// catch the case where you opened the wrong one.
Future<bool?> showConfirmRemoveZoneDialog(
  BuildContext context, {
  required String zoneName,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Icon(LucideIcons.trash2, size: 20, color: palette.red),
        title: 'Remove this zone?',
        body: TextSpan(
          text: 'Removing ',
          children: [
            TextSpan(
              text: zoneName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const TextSpan(
              text: ' takes its schedule, guardrails and playback settings '
                  'with it. Its speakers stop following Prism.',
            ),
          ],
        ),
        confirmLabel: 'Remove zone',
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    ),
  );
}
