import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/repositories/playback_repo.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/primary_button.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/seg_toggle.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'active_takeover_screen.dart';

/// The §2 S02-1 hand-back durations, shared with the extend sheet (S02-4).
const takeoverDurations = [
  ('15 mins', '15 minutes', Duration(minutes: 15)),
  ('30 mins', '30 minutes', Duration(minutes: 30)),
  ('1 hour', '1 hour', Duration(hours: 1)),
  ('2 hours', '2 hours', Duration(hours: 2)),
];

/// /takeover — S02-1 when idle; the active S02-2 screen takes over (sic)
/// while a takeover is running.
class TakeoverScreen extends ConsumerStatefulWidget {
  const TakeoverScreen({super.key});

  @override
  ConsumerState<TakeoverScreen> createState() => _TakeoverScreenState();
}

class _TakeoverScreenState extends ConsumerState<TakeoverScreen> {
  var _durationIndex = 1; // frame default: [30 mins]

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(sessionProvider);
    final header = ref.watch(venueHeaderProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects
    final takeover = ref.watch(takeoverStateProvider).value;
    if (takeover != null && takeover.active) {
      return const ActiveTakeoverScreen();
    }

    final palette = Theme.of(context).extension<PrismPalette>()!;
    final (_, longName, duration) = takeoverDurations[_durationIndex];

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
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ① "Use your own audio" (§2 S02-1).
                  const _OptionCard(
                    icon: LucideIcons.headphones,
                    title: 'Use your own audio',
                    sub: 'Plug in a phone, laptop, mixer, or mic. Prism goes '
                        'quiet and the speakers are yours.',
                  ),
                  const SizedBox(height: 12),
                  // ② "Just change the vibe" — the flow was undesigned (§6-B4)
                  // so this card shipped inert. It now returns to Floor, where
                  // the mood grid is: changing the vibe never needed a takeover,
                  // and a card that swallows taps reads as broken.
                  _OptionCard(
                    icon: LucideIcons.music,
                    title: 'Just change the vibe',
                    sub: 'Pick a different mood without handing over the '
                        'speakers.',
                    onTap: () => context.go('/floor'),
                  ),
                  const SizedBox(height: 12),
                  Text('Hand back to Prism after',
                      style: PrismType.label
                          .copyWith(color: palette.textSecondary)),
                  const SizedBox(height: 8),
                  SegToggle(
                    options: [for (final (label, _, _) in takeoverDurations) label],
                    selected: _durationIndex,
                    onChanged: (i) => setState(() => _durationIndex = i),
                  ),
                  const SizedBox(height: 9),
                  Text('Returns automatically after $longName.',
                      style: PrismType.microHelper
                          .copyWith(color: palette.textSecondary)),
                  const SizedBox(height: 12),
                  PrimaryButton(
                    // CTA label not pinned by the README (open_questions).
                    label: 'Start takeover',
                    expanded: true,
                    // S02's primary CTA. Fired-and-dropped, a rejection landed
                    // in the console as an unhandled async error and nothing
                    // reached the screen — staff tap, the speakers stay with
                    // Prism, and nothing says why. `takeover_already_active`
                    // (409, someone else holds the room) is the case that
                    // matters most and was the most invisible.
                    onTap: () async {
                      try {
                        await ref
                            .read(playbackRepoProvider)
                            .startTakeover(handBackAfter: duration);
                      } catch (e) {
                        if (context.mounted) showPrismError(context, e);
                      }
                    },
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

/// S02-1 option card: bg `surface`, border, r14, padding 18; icon + title
/// 14/700 + sub 11.5 `textSecondary`.
class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.icon,
    required this.title,
    this.sub,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? sub;

  /// Null leaves the card inert, as the first one is — it is a description of
  /// what "Start takeover" below will do, not a control of its own.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final card = Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.border),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: palette.textPrimary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: PrismType.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: palette.textPrimary)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub!,
                      style: PrismType.meta.copyWith(
                          fontSize: 11.5, color: palette.textSecondary)),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    // Pressable rather than a bare GestureDetector so a tappable card gets the
    // same 92%-scale press feedback as every other control (§6-A2).
    return onTap == null ? card : Pressable(onTap: onTap, child: card);
  }
}
