import 'package:flutter/material.dart';

import '../../../shared/widgets/mood_tile.dart';
import '../../../theme/moods.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// Moods block — §2 S01-1: header row mb11 ("Moods" 19 serif + "Tap to
/// change the vibe · one tap" 11 `textSecondary`), grid 3×2, gap 12,
/// tile h124.
class MoodGrid extends StatelessWidget {
  const MoodGrid({
    super.key,
    required this.currentMoodId,
    required this.paused,
    this.onMoodTap,
  });

  final String currentMoodId;
  final bool paused;
  final ValueChanged<Mood>? onMoodTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;

    MoodTileState stateFor(Mood mood) {
      if (mood.id != currentMoodId) return MoodTileState.idle;
      return paused ? MoodTileState.paused : MoodTileState.playing;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, box) {
          // The hint is the first thing to go. It restates what the tiles
          // already invite, so on a phone it costs more than it explains —
          // and left in place it pushed the section title itself off-screen.
          final room = box.maxWidth >= 520;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('Moods',
                  style:
                      PrismType.sectionH2.copyWith(color: palette.textPrimary)),
              const Spacer(),
              if (room)
                Flexible(
                  child: Text('Tap to change the vibe · one tap',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PrismType.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: palette.textSecondary)),
                ),
            ],
          );
        }),
        const SizedBox(height: 11),
        // Six moods across two rows of three is the frame, and it assumes an
        // iPad. At a phone's width three columns leave each tile about 90
        // logical pixels wide — narrower than the word "Afternoon" — so the
        // grid drops to two and runs three rows instead. Derived from the
        // measured width rather than from a platform check, because a resized
        // desktop window gets just as narrow.
        LayoutBuilder(builder: (context, box) {
          final columns = box.maxWidth < 560 ? 2 : 3;
          final compact = columns < 3;
          final rows = (moods.length + columns - 1) ~/ columns;
          return Column(
            children: [
              for (var row = 0; row < rows; row++) ...[
                if (row > 0) const SizedBox(height: 12),
                Row(
                  children: [
                    for (var col = 0; col < columns; col++) ...[
                      if (col > 0) const SizedBox(width: 12),
                      Expanded(
                        child: Builder(builder: (context) {
                          final i = row * columns + col;
                          // The last row can be short of a full set — six into
                          // four does not divide. An empty cell keeps the
                          // remaining tiles the same width as every other row's.
                          if (i >= moods.length) return const SizedBox();
                          final mood = moods[i];
                          return MoodTile(
                            mood: mood,
                            state: stateFor(mood),
                            meta: '${mood.bpm} BPM',
                            compact: compact,
                            onTap: onMoodTap == null
                                ? null
                                : () => onMoodTap!(mood),
                          );
                        }),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          );
        }),
      ],
    );
  }
}
