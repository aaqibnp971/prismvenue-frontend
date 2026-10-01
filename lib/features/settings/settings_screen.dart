import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/roles.dart';
import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/guardrails.dart';
import '../../data/models/timezone.dart';
import '../../data/models/venue.dart';
import '../../data/repositories/playback_repo.dart';
import '../../data/repositories/settings_repo.dart';
import '../../data/repositories/venue_repo.dart';
import '../../app/theme_mode.dart';
import '../../shared/widgets/prism_dropdown_menu.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/settings_row.dart';
import 'confirm_apply_to_all_dialog.dart';
import 'zone_picker_sheet.dart';
import 'change_password_sheet.dart';
import '../../shared/widgets/prism_toast.dart';
import 'venue_text_sheet.dart';
import 'confirm_remove_venue_dialog.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'timezone_sheet.dart';

/// S05-1 "Settings — Sound & Access guardrails (scrolls for more)".
/// Title "Settings" 22 serif + "Marina Café · you're a manager" sub; grouped
/// SettingsRows (group label = labelCaps with icon): Sound / Access / Place /
/// Alerts / Appearance. Rows open S05-2…S05-9 (screens or anchored
/// dropdowns).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A guardrail write that fails reverts the optimistic value, and the revert
    // used to be the only signal. Fine for a volume slider; not for "Who can
    // take over", where a manager sets it, watches it flip back and is told
    // nothing. One listener rather than nine try/catches -- updateGuardrails is
    // fire-and-forget by design at every call site.
    ref.listen<AsyncValue<Object>>(guardrailFailureProvider, (_, next) {
      final error = next.value;
      if (error != null && context.mounted) showPrismError(context, error);
    });

    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final guardrails = ref.watch(guardrailsProvider).value ?? const Guardrails();
    final hours = ref.watch(openHoursProvider).value;
    final header = ref.watch(venueHeaderProvider);
    final venueId = ref.watch(currentVenueIdProvider);
    final venue =
        venueId == null ? null : ref.watch(venueProvider(venueId)).value;
    final themeMode = ref.watch(themeModeProvider);

    // "you're a manager" is the pinned manager copy; owner variant derived.
    final roleLine =
        user.role == Role.owner ? "you're the owner" : "you're a manager";

    return Scaffold(
      body: Column(
        children: [
          PrismTopBar(
            title: header.title,
            subtitle: header.subtitle,
            statusDot: header.statusDot,
            user: user,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Settings',
                      style: PrismType.body.copyWith(
                          fontFamily: PrismType.displaySerif.fontFamily,
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary)),
                  const SizedBox(height: 3),
                  Text('${header.title} · $roleLine',
                      style: PrismType.label.copyWith(
                          fontWeight: FontWeight.w400,
                          color: palette.textSecondary)),
                  const SizedBox(height: 16),
                  _Group(
                    icon: LucideIcons.volume2,
                    label: 'SOUND',
                    children: [
                      SettingsRow(
                        title: 'Volume policy',
                        value: guardrails.bandLabel,
                        onTap: () => context.go('/settings/volume'),
                      ),
                      SettingsRow(
                        title: 'Transition smoothness',
                        value: guardrails.transitionLabel,
                        onTap: () => context.go('/settings/transitions'),
                      ),
                    ],
                  ),
                  _Group(
                    icon: LucideIcons.speaker,
                    label: 'THIS ZONE',
                    children: [
                      SettingsRow(
                        title: 'Settings apply to',
                        // Finding #10: the page is headed with the venue name,
                        // and the volume band, transitions and takeover access
                        // are all stored per zone. An owner changed the band
                        // believing it covered the venue. The chip said "This
                        // zone" without ever naming which.
                        value: ref.watch(sessionContextProvider)?.zoneName ?? 'No zone',
                        onTap: venue == null || venue.zones.length < 2
                            ? null
                            : () => _switchZone(context, ref, venue),
                      ),
                      if (venue != null && venue.zones.length > 1)
                        SettingsRow(
                          title: 'Apply to all zones',
                          value: '${venue.zones.length} zones',
                          onTap: () =>
                              _applyToAllZones(context, ref, venue, guardrails),
                        ),
                    ],
                  ),
                  _Group(
                    icon: LucideIcons.volume2,
                    label: 'THIS DEVICE',
                    children: [
                      _PlaysHereRow(zoneName: header.subtitle),
                    ],
                  ),
                  _Group(
                    icon: LucideIcons.lock,
                    label: 'ACCESS',
                    children: [
                      _DropdownRow(
                        title: 'Who can take over',
                        value: guardrails.takeoverAccessLabel,
                        options: const ['Manager', 'Manager + Floor'],
                        selected: guardrails.takeoverAccess ==
                                TakeoverAccess.managers
                            ? 0
                            : 1,
                        onSelect: (i) => ref
                            .read(settingsRepoProvider)
                            .updateGuardrails(guardrails.copyWith(
                                takeoverAccess: i == 0
                                    ? TakeoverAccess.managers
                                    : TakeoverAccess.managersPlusFloor)),
                      ),
                    ],
                  ),
                  _Group(
                    icon: LucideIcons.userRound,
                    label: 'ACCOUNT',
                    children: [
                      // Finding #17: the avatar menu offered only Sign out, so
                      // a member of staff could not see which account they
                      // were on, and could only change a password by
                      // pretending to have forgotten it.
                      SettingsRow(
                        title: 'Signed in as',
                        value: user.email ?? user.name,
                        chevron: false,
                      ),
                      SettingsRow(
                        title: 'Role',
                        value: switch (user.role) {
                          Role.owner => 'Owner',
                          Role.manager => 'Manager',
                          Role.floor => 'Floor',
                        },
                        chevron: false,
                      ),
                      SettingsRow(
                        title: 'Change password',
                        value: '',
                        onTap: () async {
                          final changed = await showChangePasswordSheet(context);
                          if (changed == true && context.mounted) {
                            showPrismToast(context, 'Password changed');
                          }
                        },
                      ),
                      // Sign out deliberately NOT repeated here. The
                      // avatar menu already owns it, and on a narrow screen it
                      // is the only route to it — two controls for one action
                      // is the thing CLAUDE.md names as a bug, and the report
                      // asked for this section because email, role and a
                      // password change had nowhere to live, not because
                      // signing out was hard to find.
                    ],
                  ),
                  _Group(
                    icon: LucideIcons.mapPin,
                    label: 'PLACE',
                    children: [
                      SettingsRow(
                        title: 'Zones & open hours',
                        // A dash, not "2 · 7am–11pm". Those were frame sample
                        // values standing in for data that had not arrived, so
                        // a venue with four zones and a late close read as two
                        // zones closing at 11 until the fetch landed — and if
                        // it never landed, indefinitely.
                        value: venue == null || hours == null
                            ? '—'
                            : '${venue.zones.length} · ${hours.rangeLabel}',
                        onTap: () => context.go('/settings/hours'),
                      ),
                      SettingsRow(
                        title: 'Venue name',
                        // Finding #8: there was no way to fix a typo in a
                        // venue's name, ever. The write path existed for zones
                        // and not for the venue they sit in.
                        value: venue?.name ?? '—',
                        onTap: venueId == null || venue == null
                            ? null
                            : () => _editVenueText(
                                  context,
                                  ref,
                                  venueId: venueId,
                                  title: 'Venue name',
                                  initial: venue.name,
                                  isName: true,
                                ),
                      ),
                      SettingsRow(
                        title: 'Address',
                        value: (venue?.address?.isNotEmpty ?? false)
                            ? venue!.address!
                            : 'Not set',
                        onTap: venueId == null || venue == null
                            ? null
                            : () => _editVenueText(
                                  context,
                                  ref,
                                  venueId: venueId,
                                  title: 'Address',
                                  initial: venue.address ?? '',
                                  isName: false,
                                ),
                      ),
                      SettingsRow(
                        title: 'Time zone',
                        // Says out loud when the venue's clock is not the one
                        // the manager is reading. This is the whole failure in
                        // one line: a daypart typed at 10pm on a device in
                        // India runs at 10pm in the Gulf, and every screen
                        // looked right while the room ignored the plan for
                        // ninety minutes. Only shown on a mismatch — a venue
                        // that agrees with the device needs no commentary.
                        sub: venue?.localTime == null ||
                                venue!.localTime == _deviceClock()
                            ? null
                            : 'This device says ${_deviceClock()}',
                        // The venue's own wall clock beside the zone name, and
                        // it is the reason this row exists. `venues.timezone`
                        // decides which daypart is current — nothing else does
                        // — and it was invisible and unset, so a plan typed at
                        // 10pm here ran on some other country's 10pm with no
                        // way to notice. Seeing "Asia/Dubai · 20:58" while your
                        // own clock reads 22:28 answers it instantly.
                        value: venue?.timezone == null
                            ? '—'
                            : venue!.localTime == null
                                ? venue.timezone!
                                : '${venue.timezone} · ${venue.localTime}',
                        onTap: venueId == null
                            ? null
                            : () => _pickTimezone(context, ref, venueId, venue),
                      ),
                      // Owners only, and last in the group: it is the one row
                      // here that removes something. Test venues like "0000"
                      // and "Test_Venue" had no way out of a live portfolio
                      // before this.
                      if (user.role == Role.owner)
                        SettingsRow(
                          title: 'Remove this venue',
                          value: '',
                          onTap: venueId == null || venue == null
                              ? null
                              : () =>
                                  _archiveVenue(context, ref, venueId, venue),
                        ),
                    ],
                  ),
                  _Group(
                    icon: LucideIcons.bell,
                    label: 'ALERTS',
                    children: [
                      _DropdownRow(
                        title: 'Venue / zone offline',
                        value: Guardrails
                            .offlineAlertOptions[guardrails.offlineAlertIndex],
                        options: Guardrails.offlineAlertOptions,
                        selected: guardrails.offlineAlertIndex,
                        onSelect: (i) => ref
                            .read(settingsRepoProvider)
                            .updateGuardrails(
                                guardrails.copyWith(offlineAlertIndex: i)),
                      ),
                      _DropdownRow(
                        title: 'Left in takeover too long',
                        value: Guardrails.takeoverAlertOptions[
                            guardrails.takeoverAlertIndex],
                        options: Guardrails.takeoverAlertOptions,
                        selected: guardrails.takeoverAlertIndex,
                        onSelect: (i) => ref
                            .read(settingsRepoProvider)
                            .updateGuardrails(
                                guardrails.copyWith(takeoverAlertIndex: i)),
                      ),
                    ],
                  ),
                  _Group(
                    icon: LucideIcons.sunMoon,
                    label: 'APPEARANCE',
                    children: [
                      // S05-9: dropdown anchored to the top-bar theme seg.
                      _DropdownRow(
                        title: 'Appearance',
                        value: switch (themeMode) {
                          ThemeMode.dark => 'Dark',
                          ThemeMode.light => 'Light',
                          ThemeMode.system => 'System device',
                        },
                        options: const ['Dark', 'Light', 'System device'],
                        selected: switch (themeMode) {
                          ThemeMode.dark => 0,
                          ThemeMode.light => 1,
                          ThemeMode.system => 2,
                        },
                        anchorTopBar: true,
                        onSelect: (i) =>
                            ref.read(themeModeProvider.notifier).set(const [
                          ThemeMode.dark,
                          ThemeMode.light,
                          ThemeMode.system,
                        ][i]),
                      ),
                    ],
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

class _Group extends StatelessWidget {
  const _Group(
      {required this.icon, required this.label, required this.children});

  final IconData icon;
  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 13, color: palette.textSecondary),
            const SizedBox(width: 6),
            Text(label,
                style:
                    PrismType.labelCaps.copyWith(color: palette.textSecondary)),
          ],
        ),
        const SizedBox(height: 8),
        for (final child in children) ...[
          child,
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

/// This machine's wall clock, "HH:MM", to compare against the venue's.
///
/// Read at build time rather than ticked: the row is a settings entry, not a
/// clock, and it only has to be right to the minute someone looks at it.
String _deviceClock() => DeviceOffsets.currentClock();

/// Loads the zone list, opens the picker, and writes the choice.
///
/// The list is fetched on tap rather than held in a provider: it is ~600 rows
/// that change once a year and are needed on one screen, so keeping it warm
/// would cost more than fetching it. A failed fetch reports and opens nothing,
/// because a picker with an empty list looks like a venue with no zones to
/// choose from.
Future<void> _pickTimezone(
  BuildContext context,
  WidgetRef ref,
  String venueId,
  Venue? venue,
) async {
  final repo = ref.read(venueRepoProvider);
  List<TimezoneOption> options;
  try {
    options = await repo.listTimezones();
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
    return;
  }
  if (!context.mounted) return;

  final picked = await showTimezoneSheet(
    context,
    options: options,
    selected: venue?.timezone,
  );
  if (picked == null || picked == venue?.timezone) return;

  try {
    await repo.setTimezone(venueId, picked);
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
  }
}

/// SettingsRow whose tap opens the §3 DropdownMenu as an anchored overlay
/// (S05-4/7/8; S05-9 anchors to the top-bar seg instead).
class _DropdownRow extends StatelessWidget {
  const _DropdownRow({
    required this.title,
    required this.value,
    required this.options,
    required this.selected,
    required this.onSelect,
    this.anchorTopBar = false,
  });

  final String title;
  final String value;
  final List<String> options;
  final int selected;
  final ValueChanged<int> onSelect;
  final bool anchorTopBar;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (rowContext) => SettingsRow(
        title: title,
        value: value,
        onTap: () async {
          final picked = await _showAnchoredDropdown(
            rowContext,
            options: options,
            selected: selected,
            anchorTopBar: anchorTopBar,
          );
          if (picked != null && picked != selected) onSelect(picked);
        },
      ),
    );
  }
}

Future<int?> _showAnchoredDropdown(
  BuildContext anchorContext, {
  required List<String> options,
  required int selected,
  bool anchorTopBar = false,
}) {
  // Anchor below the tapped row's right edge (or below the top-bar seg for
  // S05-9). Exact popover geometry is not pinned (open_questions).
  var top = PrismTopBar.height + 6.0;
  var right = 62.0;
  if (!anchorTopBar) {
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box != null) {
      final origin = box.localToGlobal(Offset.zero);
      top = origin.dy + box.size.height + 4;
      right = 15 + 8; // screen padding + row inset
    }
  }
  // Clamp to the screen. Anchoring took the row's global offset with no bounds
  // check, and the Alerts rows sit low on the Settings list -- on a short window
  // their menus rendered partly off-screen, with the options you most need to
  // reach being the ones past the edge.
  //
  // Measured against the anchor's own view rather than a MediaQuery from the
  // dialog, which is not built yet.
  final view = View.of(anchorContext);
  final screenHeight = view.physicalSize.height / view.devicePixelRatio;
  // PrismDropdownMenu is 44px per row plus 8px of padding; near enough to keep
  // the whole menu on screen without reaching into its internals.
  final menuHeight = options.length * 44.0 + 8;
  const bottomInset = 12.0;
  if (top + menuHeight > screenHeight - bottomInset) {
    // Flip above the row when there is no room below.
    top = (top - menuHeight - 8 - 4).clamp(PrismTopBar.height + 6.0, top);
  }

  return showDialog<int>(
    context: anchorContext,
    barrierColor: Colors.transparent,
    builder: (dialogContext) => Stack(
      children: [
        Positioned(
          top: top,
          right: right,
          child: Material(
            color: Colors.transparent,
            child: PrismDropdownMenu(
              options: options,
              selected: selected,
              onSelect: (i) => Navigator.of(dialogContext).pop(i),
            ),
          ),
        ),
      ],
    ),
  );
}

/// "This device plays Main floor" — finding #2.
///
/// The engine used to sound wherever somebody was signed in, so an owner
/// opening the app at home started their clinic's music on their phone, and
/// two iPads in one room played over each other a few hundred milliseconds
/// apart. One device holds a room; everything else is a remote control.
///
/// **Off by default, deliberately.** A device must never begin driving a room
/// because somebody signed in on it. The cost is that a freshly installed
/// venue plays nowhere until somebody says which tablet is the speaker, so the
/// row states that in as many words rather than sitting quietly on "Off".
///
/// It lives in Settings rather than on Floor because it is a property of this
/// installation, set once when a tablet is mounted, and not something anybody
/// should be flipping mid-service.
class _PlaysHereRow extends ConsumerWidget {
  const _PlaysHereRow({required this.zoneName});

  final String zoneName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = ref.watch(nowPlayingProvider).value;
    final playsHere = now?.playsHere ?? false;
    final someoneElse = !playsHere && now?.playerInstallationId != null;

    return SettingsRow(
      title: 'This device plays $zoneName',
      // Three states, not two. "Another device is playing it" and "nothing is"
      // need different actions from whoever is reading.
      value: playsHere
          ? 'On'
          : someoneElse
              ? 'Another device'
              : 'No device is playing',
      onTap: () async {
        try {
          await ref.read(playbackRepoProvider).setThisDevicePlays(!playsHere);
        } catch (e) {
          if (context.mounted) showPrismError(context, e);
        }
      },
    );
  }
}


/// Edit a venue's name or address (finding #8).
///
/// One helper for both: they differ in whether empty is allowed and in the
/// helper line, and two near-identical paths would drift.
Future<void> _editVenueText(
  BuildContext context,
  WidgetRef ref, {
  required String venueId,
  required String title,
  required String initial,
  required bool isName,
}) async {
  final value = await showVenueTextSheet(
    context,
    title: title,
    label: title,
    initial: initial,
    // A venue with no address is legitimate; a venue with no name is not.
    allowEmpty: !isName,
    helper: isName
        ? null
        : "Used to find the venue's weather, which colours the sound.",
  );
  if (value == null || !context.mounted) return;

  try {
    await ref.read(venueRepoProvider).updateVenue(
          venueId,
          name: isName ? value : null,
          address: isName || value.isEmpty ? null : value,
          // An empty address is a deliberate clear, not an omission.
          clearAddress: !isName && value.isEmpty,
        );
    if (context.mounted) showPrismToast(context, 'Saved');
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
  }
}

/// Archive a venue, after asking.
Future<void> _archiveVenue(
  BuildContext context,
  WidgetRef ref,
  String venueId,
  Venue venue,
) async {
  final confirmed =
      await showConfirmRemoveVenueDialog(context, venueName: venue.name);
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(venueRepoProvider).archiveVenue(venueId);
    if (context.mounted) {
      showPrismToast(context, '${venue.name} removed');
      // Settings is scoped to a venue that no longer exists, so staying here
      // would show a screen about nothing.
      context.go('/venues');
    }
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
  }
}


/// Move Settings (and Floor, and Schedule) to another room — finding #10.
///
/// Reuses `operateZone`, the one control in the app that changes which room is
/// being operated, rather than inventing a settings-only notion of "current
/// zone" that the rest of the app would not share.
Future<void> _switchZone(
  BuildContext context,
  WidgetRef ref,
  Venue venue,
) async {
  final picked = await showZonePickerSheet(context, venue: venue);
  if (picked == null || !context.mounted) return;

  ref.read(sessionContextProvider.notifier).operateZone(
        venueId: venue.id,
        venueName: venue.name,
        zoneId: picked.id,
        zoneName: picked.name,
      );
  if (context.mounted) showPrismToast(context, 'Now showing ${picked.name}');
}

/// Copy this zone's guardrails to every other room in the venue — finding #10.
///
/// Asks first and names the count, because it is the one control here that
/// changes rooms the person is not looking at.
Future<void> _applyToAllZones(
  BuildContext context,
  WidgetRef ref,
  Venue venue,
  Guardrails guardrails,
) async {
  final confirmed = await showConfirmApplyToAllDialog(
    context,
    zoneCount: venue.zones.length,
    venueName: venue.name,
  );
  if (confirmed != true || !context.mounted) return;

  try {
    await ref.read(settingsRepoProvider).applyGuardrailsToVenue(
          venue.id,
          [for (final z in venue.zones) z.id],
          guardrails,
        );
    if (context.mounted) {
      showPrismToast(context, 'Applied to ${venue.zones.length} zones');
    }
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
  }
}
