import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/roles.dart';
import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/guardrails.dart';
import '../../data/models/venue.dart';
import '../../data/repositories/settings_repo.dart';
import '../../data/repositories/venue_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_field.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/settings_row.dart';
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'confirm_remove_zone_dialog.dart';

/// S05-5 "Zone detail — name, hours, player, vibe, volume, remove". The
/// README gives this frame one line, so the form layout is derived: name
/// field + display rows for hours / player / vibe / volume, then the pinned
/// full-width "Remove zone" `red` button (open_questions).
class ZoneDetailScreen extends ConsumerStatefulWidget {
  const ZoneDetailScreen({super.key, required this.zoneId});

  final String zoneId;

  @override
  ConsumerState<ZoneDetailScreen> createState() => _ZoneDetailScreenState();
}

class _ZoneDetailScreenState extends ConsumerState<ZoneDetailScreen> {
  final _name = TextEditingController();
  var _nameSeeded = false;

  String get zoneId => widget.zoneId;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final venues = ref.watch(venuesProvider).value ?? const <Venue>[];
    final venue =
        venues.where((v) => v.zones.any((z) => z.id == zoneId)).firstOrNull;
    final zone =
        venue?.zones.where((z) => z.id == zoneId).firstOrNull;
    final guardrails =
        ref.watch(guardrailsProvider).value ?? const Guardrails();
    final hours = ref.watch(openHoursProvider).value ?? const OpenHours();
    if (!_nameSeeded && zone != null) {
      _name.text = zone.name;
      _nameSeeded = true;
    }

    // Back to where the zone list lives: manager tab-level /venues, owner
    // drill-in /venues/:id.
    final backTarget = user.role == Role.owner && venue != null
        ? '/venues/${venue.id}'
        : '/venues';

    return Scaffold(
      body: Column(
        children: [
          // §2.0: venue name stays in the title slot; zone as context.
          PrismTopBar(
            title: venue?.name ?? ref.watch(venueNameProvider),
            subtitle: zone?.name ?? 'Zone',
            showBack: true,
            onBack: () => context.go(backTarget),
            user: user,
          ),
          Expanded(
            child: zone == null
                ? const SizedBox.shrink() // removed/unknown; undesigned
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(15),
                    child: SizedBox(
                      width: 520,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          PrismField(label: 'Zone name', controller: _name),
                          const SizedBox(height: 14),
                          SettingsRow(
                            title: 'Open hours',
                            value: 'Every day · ${hours.rangeLabel}',
                            chevron: false,
                          ),
                          const SizedBox(height: 8),
                          // Player name is invented seed (open_questions).
                          const SettingsRow(
                              title: 'Player',
                              value: 'Prism Player 01',
                              chevron: false),
                          const SizedBox(height: 8),
                          SettingsRow(
                            title: 'Vibe',
                            value: moodById(zone.moodId).name,
                            chevron: false,
                          ),
                          const SizedBox(height: 8),
                          SettingsRow(
                            title: 'Volume',
                            value: guardrails.bandLabel,
                            chevron: false,
                          ),
                          const SizedBox(height: 18),
                          GestureDetector(
                            onTap: () async {
                              // Confirmed, not immediate. The app already puts
                              // a modal in front of *changing the music*;
                              // deleting a room's entire speaker configuration
                              // on one undoable tap was the sharper asymmetry.
                              final confirmed =
                                  await showConfirmRemoveZoneDialog(
                                context,
                                zoneName: zone.name,
                              );
                              if (confirmed != true) return;
                              try {
                                await ref
                                    .read(venueRepoProvider)
                                    .removeZone(zoneId);
                              } catch (e) {
                                if (context.mounted) {
                                  showPrismError(context, e);
                                }
                                return;
                              }
                              if (context.mounted) context.go(backTarget);
                            },
                            child: Container(
                              width: double.infinity,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              child: Text('Remove zone',
                                  style: PrismType.button.copyWith(
                                      fontSize: 13, color: palette.red)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
