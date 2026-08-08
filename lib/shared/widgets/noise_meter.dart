import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// Read-only noise display in the Floor hero — §2 S01-1: row gap 10,
/// "Noise" 10/600, track h6 r999 bg `tile2` max-w 260 with accent fill +
/// 14px white thumb, value 12/700. The thumb is decorative (§6-A6).
class NoiseMeter extends StatelessWidget {
  const NoiseMeter({super.key, required this.value});

  /// 0–100 (%), or null when nothing has reported yet.
  ///
  /// Nullable on purpose. This used to be a plain int and the Floor screen fed
  /// it `noise.value ?? 62`, so a zone whose sensor had never reported showed a
  /// confident 62% — a frame sample value rendered as live telemetry. The venue
  /// header provider already gets this right: it refuses to claim "online" it
  /// cannot substantiate. An empty track and a dash say the same thing honestly.
  final int? value;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final known = value;
    final fillPct = known ?? 0;
    return Row(
      children: [
        Text('Noise',
            style: PrismType.label
                .copyWith(fontSize: 10, color: palette.textSecondary)),
        const SizedBox(width: 10),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final w = constraints.maxWidth;
                final fillW = w * fillPct / 100;
                return SizedBox(
                  height: 14,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: palette.tile2,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      if (known != null)
                        Container(
                          height: 6,
                          width: fillW,
                          decoration: BoxDecoration(
                            color: palette.accent,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      if (known != null)
                        Positioned(
                        // `w - 14` goes negative once the track is narrower
                        // than the thumb, and clamp(0, negative) throws
                        // "Invalid argument: 0" — which surfaces as a red
                        // ErrorWidget covering the whole screen rather than a
                        // squashed meter. Narrow is a layout problem; crashing
                        // is a different and much worse one.
                        left: (fillW - 7).clamp(0, math.max(0, w - 14)),
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
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(known == null ? '—' : '$known%',
            style: PrismType.button.copyWith(
                fontSize: 12,
                color: known == null
                    ? palette.textTertiary
                    : palette.textPrimary)),
      ],
    );
  }
}
