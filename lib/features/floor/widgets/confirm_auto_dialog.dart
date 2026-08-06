import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/prism_top_bar.dart';
import '../../../theme/palette.dart';

/// Confirms handing the room back to the schedule after a manual override.
///
/// Confirmed rather than immediate, for the same reason S01-3 confirms a vibe
/// switch: this changes what the room is audibly playing, and a mis-tap in a
/// busy venue is expensive. The Venues screens perform the same action without
/// a confirm (`venue_screen.dart`) — that inconsistency is real and is logged
/// in `open_questions.md` rather than being quietly resolved in either
/// direction.
///
/// The body deliberately promises no timing. The zone row's "auto in 42 min" is
/// a mock seed with no server source, so a countdown here would be invented.
Future<bool?> showConfirmAutoDialog(BuildContext context) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Icon(LucideIcons.rotateCcw, size: 20, color: palette.accentText),
        title: 'Let Prism take it from here?',
        body: const TextSpan(
          text: 'The room goes back to your schedule and Prism picks the vibe '
              'again. You can still change it whenever you like.',
        ),
        // Not "Back to Auto" — that is the control that opened this dialog, and
        // repeating it makes the confirm read as the same button twice.
        confirmLabel: 'Let Prism drive',
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    ),
  );
}
