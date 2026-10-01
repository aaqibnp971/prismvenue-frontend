import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'pressable.dart';
import 'prism_icons.dart';

/// Settings / alerts list row — §2 S05-1: bg `surface`, 1px `border`, r12,
/// padding 13×15 (v×h); title 13.5/600, sub 11 `textSecondary`, value
/// 12.5/600 `textSecondary`, chevron 15.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.title,
    this.sub,
    this.value,
    this.chevron = true,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String? sub;
  final String? value;

  /// Trailing chevron-right (suppressed when a custom [trailing] — e.g. a
  /// PrismToggle or dropdown anchor — is supplied).
  final bool chevron;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    // §6-A2: `tile2` flash while pressed.
    return Pressable(
      onTap: onTap,
      effect: PressEffect.flash,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 15),
        decoration: BoxDecoration(
          color: palette.surface,
          border: Border.all(color: palette.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: PrismType.bodySm
                          .copyWith(color: palette.textPrimary)),
                  if (sub != null) ...[
                    const SizedBox(height: 2),
                    Text(sub!,
                        style: PrismType.label.copyWith(
                            fontWeight: FontWeight.w400,
                            color: palette.textSecondary)),
                  ],
                ],
              ),
            ),
            if (value != null) ...[
              const SizedBox(width: 10),
              // Flexible, not bare: a value is free text — an address, a
              // venue name, an IANA zone — and an unconstrained Text in a Row
              // paints the overflow stripes over the row on a narrow screen
              // rather than shortening. Found by phone_layout_test when
              // finding #8 put an address here.
              Flexible(
                child: Text(value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: PrismType.label.copyWith(
                        fontSize: 12.5, color: palette.textSecondary)),
              ),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 10),
              trailing!,
            ] else if (chevron) ...[
              const SizedBox(width: 8),
              PrismChevron(
                direction: ChevronDirection.right,
                size: 15,
                color: palette.textSecondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
