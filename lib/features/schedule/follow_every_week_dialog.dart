import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';

/// Confirms giving a forked week back to the recurring plan.
///
/// ## Why the way back matters more than the way out
///
/// "Just this week" is a copy-on-write fork (migration 011), and a forked week
/// stops consulting the recurring plan **entirely** — not per daypart, not for
/// the days it happens to fill. So after a week has diverged, every subsequent
/// "Every week" edit is written correctly, is genuinely saved, and is invisible
/// in the week on screen. It reads exactly like a save that did not work.
///
/// Until now the only remedy was deleting the week's dayparts one at a time.
///
/// ## Why it is confirmed
///
/// It discards this week's own plan, and nothing else on screen would report
/// that — the grid simply fills with different blocks. Same rule as every other
/// change the room will hear.
Future<bool?> showFollowEveryWeekDialog(BuildContext context) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon:
            Icon(LucideIcons.calendarSync, size: 20, color: palette.accentText),
        title: 'Follow the weekly plan again?',
        body: const TextSpan(
          text: 'This week has its own copy of the plan, which is why changes '
              'you make to every week do not show up here. Handing it back '
              'discards the dayparts set for this week only, and the week goes '
              'back to whatever the weekly plan says.',
        ),
        confirmLabel: 'Follow every week',
        cancelLabel: 'Keep this week separate',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ),
  );
}
