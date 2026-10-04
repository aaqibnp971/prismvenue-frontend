import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/repositories/mood_repo.dart';
import '../../../data/models/zone.dart';
import '../../../data/models/zone_activity.dart';
import '../../../data/repositories/playback_repo.dart';
import '../../../theme/moods.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// "Recent activity" on the zone screen — finding #15.
///
/// An owner finds a room paused and cannot tell who paused it, or when. This
/// is the answer, and the most valuable half of it is the entries with no
/// person attached: "Prism switched to Evening warmth" at 6pm is the line that
/// turns an unexplained change into the schedule doing its job.
///
/// ## Why it fails quietly
///
/// A failed read leaves the section out rather than showing an error. Every
/// other thing on this screen — the zone's name, its hours, the Remove button —
/// still works without it, and a red block over a history panel would make a
/// working screen look broken. The one thing worth saying out loud is an EMPTY
/// history, because "nothing has happened here" and "we could not load it" are
/// different answers and the owner deserves to know which.
class RecentActivity extends ConsumerWidget {
  const RecentActivity({super.key, required this.zoneId});

  final String zoneId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuilds this screen when a mood it drew as unknown becomes known. The
    // value is not used here: moods are read through `moodById`.
    ref.watch(moodCatalogProvider);
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final entries = ref.watch(zoneActivityProvider(zoneId));

    return entries.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (list) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Recent activity',
              style: PrismType.label.copyWith(color: palette.textSecondary)),
          const SizedBox(height: 8),
          if (list.isEmpty)
            Text(
              'Nothing has changed in this room yet.',
              style:
                  PrismType.microHelper.copyWith(color: palette.textSecondary),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: palette.surface,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0)
                      Divider(height: 1, thickness: 1, color: palette.border),
                    _ActivityRow(entry: list[i]),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.entry});

  final ZoneActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final brightness = Theme.of(context).brightness;
    final moodId = entry.moodId;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 13),
      child: Row(
        children: [
          // The mood it changed to, when it changed one. A fixed-width slot
          // either way, so the lines stay left-aligned whether or not there is
          // a dot — a ragged column is harder to scan than a plain one.
          SizedBox(
            width: 15,
            child: moodId == null
                ? null
                : Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: moodById(moodId).dot(brightness),
                      shape: BoxShape.circle,
                    ),
                  ),
          ),
          Expanded(
            child: Text(
              // Server-composed and rendered verbatim, like `hours_label`.
              entry.line,
              style: PrismType.bodySm
                  .copyWith(fontSize: 12.5, color: palette.textPrimary),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            // Applied at build time against the reader's clock, so a panel
            // left open does not keep insisting it was "just now".
            lastSeenLabel(entry.at) ?? '',
            style:
                PrismType.meta.copyWith(fontSize: 11, color: palette.textSecondary),
          ),
        ],
      ),
    );
  }
}
