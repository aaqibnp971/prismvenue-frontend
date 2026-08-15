import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/local_playback.dart';
import '../../app/session.dart';
import '../../data/models/venue.dart';
import '../../data/models/zone.dart';
import '../../data/repositories/venue_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/venue_row.dart' as rows;
import '../../shared/widgets/zone_row.dart' as rows;
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// S04-2 "Owner — triage the portfolio: problems shout, healthy venues
/// whisper" (owner only). Sort chip "Needs attention"; venue rows: 32
/// initial-avatar, name 13.5/700, sub "1 zone · Peak" 11; problem rows
/// carry red/amber status + "Return to Auto"; healthy rows quiet (no %
/// values — deliberately removed). Row tap → S04-1; "+ Venue" → S04-3.
class PortfolioScreen extends ConsumerWidget {
  const PortfolioScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects
    final palette = Theme.of(context).extension<PrismPalette>()!;
    // Corrected BEFORE sorting: a room this app is audibly playing must not be
    // hoisted to the top of "Needs attention" as offline. See
    // app/local_playback.dart.
    final local = ref.watch(localPlaybackProvider);
    final venues = needsAttentionFirst([
      for (final v in ref.watch(venuesProvider).value ?? const <Venue>[])
        withLocalPlayback(v, local),
    ]);

    return Scaffold(
      body: Column(
        children: [
          // Portfolio top-bar copy is underspecified (§2.0 assumes a single
          // venue) — derived (open_questions).
          PrismTopBar(
            title: 'Your venues',
            subtitle: '${venues.length} venues',
            user: user,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      // §6-B5: sort options beyond "Needs attention" are an
                      // open question — single inert chip.
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 6, horizontal: 12),
                        decoration: BoxDecoration(
                          color: palette.tile,
                          border: Border.all(color: palette.border),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('Needs attention',
                            style: PrismType.bodySm.copyWith(
                                fontSize: 11.5, color: palette.textPrimary)),
                      ),
                      const Spacer(),
                      Pressable(
                        onTap: () => context.go('/venues/add'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 8, horizontal: 14),
                          decoration: BoxDecoration(
                            color: palette.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text('+ Venue',
                              style: PrismType.bodySm.copyWith(
                                  fontSize: 12.5, color: palette.chipInk)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  for (final venue in venues) ...[
                    _VenueRow(venue: venue),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// S04-2's whole reason for existing is that problems shout. The screen drew a
/// "Needs attention" chip over a list in whatever order the API returned — and
/// the API orders by `created_at` — so an offline venue could sit below three
/// healthy ones under a label claiming otherwise. Nothing sorted on either
/// side.
///
/// Sorted here rather than server-side so the API and the mocks render
/// identically, which is the same reasoning `routers/venues.py` gives for
/// leaving order alone. Worth moving into SQL once a portfolio outgrows a
/// handful of venues.
///
/// Offline outranks off-schedule: a room nobody can reach needs someone to walk
/// to it, while an overridden one is a tap away from fixed. Ties keep the
/// server's order, so the list does not reshuffle under the reader on refresh.
@visibleForTesting
List<Venue> needsAttentionFirst(List<Venue> venues) {
  int rank(Venue v) => switch (v.worstStatus) {
        ZoneStatus.offline => 0,
        ZoneStatus.offSchedule => 1,
        ZoneStatus.auto => 2,
      };
  // Stable: List.sort is not, so compare the original index on a tie.
  final indexed = venues.indexed.toList()
    ..sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return [for (final (_, venue) in indexed) venue];
}

/// Thin adapter over the §3 shared VenueRow: derives the sub line (problem
/// zones shout, healthy rows whisper — open_questions item 21) and wires
/// the drill-in + quick-fix edges.
class _VenueRow extends ConsumerWidget {
  const _VenueRow({required this.venue});

  final Venue venue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoneCount = venue.zones.length;
    // Zero-zone venues (last zone removed via S05-5) are undesigned —
    // derived quiet sub without the mood segment.
    final quietSub = zoneCount == 0
        ? '0 zones'
        : '$zoneCount zone${zoneCount == 1 ? '' : 's'} · '
            '${moodById(venue.zones.first.moodId).name}';

    // The WORST zone, not merely the first non-auto one, so the sub line
    // describes the same zone the row's status dot is coloured for.
    final problemZone =
        venue.zones.where((z) => z.status == ZoneStatus.offline).firstOrNull ??
            venue.zones
                .where((z) => z.status == ZoneStatus.offSchedule)
                .firstOrNull;
    final sub = switch (problemZone?.status) {
      ZoneStatus.offline =>
        '${problemZone!.name} · ${problemZone.statusDetail ?? 'Offline'}',
      ZoneStatus.offSchedule =>
        '${problemZone!.name} · ${problemZone.statusDetail ?? 'Off schedule'}',
      _ => quietSub,
    };

    // Only ever the zone the row just named.
    //
    // The sub took the first NON-AUTO zone and the button took the first
    // OFF-SCHEDULE one, which are not the same zone: with an offline Terrace
    // and an off-schedule Main floor the row read "Terrace · Offline" beside a
    // "Return to Auto" button that silently fixed Main floor. A control that
    // acts on something other than what the row describes is worse than no
    // control.
    //
    // So a venue whose worst zone is offline shows no quick-fix -- which is
    // already the rule for offline rows elsewhere, since there is nothing to
    // fix remotely. Its off-schedule zones are still one tap away through the
    // venue.
    final fixableZone =
        problemZone?.status == ZoneStatus.offSchedule ? problemZone : null;

    return rows.VenueRow(
      name: venue.name,
      sub: sub,
      status: switch (venue.worstStatus) {
        ZoneStatus.auto => rows.ZoneStatus.ok,
        ZoneStatus.offline => rows.ZoneStatus.offline,
        ZoneStatus.offSchedule => rows.ZoneStatus.offSchedule,
      },
      quickFixLabel: fixableZone != null ? 'Return to Auto' : null,
      onQuickFix: fixableZone != null
          ? () async {
              try {
                await ref
                    .read(venueRepoProvider)
                    .returnZoneToAuto(venue.id, fixableZone.id);
              } catch (e) {
                if (context.mounted) showPrismError(context, e);
              }
            }
          : null,
      onTap: () => context.go('/venues/${venue.id}'),
    );
  }
}
