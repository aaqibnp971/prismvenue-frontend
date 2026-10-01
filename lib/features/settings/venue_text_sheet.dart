import 'package:flutter/material.dart';

import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/prism_field.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// Edit one line of text about a venue — its name, or its address.
///
/// Finding #8: neither could be changed after creation. A typo in a venue name
/// was permanent, and test venues like "0000" were stuck in live portfolios.
///
/// One sheet for both, because they differ in exactly two ways — whether empty
/// is allowed, and the helper line — and two near-identical sheets would drift
/// the way the two `hours_label` formatters nearly did.
///
/// Resolves with the new value, or null if cancelled. An empty result is
/// meaningful for an address (it clears it) and impossible for a name, which
/// is what [allowEmpty] decides.
Future<String?> showVenueTextSheet(
  BuildContext context, {
  required String title,
  required String label,
  required String initial,
  required bool allowEmpty,
  String? helper,
}) {
  return showPrismSheet<String>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: _VenueTextSheet(
      title: title,
      label: label,
      initial: initial,
      allowEmpty: allowEmpty,
      helper: helper,
    ),
  );
}

class _VenueTextSheet extends StatefulWidget {
  const _VenueTextSheet({
    required this.title,
    required this.label,
    required this.initial,
    required this.allowEmpty,
    this.helper,
  });

  final String title;
  final String label;
  final String initial;
  final bool allowEmpty;
  final String? helper;

  @override
  State<_VenueTextSheet> createState() => _VenueTextSheetState();
}

class _VenueTextSheetState extends State<_VenueTextSheet> {
  late final TextEditingController _value =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return PrismBottomSheet(
      title: widget.title,
      primaryLabel: 'Save',
      onPrimary: () {
        final text = _value.text.trim();
        // A blank name resolves to null — "nothing to change" rather than an
        // unnamed venue. A blank address resolves to the empty string, which
        // the caller turns into a deliberate clear.
        if (text.isEmpty && !widget.allowEmpty) {
          Navigator.of(context).pop();
          return;
        }
        Navigator.of(context).pop(text);
      },
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 16),
        PrismField(
          label: widget.label,
          controller: _value,
          focusedOverride: true,
        ),
        if (widget.helper != null) ...[
          const SizedBox(height: 9),
          Text(
            widget.helper!,
            style: PrismType.microHelper.copyWith(color: palette.textSecondary),
          ),
        ],
      ],
    );
  }
}
