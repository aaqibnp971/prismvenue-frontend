import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import '../../shared/widgets/prism_toast.dart';
import '../../shared/widgets/zone_row.dart' as rows;
import '../floor/widgets/confirm_auto_dialog.dart';
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// How the portfolio is ordered — finding #19.
///
/// §6-B5 listed sort options as an open question and the chip shipped inert
/// because of it. The walkthrough answered the question from the other end: an
/// owner tapped it expecting a menu and nothing happened, which is worse than
/// no chip at all. Two orders, because those are the two an owner actually
/// asks for — "what needs me" and "where is the one I'm thinking of".
enum VenueSort {
  needsAttention('Needs attention'),
  nameAZ('Name A–Z');

  const VenueSort(this.label);
  final String label;
}

final venueSortProvider =
    NotifierProvider<VenueSortNotifier, VenueSort>(VenueSortNotifier.new);

class VenueSortNotifier extends Notifier<VenueSort> {
  @override
  VenueSort build() => VenueSort.needsAttention;

  void toggle() => state = state == VenueSort.needsAttention
      ? VenueSort.nameAZ
      : VenueSort.needsAttention;
}

/// What the owner has typed into the portfolio search box.
final venueQueryProvider =
    NotifierProvider<VenueQueryNotifier, String>(VenueQueryNotifier.new);

class VenueQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// Search appears only once scrolling is the alternative.
///
/// The report says "once an owner has more than about 10 venues". Below that
/// the whole estate is on one screen and a search box is a control that costs
/// space and earns nothing.
const venueSearchThreshold = 8;

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
    final all = [
      for (final v in ref.watch(venuesProvider).value ?? const <Venue>[])
        withLocalPlayback(v, local),
    ];
    final query = ref.watch(venueQueryProvider).trim().toLowerCase();
    // Name and address both: an owner looking for "the Deira one" is as likely
    // to remember where it is as what it is called.
    final matching = query.isEmpty
        ? all
        : [
            for (final v in all)
              if (v.name.toLowerCase().contains(query) ||
                  (v.address ?? '').toLowerCase().contains(query))
                v,
          ];
    final sort = ref.watch(venueSortProvider);
    final venues = switch (sort) {
      VenueSort.needsAttention => needsAttentionFirst(matching),
      VenueSort.nameAZ => [...matching]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
    };

    return Scaffold(
      body: Column(
        children: [
          // Portfolio top-bar copy is underspecified (§2.0 assumes a single
          // venue) — derived (open_questions).
          PrismTopBar(
            title: 'Your venues',
            // Says what is on screen, and what is not. "3 venues" over a
            // filtered list of 3 out of 40 would be a quiet lie.
            subtitle: query.isEmpty
                ? '${venues.length} venues'
                : '${venues.length} of ${all.length} venues',
            user: user,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Finding #19: no way to find a venue but scrolling. Shown
                  // only once the estate is big enough that scrolling is the
                  // alternative — below that it is a control that costs space
                  // and earns nothing.
                  if (all.length >= venueSearchThreshold) ...[
                    _VenueSearchField(
                      onChanged: (v) =>
                          ref.read(venueQueryProvider.notifier).set(v),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Row(
                    children: [
                      // §6-B5: sort options beyond "Needs attention" are an
                      // open question — single inert chip. Flexible so the
                      // "+ Venue" button beside it keeps its full label on a
                      // phone: the chip is inert, the button is the only way
                      // to add a venue, so the chip is what gives way.
                      Flexible(
                        child: Pressable(
                          // Finding #19: this was inert, and looked exactly
                          // like a menu. Tapping now moves between the two
                          // orders and the label says which one you are in, so
                          // the control and its state are the same object.
                          onTap: () =>
                              ref.read(venueSortProvider.notifier).toggle(),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 6, horizontal: 12),
                            decoration: BoxDecoration(
                              color: palette.tile,
                              border: Border.all(color: palette.border),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(sort.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PrismType.bodySm.copyWith(
                                    fontSize: 11.5,
                                    color: palette.textPrimary)),
                          ),
                        ),
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
  int rank(Venue v) {
    // Finding #9: a venue with no zones cannot play anything, and it used to
    // rank with the healthy ones because it has no zone to be unhealthy. It
    // sits with the amber rows — it needs somebody, but not urgently.
    if (v.zones.isEmpty) return 1;
    return switch (v.worstStatus) {
      ZoneStatus.offline => 0,
      ZoneStatus.offSchedule => 1,
      ZoneStatus.auto => 2,
    };
  }
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
    // Finding #9: a zero-zone venue said "0 zones" in the quiet style and sat
    // among the healthy rows, though it cannot play a note. Creating one is now
    // refused, but they still exist — made before that, or left behind when a
    // venue's last zone is removed (S05-5) — so the row has to say so itself.
    final quietSub = zoneCount == 0
        ? 'Setup needed · add a zone'
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
      // #16: an owner scanning the portfolio needs to know whether this is
      // minutes old or weeks old before deciding to drive to the venue.
      ZoneStatus.offline => switch (lastSeenLabel(problemZone!.lastSeenAt)) {
          final seen? => '${problemZone.name} · Offline · last seen $seen',
          _ => '${problemZone.name} · Offline · never reported',
        },
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
      // Amber for a venue with nothing in it: the same "needs somebody, not
      // urgently" treatment an overridden room gets.
      status: zoneCount == 0
          ? rows.ZoneStatus.offSchedule
          : switch (venue.worstStatus) {
              ZoneStatus.auto => rows.ZoneStatus.ok,
              ZoneStatus.offline => rows.ZoneStatus.offline,
              ZoneStatus.offSchedule => rows.ZoneStatus.offSchedule,
            },
      quickFixLabel: fixableZone != null ? 'Return to Auto' : null,
      onQuickFix: fixableZone != null
          ? () async {
              // Finding #13: one tap on a portfolio row changed what a room
              // was playing, with nothing asked beforehand and nothing said
              // after. The same action on Floor has always confirmed first
              // ("Let Prism take it from here?"), and two controls for one
              // thing behaving differently is the bug — mutations here are
              // fire-and-forget, so the dialog is the only chance to change
              // your mind.
              if (await showConfirmAutoDialog(context) != true) return;
              try {
                await ref
                    .read(venueRepoProvider)
                    .returnZoneToAuto(venue.id, fixableZone.id);
                if (context.mounted) {
                  showPrismToast(context, '${fixableZone.name} is back on Auto');
                }
              } catch (e) {
                if (context.mounted) showPrismError(context, e);
              }
            }
          : null,
      onTap: () => context.go('/venues/${venue.id}'),
    );
  }
}


/// The portfolio's search box (finding #19).
///
/// Stateful only to own its controller: the text itself lives in
/// [venueQueryProvider], because the list that reads it is rebuilt by the
/// screen above, not by this widget.
class _VenueSearchField extends StatefulWidget {
  const _VenueSearchField({required this.onChanged});

  final ValueChanged<String> onChanged;

  @override
  State<_VenueSearchField> createState() => _VenueSearchFieldState();
}

class _VenueSearchFieldState extends State<_VenueSearchField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return TextField(
      controller: _controller,
      onChanged: widget.onChanged,
      style: PrismType.bodySm.copyWith(color: palette.textPrimary),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Search venues',
        hintStyle: PrismType.bodySm.copyWith(color: palette.textSecondary),
        prefixIcon:
            Icon(LucideIcons.search, size: 16, color: palette.textSecondary),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 34, minHeight: 34),
        filled: true,
        fillColor: palette.tile,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: palette.accent),
        ),
      ),
    );
  }
}
