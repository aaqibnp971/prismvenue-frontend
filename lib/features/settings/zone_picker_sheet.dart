import 'package:flutter/material.dart';

import '../../data/models/venue.dart';
import '../../data/models/zone.dart';
import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/pressable.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// Pick which room Settings is talking about — finding #10.
///
/// The Settings page is headed with the VENUE, while the volume band,
/// transitions and takeover access are all stored per ZONE. An owner changed
/// the band believing it covered the venue; the only hint otherwise was a chip
/// reading "This zone", which never said which.
///
/// Switching here uses `operateZone`, the same control S04-1's "Open floor"
/// uses, so Floor and Schedule follow along. A settings-only notion of
/// "current zone" would be a second answer to a question the app already has
/// one answer for.
Future<Zone?> showZonePickerSheet(
  BuildContext context, {
  required Venue venue,
}) {
  return showPrismSheet<Zone>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: _ZonePickerSheet(venue: venue),
  );
}

class _ZonePickerSheet extends StatelessWidget {
  const _ZonePickerSheet({required this.venue});

  final Venue venue;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return PrismBottomSheet(
      title: 'Which room?',
      // Choosing a row IS the action; the primary button is only a way out,
      // so it says Close rather than offering a second control for one
      // outcome.
      primaryLabel: 'Close',
      onPrimary: () => Navigator.of(context).pop(),
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 8),
        Text(
          'Volume, transitions and takeover access are set for one room at a '
          'time.',
          style: PrismType.microHelper.copyWith(color: palette.textSecondary),
        ),
        const SizedBox(height: 12),
        for (final zone in venue.zones)
          Pressable(
            onTap: () => Navigator.of(context).pop(zone),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding:
                  const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
              decoration: BoxDecoration(
                color: palette.tile,
                border: Border.all(color: palette.border),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                zone.name,
                style: PrismType.bodySm.copyWith(color: palette.textPrimary),
              ),
            ),
          ),
      ],
    );
  }
}
