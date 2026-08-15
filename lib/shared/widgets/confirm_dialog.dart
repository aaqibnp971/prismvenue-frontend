import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'primary_button.dart';
import 'secondary_button.dart';

/// Confirm dialog — §3: w400, r18, bg `surface`, border `borderStrong`,
/// padding 22, centered; icon well 44 r12 `accentSoft`; title 21 serif;
/// body 13.5 lh 1.5 `textSecondary`; two h46 flex1 buttons, gap 10.
/// Dialog shadow §1.7. Scrim starts below the top bar (S01-3).
class ConfirmDialog extends StatelessWidget {
  const ConfirmDialog({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.confirmLabel,
    this.cancelLabel = 'Cancel',
    this.onCancel,
    this.onConfirm,
  });

  /// Content of the 44×44 accentSoft well — a mood dot (S01-3) or an icon
  /// (S02-3 rotate-ccw).
  final Widget icon;

  final String title;

  /// Body supports bold spans (S02-3 bolds the mood name).
  final InlineSpan body;

  final String confirmLabel;
  /// Null renders a single full-width action.
  ///
  /// Every dialog in the app is a real choice, so two buttons is the default.
  /// An informational one — "nothing is planned for today", shown to floor
  /// staff who cannot edit the schedule — has only one thing to say, and a
  /// Cancel beside a Got it is two controls for the same outcome.
  final String? cancelLabel;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return Container(
      width: 400,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border.all(color: palette.borderStrong),
        borderRadius: BorderRadius.circular(18),
        boxShadow: PrismPalette.dialogShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: palette.accentSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: icon,
          ),
          const SizedBox(height: 14),
          Text(title,
              style: PrismType.dialogTitle.copyWith(color: palette.textPrimary)),
          const SizedBox(height: 8),
          Text.rich(
            body,
            style: PrismType.dialogBody.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              if (cancelLabel != null) ...[
                Expanded(
                  child: SecondaryButton(label: cancelLabel!, onTap: onCancel),
                ),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: PrimaryButton(label: confirmLabel, onTap: onConfirm),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Shows [dialog] centered over a scrim `rgba(5,5,8,.62)` that starts BELOW
/// the top bar — the bar stays visible (S01-3). Scrim tap dismisses with no
/// state change (§4).
Future<T?> showPrismDialog<T>(
  BuildContext context, {
  required Widget dialog,
  double topBarHeight = 0,
}) {
  return Navigator.of(context, rootNavigator: true).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierColor: Colors.transparent, // scrim drawn manually below the bar
      transitionDuration: const Duration(milliseconds: 150),
      reverseTransitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (routeContext, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: Stack(
            children: [
              Positioned.fill(
                top: topBarHeight,
                child: GestureDetector(
                  onTap: () => Navigator.of(routeContext).pop(),
                  child:
                      Container(color: const Color.fromRGBO(5, 5, 8, .62)),
                ),
              ),
              Center(
                child: Material(color: Colors.transparent, child: dialog),
              ),
            ],
          ),
        );
      },
    ),
  );
}
