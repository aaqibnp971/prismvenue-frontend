import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';

/// "Apply these settings to every room?" — finding #10.
///
/// Asked, and the count named, because this is the one control on the page
/// that changes rooms the person is not looking at. Everything else here
/// affects the zone whose name is at the top; this reaches across the venue,
/// and a manager who meant "this room" would hear the difference.
Future<bool?> showConfirmApplyToAllDialog(
  BuildContext context, {
  required int zoneCount,
  required String venueName,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Icon(LucideIcons.copy, size: 20, color: palette.accent),
        title: 'Apply to every room?',
        body: TextSpan(
          text: 'This room’s volume band, transitions and takeover '
              'access will be copied to all ',
          children: [
            TextSpan(
              text: '$zoneCount rooms',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            TextSpan(text: ' at $venueName. Rooms already playing will follow '
                'the new band straight away.'),
          ],
        ),
        confirmLabel: 'Apply to all',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ),
  );
}
