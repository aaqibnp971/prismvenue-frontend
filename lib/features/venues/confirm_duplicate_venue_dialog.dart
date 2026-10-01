import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';

/// "You already have a venue called X" — finding #20.
///
/// Deliberately a question, not a rule. Two venues called "Test Clinic" were
/// indistinguishable in the portfolio, which is the defect; but a chain really
/// can have two branches with one name, and refusing outright would make the
/// app wrong for them. So the server refuses once with `venue_name_taken` and
/// the owner's "yes" comes back as `allow_duplicate_name`.
///
/// The same shape as a daypart overwrite (`DaypartWriteRequest.replace`): the
/// client is saying "the person was shown what this collides with and agreed".
Future<bool?> showConfirmDuplicateVenueDialog(
  BuildContext context, {
  required String venueName,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Icon(LucideIcons.circleAlert, size: 20, color: palette.amber),
        title: 'That name is already used',
        body: TextSpan(
          text: 'You already have a venue called ',
          children: [
            TextSpan(
              text: venueName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const TextSpan(
              text: '. Two with the same name are hard to tell apart in the '
                  'portfolio — add a branch or street to one of them if you '
                  'can.',
            ),
          ],
        ),
        confirmLabel: 'Add it anyway',
        cancelLabel: 'Change the name',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ),
  );
}
