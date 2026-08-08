import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/roles.dart';
import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/guardrails.dart';
import '../../data/repositories/settings_repo.dart';
import '../../data/repositories/venue_repo.dart';
import '../../app/theme_mode.dart';
import '../../shared/widgets/prism_dropdown_menu.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/settings_row.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

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
