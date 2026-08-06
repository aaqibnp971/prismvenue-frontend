import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../data/models/playback_state.dart';
import '../../../shared/widgets/noise_meter.dart';
import '../../../shared/widgets/pressable.dart';
import '../../../shared/widgets/status_pill.dart';
import '../../../shared/widgets/take_over_button.dart';
import '../../../theme/moods.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// Floor hero — §2 S01-1: bg `surface`, border, r14, padding 24×22 (v×h),
/// row gap 20. Pause button 64 circle accent (white icon 20; play icon while
/// paused, S01-2). Center: "NOW PLAYING" caps → mood row (wrap, gap 9: dot
/// 11, name 31 italic serif, pill, context 10.5) → noise row mt10.
/// Right: Take over.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.state,
    required this.noise,
    this.onTogglePause,
    this.onTakeOver,
    this.onReturnToAuto,
  });

  final PlaybackState state;
  final int noise;
  final VoidCallback? onTogglePause;
  final VoidCallback? onTakeOver;

  /// Hands the room back to the schedule. Null hides the control — the Floor
  /// screen passes null during a takeover, where S02 already owns the hand-back
  /// and two competing controls would be exactly the dashboard/speaker
  /// disagreement the engine seam exists to prevent.
  final VoidCallback? onReturnToAuto;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final mood = moodById(state.moodId);

    // S01-1 pill: "Prism is driving" (accentSoft). S01-2 swaps it for an
    // amber-tinted "Paused by **Priya** · tap play to resume".
    final pill = state.paused
        ? StatusPill(
            text: 'Paused by ${state.pausedBy} · tap play to resume',
            tone: PillTone.amber,
            span: TextSpan(
              text: 'Paused by ',
              children: [
                TextSpan(
                    text: state.pausedBy ?? '',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const TextSpan(text: ' · tap play to resume'),
              ],
            ),
          )
        : state.offSchedule
            // Someone chose this vibe, so "Prism is driving" would be a lie —
            // and it is the lie that hides the fact the schedule is not running.
            ? const StatusPill(
                text: 'Off schedule · you chose this vibe', tone: PillTone.amber)
            : const StatusPill(text: 'Prism is driving', dot: true);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 22),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onTogglePause,
            child: Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: palette.accent, shape: BoxShape.circle),
              child: Icon(
                state.paused ? LucideIcons.play : LucideIcons.pause,
                size: 20,
                color: const Color(0xFFFFFFFF),
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('NOW PLAYING',
                    style: PrismType.labelCaps
                        .copyWith(color: palette.textSecondary)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Container(
                      width: 11,
                      height: 11,
                      decoration: BoxDecoration(
                        color: mood.dot(palette.brightness),
                        shape: BoxShape.circle,
                      ),
                    ),
                    Text(mood.name,
                        style: PrismType.moodNameHero
                            .copyWith(color: palette.textPrimary)),
                    pill,
                    // Only while the room is actually overridden. A permanently
                    // visible hand-back implies something is wrong when nothing
                    // is, and S01-1's resting state is "Prism is driving".
                    if (state.offSchedule && onReturnToAuto != null)
                      Pressable(
                        onTap: onReturnToAuto,
                        child: Text(
                          'Back to Auto',
                          style: PrismType.microHelper.copyWith(
                            color: palette.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    Text(state.contextLine,
                        style: PrismType.microHelper
                            .copyWith(color: palette.textSecondary)),
                  ],
                ),
                const SizedBox(height: 10),
                NoiseMeter(value: noise),
              ],
            ),
          ),
          const SizedBox(width: 20),
          TakeOverButton(onTap: onTakeOver),
        ],
      ),
    );
  }
}
