import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/zone.dart';
import '../../data/repositories/venue_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/zone_row.dart' as rows;
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// S04-1 "Manager — operate one venue: catch zone problems & fix from the
/// list" (M+O). Venue header + §3 ZoneRows; off-schedule rows carry the
/// "Return to Auto" quick-fix, others a chevron → zone detail (S05-5,
/// wired when Section 05 lands).
///
/// Serves two mounts (§4): the manager's tab-level /venues (no back) and
/// the owner's /venues/:id drill-in (top-bar back chevron).
class VenueScreen extends ConsumerWidget {
  const VenueScreen({super.key, required this.venueId, this.drillIn = false});

  final String venueId;

  /// True when reached via /venues/:id from the portfolio (sub-screen).
  final bool drillIn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final venue = ref.watch(venueProvider(venueId)).value;

    // §2.0 status line, bound to the routed venue. "online" is connectivity:
    // an off-schedule zone is still online; an offline zone flips the line
    // (derived — open_questions).
    final offlineZone = venue?.zones
        .where((z) => z.status == ZoneStatus.offline)
        .firstOrNull;
    // Empty-zones case (last zone removed via S05-5) is undesigned — derived.
    final firstZone = venue?.zones.firstOrNull;
    final subtitle = venue == null
        ? ref.watch(venueHeaderProvider).subtitle
        : offlineZone != null
            ? '${offlineZone.name} · offline'
            : firstZone != null
                ? '${firstZone.name} · online'
                : 'No zones';

    return Scaffold(
      body: Column(
        children: [
          PrismTopBar(
            title: venue?.name ?? ref.watch(venueNameProvider),
            subtitle: subtitle,
            statusDot: offlineZone == null && firstZone != null,
            showBack: drillIn,
            onBack: drillIn ? () => context.go('/venues') : null,
            user: user,
          ),
          Expanded(
            child: venue == null
                ? const SizedBox.shrink() // unknown id; states undesigned
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(venue.name,
                            style: PrismType.body.copyWith(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                                color: palette.textPrimary)),
                        if (venue.address != null) ...[
                          const SizedBox(height: 3),
                          Text(venue.address!,
                              style: PrismType.label.copyWith(
                                  fontWeight: FontWeight.w400,
                                  color: palette.textSecondary)),
                        ],
                        const SizedBox(height: 14),
                        for (final zone in venue.zones) ...[
                          rows.ZoneRow(
                            name: zone.name,
                            statusText: _statusText(zone),
                            status: _rowStatus(zone.status),
                            // S04-1 "Open floor →": with more than one zone,
                            // each row can point the whole app at that room —
                            // the Floor, Schedule and Settings tabs all follow
                            // the session's current zone.
                            actionLabel:
                                venue.zones.length > 1 ? 'Open floor' : null,
                            onAction: venue.zones.length > 1
                                ? () {
                                    ref
                                        .read(sessionContextProvider.notifier)
                                        .operateZone(
                                          venueId: venue.id,
                                          venueName: venue.name,
                                          zoneId: zone.id,
                                          zoneName: zone.name,
                                        );
                                    context.go('/floor');
                                  }
                                : null,
                            quickFixLabel:
                                zone.status == ZoneStatus.offSchedule
                                    ? 'Return to Auto'
                                    : null,
                            onQuickFix: () async {
                              try {
                                await ref
                                    .read(venueRepoProvider)
                                    .returnZoneToAuto(venue.id, zone.id);
                              } catch (e) {
                                if (context.mounted) {
                                  showPrismError(context, e);
                                }
                              }
                            },
                            // §4 edge: venue → zone-detail (S05-5).
                            onTap: zone.status == ZoneStatus.offSchedule
                                ? null
                                : () =>
                                    context.go('/venues/zones/${zone.id}'),
                          ),
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

  /// Quiet-row sub is underspecified — derived (open_questions).
  static String _statusText(Zone zone) => switch (zone.status) {
        ZoneStatus.offline => zone.statusDetail ?? 'Offline',
        ZoneStatus.offSchedule => zone.statusDetail ?? 'Off schedule',
        ZoneStatus.auto => 'Auto · ${moodById(zone.moodId).name}',
      };

  static rows.ZoneStatus _rowStatus(ZoneStatus status) => switch (status) {
        ZoneStatus.auto => rows.ZoneStatus.ok,
        ZoneStatus.offline => rows.ZoneStatus.offline,
        ZoneStatus.offSchedule => rows.ZoneStatus.offSchedule,
      };
}
