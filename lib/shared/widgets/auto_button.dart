import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'pressable.dart';

/// Floor hero control — "Auto": hand the room to the schedule and leave it
/// there.
///
/// Sits immediately left of [TakeOverButton] and borrows its metrics (h50,
/// padding-h 22, r14, border 1.5) so the two read as one control group: who is
/// driving the room, Prism or a person.
///
/// It is deliberately a **standing** control rather than one that only appears
/// after someone overrides. The affordance this replaces — a small "Back to
/// Auto" text link inside the hero's wrap — only existed while the room was
/// already off schedule, so a venue that had never overridden had no way to see
/// that letting Prism drive was an option at all. Staff asked for exactly this:
/// a way to say "just follow the schedule" without first having to take manual
/// control and then give it back.
///
/// [active] is the resting state (the schedule is running). It renders filled
/// and takes no tap — there is nothing to switch to, and a live-looking button
/// that does nothing is worse than one that plainly reads as "already on".
class AutoButton extends StatelessWidget {
  const AutoButton({super.key, required this.active, this.onTap});

  /// Whether the room is currently following the schedule.
  final bool active;

  /// Hands the room back to the schedule. Null while [active] — see above.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final ink = active ? palette.accentText : palette.textPrimary;

    return Pressable(
      onTap: active ? null : onTap,
      child: Container(
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(
          color: active ? palette.accentSoft : null,
          border: Border.all(
            color: active ? palette.accent : palette.borderStrong,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          // Centred, not start-aligned: the Floor hero stretches these to share
          // a row on narrow screens, and a left-hugging label looks broken.
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(LucideIcons.sparkles, size: 17, color: ink),
            const SizedBox(width: 9),
            Text('Auto', style: PrismType.button.copyWith(color: ink)),
          ],
        ),
      ),
    );
  }
}
