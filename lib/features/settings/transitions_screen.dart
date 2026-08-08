import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/guardrails.dart';
import '../../data/repositories/settings_repo.dart';
import '../../shared/widgets/prism_icons.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// S05-3 "Transition smoothness — how slowly Prism eases between vibes".
/// Radio cards: Seamless (~60s) / [Gentle (~35s) — accent border + check] /
/// Lively (~8s); selected card accentSoft-tinted; footer note.
class TransitionsScreen extends ConsumerWidget {
  const TransitionsScreen({super.key});

  static const _options = [
    (TransitionSmoothness.seamless, 'Seamless', '~60s'),
    (TransitionSmoothness.gentle, 'Gentle', '~35s'),
    (TransitionSmoothness.lively, 'Lively', '~8s'),
  ];

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
    final guardrails =
        ref.watch(guardrailsProvider).value ?? const Guardrails();

    return Scaffold(
      body: Column(
        children: [
          // §2.0: venue name stays in the title slot; context in the 10px
          // line.
          PrismTopBar(
            title: ref.watch(venueNameProvider),
            subtitle: 'Settings · Sound',
            showBack: true,
            onBack: () => context.go('/settings'),
            user: user,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: SizedBox(
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Transition smoothness',
                        style: PrismType.displaySerif.copyWith(
                            fontSize: 22, color: palette.textPrimary)),
                    const SizedBox(height: 14),
                    for (final (mode, name, duration) in _options) ...[
                      _RadioCard(
                        name: name,
                        duration: duration,
                        selected: guardrails.transition == mode,
                        onTap: () => ref
                            .read(settingsRepoProvider)
                            .updateGuardrails(
                                guardrails.copyWith(transition: mode)),
                      ),
                      const SizedBox(height: 10),
                    ],
                    // Footer-note copy is not pinned (open_questions).
                    Text(
                        'Applies to every vibe change, including schedule '
                        'switches.',
                        style: PrismType.microHelper
                            .copyWith(color: palette.textSecondary)),
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

class _RadioCard extends StatelessWidget {
  const _RadioCard({
    required this.name,
    required this.duration,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String duration;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
        decoration: BoxDecoration(
          color: selected ? palette.accentSoft : palette.surface,
          border:
              Border.all(color: selected ? palette.accent : palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(name,
                  style:
                      PrismType.bodySm.copyWith(color: palette.textPrimary)),
            ),
            Text(duration,
                style: PrismType.label.copyWith(
                    fontSize: 12.5, color: palette.textSecondary)),
            if (selected) ...[
              const SizedBox(width: 10),
              PrismCheck(size: 15, color: palette.accent),
            ],
          ],
        ),
      ),
    );
  }
}
