import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/takeover_state.dart';
import '../../data/repositories/playback_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/secondary_button.dart';
import '../../theme/moods.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'confirm_return_dialog.dart';
import 'extend_sheet.dart';

/// S02-2 "Active takeover — Prism is holding the room; return now or extend".
///
/// Built to the frame: amber banner ("You're in control" / "Prism is handed
/// off · playing from your device"), centered "Prism returns in" + countdown
/// + reassurance line, stacked full-width CTAs ("Return to Prism now" with the
/// rotate glyph, then "Running long? Extend" with the clock), the device-note
/// info card, and the "Started by …" footer.
///
/// With auto-return removed (S02-4) there is no frame, so that state is
/// derived: the countdown becomes elapsed time counting UP — which is what
/// the "left in takeover too long" alert cares about — and Extend is hidden,
/// since there is no deadline left to push.
class ActiveTakeoverScreen extends ConsumerWidget {
  const ActiveTakeoverScreen({super.key});

  /// "12 min ago" — the footer's elapsed style.
  static String _elapsedLabel(DateTime startedAt) {
    final elapsed = DateTime.now().difference(startedAt);
    if (elapsed.inMinutes < 1) return 'just now';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes} min ago';
    return '${elapsed.inHours} hr ${elapsed.inMinutes % 60} min ago';
  }

  /// "Priya Nair" → "Priya N", matching the frame's footer. A single-word
  /// name passes through untouched.
  static String _shortName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length < 2) return name.trim();
    return '${parts.first} ${parts[1][0]}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    final header = ref.watch(venueHeaderProvider);
    final takeover = ref.watch(takeoverStateProvider).value;
    if (user == null || takeover == null || !takeover.active) {
      return const SizedBox.shrink(); // TakeoverScreen switches back
    }
    final palette = Theme.of(context).extension<PrismPalette>()!;

    final startedAt = takeover.startedAt;
    final footerParts = [
      if (takeover.startedByName != null)
        'Started by ${_shortName(takeover.startedByName!)}'
      else
        'Started',
      if (startedAt != null) _elapsedLabel(startedAt),
      'Prism moods paused',
    ];

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
            child: Padding(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Amber banner — bg amber@12%, border amber@34%, r13.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: palette.amber.withValues(alpha: .12),
                      border: Border.all(
                          color: palette.amber.withValues(alpha: .34)),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: palette.amber,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("You're in control",
                                  style: PrismType.bodySm.copyWith(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w700,
                                      color: palette.amber)),
                              const SizedBox(height: 2),
                              Text(
                                  'Prism is handed off · playing from your '
                                  'device',
                                  style: PrismType.meta.copyWith(
                                      fontSize: 11.5,
                                      color: palette.amber
                                          .withValues(alpha: .85))),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Countdown block, centered in the remaining space.
                  Expanded(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            takeover.hasAutoReturn
                                ? 'Prism returns in'
                                : 'Auto-return is off',
                            style: PrismType.label.copyWith(
                                fontWeight: FontWeight.w400,
                                color: palette.textSecondary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            takeover.hasAutoReturn
                                ? takeover.countdownLabel
                                : (startedAt == null
                                    ? '—'
                                    : TakeoverState.formatDuration(
                                        DateTime.now()
                                            .difference(startedAt))),
                            style: PrismType.numeralHuge
                                .copyWith(color: palette.amber),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            takeover.hasAutoReturn
                                ? 'It hands back on its own — or bring it '
                                    'back anytime.'
                                : 'Bring Prism back when you\'re done.',
                            textAlign: TextAlign.center,
                            style: PrismType.bodySm.copyWith(
                                fontSize: 12.5,
                                color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  PrimaryButton(
                    expanded: true,
                    icon: Icon(LucideIcons.rotateCcw,
                        size: 16, color: palette.chipInk),
                    label: 'Return to Prism now',
                    onTap: () => _confirmReturn(context, ref),
                  ),
                  if (takeover.hasAutoReturn) ...[
                    const SizedBox(height: 10),
                    SecondaryButton(
                      expanded: true,
                      icon: Icon(LucideIcons.clock,
                          size: 16, color: palette.textSecondary),
                      // The sheet moves the deadline both ways now, so the
                      // frame's "Running long? Extend" only described half of
                      // it — and the half it hid is the one staff would never
                      // have gone looking for behind that label.
                      label: 'Running long or done early? Adjust',
                      onTap: () => showExtendSheet(context, ref),
                    ),
                  ],
                  const SizedBox(height: 12),
                  // Device note — the volume answer staff will look for here.
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: palette.border),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        Icon(LucideIcons.info,
                            size: 14, color: palette.textSecondary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Volume and playback are on your own device or '
                            'mixer — not here. Prism is just holding the '
                            'room for you.',
                            style: PrismType.meta.copyWith(
                                fontSize: 11.5,
                                color: palette.textSecondary),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    footerParts.join(' · '),
                    textAlign: TextAlign.center,
                    style: PrismType.meta.copyWith(
                        fontSize: 11, color: palette.textSecondary),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmReturn(BuildContext context, WidgetRef ref) async {
    final moodId =
        ref.read(nowPlayingProvider).value?.moodId ?? 'afternoon-lift';
    final confirmed =
        await showConfirmReturnDialog(context, currentMood: moodById(moodId));
    if (confirmed != true) return;
    try {
      await ref.read(playbackRepoProvider).endTakeover();
    } catch (e) {
      if (context.mounted) showPrismError(context, e);
      return;
    }
    if (context.mounted) context.go('/floor'); // §4: confirm-return → floor
  }
}
