import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';

/// Confirms deleting a daypart (S03-5).
///
/// Same asymmetry H-04 fixed on "Remove zone": the app puts a modal in front of
/// *changing the music for the next few hours*, and deleted a block of the
/// week's plan on one undoable tap. A daypart is not recoverable from the UI —
/// there is no undo and no history — so the tap deserves the same gate the
/// cheaper action already had.
///
/// The block is named back rather than described generically, because the sheet
/// is opened by tapping a block in a grid and picking the wrong one is exactly
/// the mistake this catches.
Future<bool?> showConfirmDeleteDaypartDialog(
  BuildContext context, {
  required String rangeLabel,
  required String moodName,
  required String dayName,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Icon(LucideIcons.trash2, size: 20, color: palette.red),
        title: 'Delete this daypart?',
        body: TextSpan(
          text: '',
          children: [
            TextSpan(
              text: '$dayName · $rangeLabel · $moodName',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const TextSpan(
              text: ' comes out of the plan. Whatever runs either side of it '
                  'will cover the gap.',
            ),
          ],
        ),
        confirmLabel: 'Delete daypart',
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    ),
  );
}
