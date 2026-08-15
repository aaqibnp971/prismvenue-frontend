import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/guardrails.dart';
import '../../data/repositories/settings_repo.dart';
import '../../shared/widgets/prism_toggle.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/pressable.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/seg_toggle.dart';
import '../../shared/widgets/settings_row.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// S05-2 "Volume policy — the output band, daypart curve & floor-staff
/// leeway". Title + "This zone" scope chip (single option); band sliders
/// (track h6 r999 `tile2`, accent fill, 14 white thumb); quiet-hours row
/// with toggle; "Floor staff can" seg + helper.
class VolumePolicyScreen extends ConsumerWidget {
  const VolumePolicyScreen({super.key});

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
    final repo = ref.read(settingsRepoProvider);

    return Scaffold(
      body: Column(
        children: [
          // §2.0: sub-screens keep the venue name; only the 10px line swaps
          // to context ("Settings · Sound" is the pinned example).
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Volume policy',
                        style: PrismType.displaySerif.copyWith(
                            fontSize: 22, color: palette.textPrimary)),
                    const SizedBox(height: 14),
                    // Scope chip — single option (S05-2).
                    SizedBox(
                      width: 130,
                      child: SegToggle(
                        options: const ['This zone'],
                        selected: 0,
                      ),
                    ),
                    const SizedBox(height: 18),
                    _SliderRow(
                      label: 'Quietest it can go',
                      value: guardrails.volumeMin,
                      onChanged: (v) => repo.updateGuardrails(guardrails
                          .copyWith(
                              volumeMin:
                                  v.clamp(0, guardrails.volumeMax - 1))),
                    ),
                    const SizedBox(height: 14),
                    _SliderRow(
                      label: 'Loudest it can go',
                      value: guardrails.volumeMax,
                      onChanged: (v) => repo.updateGuardrails(guardrails
                          .copyWith(
                              volumeMax:
                                  v.clamp(guardrails.volumeMin + 1, 100))),
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        // Helper copy is elided in the README (open_questions).
                        Expanded(
                          child: Text('Auto and staff stay inside this band.',
                              style: PrismType.microHelper
                                  .copyWith(color: palette.textSecondary)),
                        ),
                        const SizedBox(width: 12),
                        _ResetBandButton(guardrails: guardrails),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SettingsRow(
                      title: 'Quiet hours',
                      sub: 'After 10:00 pm · cap at 55%',
                      chevron: false,
                      trailing: PrismToggle(
                        on: guardrails.quietHoursOn,
                        onChanged: (on) => repo.updateGuardrails(
                            guardrails.copyWith(quietHoursOn: on)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text('Floor staff can',
                        style: PrismType.label
                            .copyWith(color: palette.textSecondary)),
                    const SizedBox(height: 8),
                    SegToggle(
                      options: const ['View only', 'Nudge ±10%', 'Full band'],
                      selected: guardrails.floorLeeway.index,
                      onChanged: (i) => repo.updateGuardrails(guardrails
                          .copyWith(floorLeeway: FloorLeeway.values[i])),
                    ),
                    const SizedBox(height: 9),
                    Text('A floor nudge eases back to the curve after 2 hours.',
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

/// Puts the output band back to the shipped default.
///
/// The two sliders clamp against each other — the min cannot pass the max and
/// vice versa — so dragging back to a known band by hand is fiddly, and a
/// manager who has pulled it to 0–100 while experimenting has no way to say
/// "never mind".
///
/// The defaults come from `const Guardrails()` rather than from literals here.
/// 26/70 is the value the Dart model, the server's `GuardrailsBody` zod schema
/// and the S05-2 frame all agree on, and reading it from the model is what
/// stops this button drifting away from them if the default ever moves.
///
/// **One write, not two.** Setting min and max in a single `copyWith` matters:
/// two sequential updates would each be clamped against the other's old value,
/// so resetting 0–100 would land on 26–100 and then 26–70 only by luck of
/// ordering. It also keeps the debounced PUT to a single request.
///
/// Inert at 40% once the band is already at the default (§6-A3), rather than
/// hidden — a control that vanishes is harder to find again than one that is
/// visibly unavailable, and this one is the answer to "what were the numbers?".
class _ResetBandButton extends ConsumerWidget {
  const _ResetBandButton({required this.guardrails});

  final Guardrails guardrails;

  static const _defaults = Guardrails();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final atDefault = guardrails.volumeMin == _defaults.volumeMin &&
        guardrails.volumeMax == _defaults.volumeMax;

    return Opacity(
      opacity: atDefault ? 0.4 : 1,
      child: Pressable(
        onTap: atDefault
            ? null
            : () => ref.read(settingsRepoProvider).updateGuardrails(
                  guardrails.copyWith(
                    volumeMin: _defaults.volumeMin,
                    volumeMax: _defaults.volumeMax,
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
          child: Text(
            'Reset to ${_defaults.volumeMin}–${_defaults.volumeMax}%',
            style: PrismType.bodySm.copyWith(
                fontSize: 12, fontWeight: FontWeight.w700, color: palette.accent),
          ),
        ),
      ),
    );
  }
}

/// Label + live % + interactive band slider (S05-2: track h6 r999 `tile2`,
/// fill accent, thumb 14 white).
class _SliderRow extends StatelessWidget {
  const _SliderRow(
      {required this.label, required this.value, required this.onChanged});

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label,
                style: PrismType.label.copyWith(color: palette.textSecondary)),
            const Spacer(),
            Text('$value%',
                style: PrismType.bodySm
                    .copyWith(fontSize: 12, color: palette.textPrimary)),
          ],
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth;

            void handle(Offset local) {
              final v = (local.dx / w * 100).round().clamp(0, 100);
              if (v != value) onChanged(v);
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (d) => handle(d.localPosition),
              onHorizontalDragUpdate: (d) => handle(d.localPosition),
              child: SizedBox(
                height: 14,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: palette.tile2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Container(
                      height: 6,
                      width: w * value / 100,
                      decoration: BoxDecoration(
                        color: palette.accent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Positioned(
                      left: (w * value / 100 - 7).clamp(0, w - 14),
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFFFFF),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
