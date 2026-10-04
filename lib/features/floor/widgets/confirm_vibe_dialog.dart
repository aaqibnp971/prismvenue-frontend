import 'package:flutter/material.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/prism_top_bar.dart';
import '../../../theme/moods.dart';
import '../../../theme/palette.dart';

/// S01-3 "Confirm before switching the vibe — no accidental changes".
/// ConfirmDialog over a scrim that starts below the top bar; icon = mood dot;
/// title "Switch to Evening warmth?"; body "The room eases over ~40s.
/// 92 BPM · energy 3/5."; Cancel / "Switch the vibe".
/// Resolves true when confirmed.
///
/// A mood with no pulse has no tempo to quote, so its body reads "The room
/// eases over ~40s. Energy 2/5." — the tempo is left out, not replaced.
Future<bool?> showConfirmVibeDialog(BuildContext context, {required Mood mood}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: mood.dot(palette.brightness),
            shape: BoxShape.circle,
          ),
        ),
        title: 'Switch to ${mood.name}?',
        body: TextSpan(
          text: 'The room eases over ~40s. '
              '${mood.tempoLabel == null ? 'Energy' : '${mood.tempoLabel} · energy'} '
              '${mood.energy}/5.',
        ),
        confirmLabel: 'Switch the vibe',
        onCancel: () => Navigator.of(dialogContext).pop(false),
        onConfirm: () => Navigator.of(dialogContext).pop(true),
      ),
    ),
  );
}
