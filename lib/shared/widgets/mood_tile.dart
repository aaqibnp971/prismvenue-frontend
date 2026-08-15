import 'package:flutter/material.dart';

import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'energy_bars.dart';
import 'eq_bars.dart';

enum MoodTileState { idle, playing, paused }

/// Mood tile — §3: h124 r16 padding 13×15 (v×h).
/// Idle: `tint` base + mood tint gradient (13%→3%), border mood@22%,
///       11px dot + EnergyBars; name 19 italic serif bottom-anchored,
///       meta 11.5.
/// Playing: mood gradient pair (150°), white text, EqBars + "Playing" chip
///          (white@25% bg), shadow 0 12 28 mood@28% (§1.7).
/// Paused: playing visuals with the eq animation stopped (S01-2 — the spec's
///         only stated delta; chip copy unverified, see open_questions.md).
class MoodTile extends StatelessWidget {
  const MoodTile({
    super.key,
    required this.mood,
    this.state = MoodTileState.idle,
    this.meta,
    this.onTap,
    this.compact = false,
  });

  final Mood mood;
  final MoodTileState state;

  /// Meta line under the name (11.5). Content is screen-supplied.
  final String? meta;

  /// Phone sizing: shorter, tighter, and the "Playing" pill gives up room
  /// first. Set by the grid, which is the only thing that knows how many
  /// columns it decided on.
  final bool compact;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final b = palette.brightness;
    final playing = state != MoodTileState.idle;
    const white = Color(0xFFFFFFFF);

    final fg = playing ? white : palette.textPrimary;
    final metaFg = playing ? white : palette.textSecondary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        // Shorter on a phone. 124 is the frame's height against a three-across
        // grid on an iPad; on a two-across phone grid it is six rows of tile
        // and no room for anything else on the screen.
        height: compact ? 96 : 124,
        padding: EdgeInsets.symmetric(
            vertical: compact ? 10 : 13, horizontal: compact ? 11 : 15),
        decoration: playing
            ? BoxDecoration(
                gradient: mood.playingGradient(),
                borderRadius: BorderRadius.circular(16),
                boxShadow: PrismPalette.playingTileShadow(mood.dot(b)),
              )
            : BoxDecoration(
                // §1.3 tint gradient pre-composited over the `tint` base.
                gradient: mood.idleTintGradient(b, over: palette.tint),
                border: Border.all(color: mood.idleBorder(b)),
                borderRadius: BorderRadius.circular(16),
              ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (playing) ...[
                  EqBars(color: white, animate: state == MoodTileState.playing),
                  const Spacer(),
                  // Flexible, because the pill is the widest thing on the row
                  // and the tile can be half an iPad column wide. It shrinks
                  // and ellipsises rather than pushing the bars off the tile.
                  Flexible(
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          vertical: 3, horizontal: compact ? 6 : 9),
                      decoration: BoxDecoration(
                        color: white.withValues(alpha: .25),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text('Playing',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PrismType.micro.copyWith(color: white)),
                    ),
                  ),
                ] else ...[
                  Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                        color: mood.dot(b), shape: BoxShape.circle),
                  ),
                  const Spacer(),
                  EnergyBars(energy: mood.energy, color: mood.dot(b)),
                ],
              ],
            ),
            const Spacer(),
            // Single line and ellipsised. "Afternoon lift" wraps in a phone
            // column, and a second line is taller than the tile — which
            // Flutter answers by painting the overflow banner over the mood
            // name itself, so the one word that matters is the one you lose.
            Text(mood.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PrismType.moodNameTile.copyWith(color: fg)),
            if (meta != null)
              Text(meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PrismType.meta.copyWith(color: metaFg)),
          ],
        ),
      ),
    );
  }
}
