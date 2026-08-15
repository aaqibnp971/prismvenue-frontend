import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// The 5 fixed tabs — §2.0 (Team was removed; do not add).
enum NavTab { floor, takeover, schedule, venues, settings }

/// Bottom nav — §2.0: bg `surface`, top border 1px `border`, padding 9×14,
/// gap 4. Item: expanded column, icon 20 + label 11, gap 5, padding 8×4, r14.
/// Active: bg `accentSoft`, `accentText`, label 700. Inactive:
/// `textSecondary`, label 600. Locked: `textTertiary`, icon 60% opacity,
/// label prefixed with a 9px lock glyph; taps inert (§6-A5).
class PrismBottomNav extends StatelessWidget {
  const PrismBottomNav({
    super.key,
    required this.active,
    this.lockedTabs = const {},
    this.onSelect,
  });

  final NavTab active;
  final Set<NavTab> lockedTabs;
  final ValueChanged<NavTab>? onSelect;

  // Icon mapping: §1.8 sanctions Lucide; exact glyph names aren't in the
  // README — eyeball via /_gallery (see open_questions.md).
  static const _items = [
    (NavTab.floor, 'Floor', LucideIcons.music),
    (NavTab.takeover, 'Takeover', LucideIcons.headphones),
    (NavTab.schedule, 'Schedule', LucideIcons.calendar),
    (NavTab.venues, 'Venues', LucideIcons.mapPin),
    (NavTab.settings, 'Settings', LucideIcons.settings),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;

    Widget item((NavTab, String, IconData) entry) {
      final (tab, label, icon) = entry;
      final isActive = tab == active;
      final locked = lockedTabs.contains(tab);
      final color = locked
          ? palette.textTertiary
          : isActive
              ? palette.accentText
              : palette.textSecondary;
      return Expanded(
        child: GestureDetector(
          // Locked taps are inert — no toast/dialog designed (§6-A5).
          onTap: locked || onSelect == null ? null : () => onSelect!(tab),
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            decoration: BoxDecoration(
              color: isActive && !locked ? palette.accentSoft : null,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: locked ? .6 : 1,
                  child: Icon(icon, size: 20, color: color),
                ),
                const SizedBox(height: 5),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (locked) ...[
                      Icon(LucideIcons.lock, size: 9, color: color),
                      const SizedBox(width: 3),
                    ],
                    // Flexible + ellipsis: four or five tabs across a 320pt
                    // phone leaves each about 60pt, and "Schedule" beside a
                    // lock glyph does not fit. The icon above carries the
                    // meaning; a clipped word beside a striped banner does not.
                    Flexible(
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: PrismType.label.copyWith(
                          fontWeight: isActive && !locked
                              ? FontWeight.w700
                              : FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            item(_items[i]),
          ],
        ],
      ),
    );
  }
}
