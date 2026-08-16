import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/session.dart';
import '../../data/models/timezone.dart';
import '../../data/repositories/venue_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/prism_field.dart';
import '../../shared/widgets/prism_icons.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import '../settings/timezone_sheet.dart';
import 'add_zone_sheet.dart';

/// S04-3 "Add a venue — owner onboards a new location into the estate".
/// Form: Venue name, Home address (two-col), Open hours (S05-6 pattern),
/// zone chips + "+ Add zone" → S04-4. CTA "Add venue".
class AddVenueScreen extends ConsumerStatefulWidget {
  const AddVenueScreen({super.key});

  @override
  ConsumerState<AddVenueScreen> createState() => _AddVenueScreenState();
}

class _AddVenueScreenState extends ConsumerState<AddVenueScreen> {
  final _name = TextEditingController();
  final _street = TextEditingController();
  final _city = TextEditingController();
  final _zones = <String>[];

  /// The clock this venue's schedule will run on.
  ///
  /// Asked at creation rather than only inferred, because it is the single
  /// field that decides when every daypart fires and it is invisible
  /// afterwards unless somebody goes looking. Left unset it took the column
  /// default, which is how nine venues ended up on one arbitrary zone and every
  /// schedule fired at the wrong hour.
  ///
  /// Pre-filled from THIS device — a venue is usually set up from somewhere
  /// near it — so the common case is confirm-and-move-on rather than a search.
  /// Null only while the list is loading, or if it failed to load; the create
  /// call then falls back to sending the device's raw offsets, which the server
  /// resolves the same way.
  String? _timezone;
  List<TimezoneOption> _timezoneOptions = const [];

  @override
  void initState() {
    super.initState();
    _loadTimezones();
  }

  Future<void> _loadTimezones() async {
    try {
      final options = await ref.read(venueRepoProvider).listTimezones();
      if (!mounted) return;
      final offset = DeviceOffsets.currentMinutes();
      final match = options.where((o) => o.utcOffsetMinutes == offset);
      setState(() {
        _timezoneOptions = options;
        _timezone = match.isEmpty ? null : match.first.name;
      });
    } catch (_) {
      // Silent: the field shows "Use this device's clock" and the create call
      // sends offsets instead. A venue form must not fail because a reference
      // list did not load.
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _street.dispose();
    _city.dispose();
    super.dispose();
  }

  Future<void> _addZone() async {
    final zoneName = await showAddZoneSheet(context);
    if (zoneName != null && zoneName.trim().isNotEmpty) {
      setState(() => _zones.add(zoneName.trim()));
    }
  }

  String? _error;

  /// Guards the double-submit. Each tap mints a fresh idempotency key, so two
  /// taps on a slow network are two distinct requests — and a recovered
  /// connection then creates the venue twice.
  bool _saving = false;

  Future<void> _submit() async {
    if (_saving) return;
    final name = _name.text.trim();
    // Silently returning made the CTA read as broken rather than as a
    // validation message.
    if (name.isEmpty) {
      setState(() => _error = 'Give the venue a name.');
      return;
    }

    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      await ref.read(venueRepoProvider).addVenue(
            name: name,
            address: [_street.text.trim(), _city.text.trim()]
                .where((s) => s.isNotEmpty)
                .join(', '),
            zoneNames: _zones,
            timezone: _timezone,
            // This machine's own clock, which is the closest thing to a right
            // answer available at creation time — a venue is usually set up
            // from somewhere near it. Without it the column default stands,
            // which is how every existing venue ended up on one arbitrary zone
            // and every schedule fired at the wrong hour. Correctable
            // afterwards in Settings; the point is that it starts sane rather
            // than starting wrong and silent.
            deviceOffsets: DeviceOffsets.fromDevice(),
          );
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = messageFor(e);
          _saving = false;
        });
      }
      return;
    }
    if (mounted) context.go('/venues');
  }

  Future<void> _pickTimezone() async {
    final picked = await showTimezoneSheet(context,
        options: _timezoneOptions, selected: _timezone);
    if (picked != null && mounted) setState(() => _timezone = picked);
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects
    final palette = Theme.of(context).extension<PrismPalette>()!;

    return Scaffold(
      body: Column(
        children: [
          PrismTopBar(
            title: 'Add a venue',
            subtitle: 'New location',
            showBack: true,
            onBack: () => context.go('/venues'),
            user: user,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 420,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        PrismField(label: 'Venue name', controller: _name),
                        const SizedBox(height: 14),
                        // "Home address (two-col)" — field split derived.
                        Text('Home address',
                            style: PrismType.label
                                .copyWith(color: palette.textSecondary)),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            Expanded(
                                child: PrismField(
                                    hint: 'Street', controller: _street)),
                            const SizedBox(width: 10),
                            Expanded(
                                child: PrismField(
                                    hint: 'City', controller: _city)),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text('Time zone',
                            style: PrismType.label
                                .copyWith(color: palette.textSecondary)),
                        const SizedBox(height: 7),
                        Pressable(
                          onTap: _timezoneOptions.isEmpty ? null : _pickTimezone,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                vertical: 13, horizontal: 15),
                            decoration: BoxDecoration(
                              color: palette.surface,
                              border: Border.all(color: palette.border),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                Icon(LucideIcons.globe,
                                    size: 15, color: palette.accent),
                                const SizedBox(width: 9),
                                Expanded(
                                  child: Text(
                                    _timezone ?? "This device's clock",
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PrismType.bodySm.copyWith(
                                        fontSize: 13,
                                        color: palette.textPrimary),
                                  ),
                                ),
                                Text('Change',
                                    style: PrismType.microHelper
                                        .copyWith(color: palette.accentText)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Every daypart you plan runs on this clock. It is '
                          'the venue’s, not yours.',
                          style: PrismType.microHelper
                              .copyWith(color: palette.textSecondary),
                        ),
                        const SizedBox(height: 14),
                        // Open hours row (S05-6 pattern); editing lands with
                        // Section 05.
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 13, horizontal: 15),
                          decoration: BoxDecoration(
                            color: palette.surface,
                            border: Border.all(color: palette.border),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Open hours',
                                        style: PrismType.body.copyWith(
                                            fontSize: 13.5,
                                            fontWeight: FontWeight.w600,
                                            color: palette.textPrimary)),
                                    const SizedBox(height: 3),
                                    Text('Every day · 7am–11pm',
                                        style: PrismType.label.copyWith(
                                            fontWeight: FontWeight.w400,
                                            color: palette.textSecondary)),
                                  ],
                                ),
                              ),
                              PrismChevron(
                                  direction: ChevronDirection.right,
                                  size: 15,
                                  color: palette.textTertiary),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text('Zones',
                            style: PrismType.label
                                .copyWith(color: palette.textSecondary)),
                        const SizedBox(height: 7),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final zone in _zones)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: palette.tile,
                                  border: Border.all(color: palette.border),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(zone,
                                    style: PrismType.bodySm.copyWith(
                                        fontSize: 12,
                                        color: palette.textPrimary)),
                              ),
                            GestureDetector(
                              onTap: _addZone,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 12),
                                decoration: BoxDecoration(
                                  color: palette.accentSoft,
                                  border: Border.all(color: palette.accent),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text('+ Add zone',
                                    style: PrismType.bodySm.copyWith(
                                        fontSize: 12,
                                        color: palette.accentText)),
                              ),
                            ),
                          ],
                        ),
                        ErrorNote(message: _error),
                        const SizedBox(height: 22),
                        PrimaryButton(
                            label: _saving ? 'Adding…' : 'Add venue',
                            expanded: true,
                            // Null while in flight: the guard in _submit is the
                            // real protection, this is what makes it visible.
                            onTap: _saving ? null : _submit),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
