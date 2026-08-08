import 'package:flutter/material.dart';

import '../../theme/palette.dart';

/// §6-A2 pressed states (not designed — derived): 92% scale on filled
/// buttons, `tile2` flash on rows. No effect while [onTap] is null
/// (disabled rows/buttons stay inert).
enum PressEffect { scale, flash }

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.effect = PressEffect.scale,
    this.borderRadius = 12,
    this.semanticLabel,
    this.minTapTarget = 44,
  });

  final Widget child;
  final VoidCallback? onTap;
  final PressEffect effect;

  /// Spoken label, when the child's own text is not the whole story — an
  /// icon-only control, or a row whose meaning depends on nearby text.
  ///
  /// Null is fine for anything whose visible text already reads correctly:
  /// Semantics merges the descendants, so a labelled button announces itself.
  final String? semanticLabel;

  /// The floor for the touch target, independent of how the child paints.
  ///
  /// 44 is the platform minimum on both iOS and Android, and several controls
  /// sat well under it — the schedule's date label and its 28px chevrons among
  /// them. It expands the hit area only; nothing moves on screen.
  final double minTapTarget;

  /// Flash overlay corner radius — match the row's own radius.
  final double borderRadius;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final active = widget.onTap != null;

    final content = switch (widget.effect) {
      PressEffect.scale => AnimatedScale(
          scale: _pressed ? .92 : 1,
          duration: const Duration(milliseconds: 90),
          curve: Curves.ease,
          child: widget.child,
        ),
      PressEffect.flash => Stack(
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: _pressed ? .45 : 0,
                  duration: const Duration(milliseconds: 90),
                  curve: Curves.ease,
                  child: Container(
                    decoration: BoxDecoration(
                      color: palette.tile2,
                      borderRadius:
                          BorderRadius.circular(widget.borderRadius),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    };

    // Every control in the app was a bare GestureDetector: no role, no label,
    // nothing operable by assistive tech, and VoiceOver announcing raw text.
    // Wrapping the shared press widget gets the button role onto most of them
    // at once, rather than one screen at a time.
    return Semantics(
      button: true,
      enabled: active,
      label: widget.semanticLabel,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: active ? (_) => _set(true) : null,
        onTapUp: active ? (_) => _set(false) : null,
        onTapCancel: active ? () => _set(false) : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: widget.minTapTarget,
            minHeight: widget.minTapTarget,
          ),
          child: Center(widthFactor: 1, heightFactor: 1, child: content),
        ),
      ),
    );
  }
}
