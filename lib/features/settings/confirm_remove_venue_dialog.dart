import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';

/// "Remove this venue?" — finding #8.
///
/// Modelled on the remove-zone dialog, and deliberately says what survives.
/// "Remove" reads as "destroy", and this is an archive: every read path
/// filters `archived_at is null`, so the venue disappears while its schedules,
/// takeover history and idempotency records — somebody's audit trail — stay
/// exactly where they are. An owner about to press it deserves to know that.
Future<bool?> showConfirmRemoveVenueDialog(
  BuildContext context, {
  required String venueName,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Icon(LucideIcons.trash2, size: 20, color: palette.red),
        title: 'Remove this venue?',
        body: TextSpan(
          text: 'Removing ',
          children: [
            TextSpan(
              text: venueName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const TextSpan(
              text: ' takes it out of your portfolio along with its rooms. '
                  'Its schedules and history are kept, so support can put it '
                  'back.',
            ),
          ],
        ),
        confirmLabel: 'Remove venue',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ),
  );
}
