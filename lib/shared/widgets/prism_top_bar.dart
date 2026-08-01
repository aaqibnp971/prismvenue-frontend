import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';
import '../../data/models/user.dart';
import '../../app/theme_mode.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'account_menu.dart';
import 'prism_avatar.dart';
import 'prism_icons.dart';
import 'prism_logo.dart';
import 'seg_toggle.dart';

/// Top bar — §2.0: h≈58 (12 v-pad + content), bg `surface`, bottom border 1px
/// `border`. Row padding 12×16, gap 12. Left (flex): logo h26, back button
/// first on sub-screens (30×30, r9, bg `tile`, chevron-left 15). Center
/// (fixed): title 14/700 + status 10 `textSecondary` (6px green dot, gap 5 on
/// main screens). Right (flex, end, gap 10): Dark/Light seg + 32 avatar.
class PrismTopBar extends ConsumerWidget {
  const PrismTopBar({
    super.key,
    required this.title,
    required this.subtitle,
    this.statusDot = false,
    this.showBack = false,
    this.onBack,
    required this.user,
    this.onAvatarTap,
  });

  final String title;

  /// Status ("Main floor · online") on main screens; context ("Settings ·
  /// Sound") on sub-screens.
  final String subtitle;

  /// 6px green dot before the subtitle (main-screen online status).
  final bool statusDot;

  final bool showBack;
  final VoidCallback? onBack;
  final User user;

  /// Overrides the default avatar-tap behavior (account menu → Sign out).
  final VoidCallback? onAvatarTap;

  /// §2.0 h≈58 — used to start modal scrims below the bar (S01-3).
  static const height = 58.0;

  /// §2.0 avatar tap → account menu, anchored below the bar at the right;
  /// "Sign out" clears the session (router redirects to /signin).
  void _showAccountMenu(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: height + 6, right: 16),
          child: Material(
            color: Colors.transparent,
            child: AccountMenu(
              user: user,
              onSignOut: () {
                Navigator.of(dialogContext).pop();
                // Clears session state on this frame (so the router redirects
                // immediately) and discards the stored token in the background.
                ref.read(authControllerProvider).signOut();
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final mode = ref.watch(themeModeProvider);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      child: Row(
        children: [
          // Left (flex): [back] + logo.
          Expanded(
            child: Row(
              children: [
                if (showBack) ...[
                  GestureDetector(
                    onTap: onBack,
                    child: Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: palette.tile,
                        border: Border.all(color: palette.border),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: PrismChevron(
                        direction: ChevronDirection.left,
                        size: 15,
                        color: palette.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                const PrismLogo(height: 26),
              ],
            ),
          ),
          const SizedBox(width: 12), // row gap 12 (§2.0)
          // Center (fixed size).
          Column(
            children: [
              Text(title,
                  style: PrismType.body.copyWith(
                      fontWeight: FontWeight.w700,
                      color: palette.textPrimary)),
              const SizedBox(height: 1),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (statusDot) ...[
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: palette.green, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 5),
                  ],
                  Text(subtitle,
                      style: PrismType.micro.copyWith(
                          fontWeight: FontWeight.w400,
                          color: palette.textSecondary)),
                ],
              ),
            ],
          ),
          const SizedBox(width: 12), // row gap 12 (§2.0)
          // Right (flex, end, gap 10): theme seg + avatar.
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                SegToggle(
                  options: const ['Dark', 'Light'],
                  selected: mode == ThemeMode.dark ? 0 : 1,
                  pill: true,
                  onChanged: (i) => ref
                      .read(themeModeProvider.notifier)
                      .set(i == 0 ? ThemeMode.dark : ThemeMode.light),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: onAvatarTap ?? () => _showAccountMenu(context, ref),
                  child: PrismAvatar(
                      initials: user.initials, color: user.avatarColor),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
