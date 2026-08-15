import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/local_playback.dart';
import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/zone.dart';
import '../../data/repositories/venue_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/error_state.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/zone_row.dart' as rows;
import 'add_zone_sheet.dart';
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
    // A room this app is playing is demonstrably not offline, whatever the
    // never-written `devices.online` says — see app/local_playback.dart.
    // Nullability is preserved: null still means "could not be loaded", which
    // is the ErrorState below, not an empty venue.
    final loaded = ref.watch(venueProvider(venueId)).value;
    final venue = loaded == null
        ? null
        : withLocalPlayback(loaded, ref.watch(locallyPlayingZoneProvider));

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
                // Was SizedBox.shrink(): a fetch failure and a venue that does
                // not exist both rendered as an empty screen under a top bar
                // showing the previous venue's name.
                ? ErrorState(
                    message: 'That venue could not be loaded.',
                    onRetry: () => ref.invalidate(venueProvider(venueId)),
                  )
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(15),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                ],
                              ),
                            ),
                            // Suppressed while the venue is empty: the
                            // "No zones yet" card below carries its own, and
                            // two controls for the same thing is a bug.
                            if (venue.zones.isNotEmpty) ...[
                              const SizedBox(width: 12),
                              _AddZoneButton(venueId: venue.id),
                            ],
                          ],
                        ),
                        const SizedBox(height: 14),
                        if (venue.zones.isEmpty)
                          _NoZones(venueId: venue.id)
                        else
                          for (final zone in venue.zones) ...[
                          rows.ZoneRow(
                            name: zone.name,
                            statusText: _statusText(zone),
                            status: _rowStatus(zone.status),
                            // S04-1 "Open floor →": points the whole app at
                            // that room — Floor, Schedule and Settings all
                            // follow the session's current zone, so this is
                            // the only control in the app that changes which
                            // venue you are operating.
                            //
                            // Offered on every row EXCEPT the one already
                            // being operated. The old rule was
                            // `venue.zones.length > 1`, reasoning that a
                            // single-zone venue has "nothing to switch
                            // between" — true within one venue, and wrong for
                            // the estate. An owner whose venues each hold one
                            // zone got the control nowhere, so there was no
                            // way to point the app at a different venue at
                            // all and every venue's Floor tab showed whichever
                            // room sign-in happened to pick.
                            actionLabel: _isCurrent(ref, zone.id)
                                ? null
                                : 'Open floor',
                            onAction: _isCurrent(ref, zone.id)
                                ? null
                                : () {
                                    ref
                                        .read(sessionContextProvider.notifier)
                                        .operateZone(
                                          venueId: venue.id,
                                          venueName: venue.name,
                                          zoneId: zone.id,
                                          zoneName: zone.name,
                                        );
                                    context.go('/floor');
                                  },
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
                            //
                            // Off-schedule rows used to be inert, on the
                            // reasoning that they carry a quick-fix instead. It
                            // inverted the screen's purpose: the rows a manager
                            // most wants to inspect were the only ones they
                            // could not open, so you had to fix a zone before
                            // you could look at why it needed fixing.
                            onTap: () =>
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

  /// The room the app is pointed at right now.
  ///
  /// Read rather than watched: this rebuilds with the venue stream anyway, and
  /// tapping "Open floor" navigates away in the same frame.
  static bool _isCurrent(WidgetRef ref, String zoneId) =>
      ref.read(currentZoneIdProvider) == zoneId;

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

/// Adds a zone to a venue that already exists — the other half of S05-5
/// "Remove zone".
///
/// Reuses the S04-4 sheet the add-venue flow already collects names with, so
/// the two paths ask the same question the same way. Styled like the
/// portfolio's "+ Venue" for the same reason.
class _AddZoneButton extends ConsumerWidget {
  const _AddZoneButton({required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Pressable(
      onTap: () => addZoneTo(context, ref, venueId),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
        decoration: BoxDecoration(
          color: palette.accent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text('+ Zone',
            style:
                PrismType.bodySm.copyWith(fontSize: 12.5, color: palette.chipInk)),
      ),
    );
  }
}

/// A venue with no zones at all.
///
/// Reachable two ways: removing the last zone via S05-5, and creating a venue
/// with no zone names. It used to render as a bare heading over nothing — and
/// worse, it was terminal, because every zone-scoped screen throws
/// `no_zone_selected` and no control anywhere could create a zone.
class _NoZones extends ConsumerWidget {
  const _NoZones({required this.venueId});

  final String venueId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 15),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text('No zones yet',
              style: PrismType.body.copyWith(
                  fontWeight: FontWeight.w600, color: palette.textPrimary)),
          const SizedBox(height: 5),
          Text(
            'A zone is one area with its own speakers. Add one to give this '
            'venue a floor, a schedule and its own sound.',
            textAlign: TextAlign.center,
            style: PrismType.microHelper.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 14),
          _AddZoneButton(venueId: venueId),
        ],
      ),
    );
  }
}

/// Shared by both entry points above.
///
/// Wrapped in try/catch like every other mutation in the app: a duplicate name
/// is a 409 the manager can act on, and swallowing it would leave the sheet
/// looking like it worked.
Future<void> addZoneTo(BuildContext context, WidgetRef ref, String venueId) async {
  final name = await showAddZoneSheet(context);
  if (name == null) return;
  try {
    await ref.read(venueRepoProvider).addZone(venueId, name);
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
  }
}
