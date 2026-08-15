import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'pressable.dart';

/// Floor hero CTA — §3: h50, padding-h 22, r14, transparent bg, border 1.5
/// `borderStrong`, "Take over" 14/700 + headphones icon 17, gap 9.
/// Pressed = 92% scale (§6-A2).
class TakeOverButton extends StatelessWidget {
  const TakeOverButton({super.key, this.onTap, this.label = 'Take over'});

  final VoidCallback? onTap;

  /// "Take over" normally; "Hand back" once a takeover is already running.
  ///
  /// The destination was always right — it routes to S02, which shows the
  /// ACTIVE screen when one is in flight — but the label was not. A button
  /// offering to take over a room that staff already hold reads as a control
  /// that has not noticed, which is exactly how the Floor screen managed to
  /// look broken during a perfectly normal takeover.
  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Pressable(
      onTap: onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          border: Border.all(color: palette.borderStrong, width: 1.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          // Centred for the same reason as AutoButton: the Floor hero stretches
          // the pair to share a row on narrow screens.
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.headphones, size: 17, color: palette.textPrimary),
            const SizedBox(width: 9),
            Text(label,
                style: PrismType.button.copyWith(color: palette.textPrimary)),
          ],
        ),
      ),
    );
  }
}
