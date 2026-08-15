import 'package:flutter/material.dart';

import '../../data/models/timezone.dart';
import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// Picks the clock a venue's schedule runs on.
///
/// ## Why this screen has to exist
///
/// `venues.timezone` is the single thing that decides which daypart is current
/// — `app.scheduled_mood_for` reads it, and migration 010's per-minute job acts
/// on the answer. Nothing in the app set it or showed it, so every venue kept
/// the column default: a manager in one country typed 10pm, the room ran on
/// another country's clock, and the plan fired ninety minutes late with nothing
/// on screen to explain why.
///
/// ## The list is the tz database, not a list we keep
///
/// Options come from the server, which reads `pg_timezone_names`. A list
/// compiled into the app is a list that goes stale — zones are added, renamed
/// and re-offset every year — and this is exactly the field where being quietly
/// out of date is expensive.
///
/// Search is over the city, the region and the offset together, because people
/// look for a venue's zone by all three ("kolkata", "asia", "5:30").
Future<String?> showTimezoneSheet(
  BuildContext context, {
  required List<TimezoneOption> options,
  required String? selected,
}) {
  return showPrismSheet<String>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: Builder(
      builder: (sheetContext) => _TimezoneSheet(
        options: options,
        selected: selected,
        onPick: (name) => Navigator.of(sheetContext).pop(name),
        onCancel: () => Navigator.of(sheetContext).pop(),
      ),
    ),
  );
}

class _TimezoneSheet extends StatefulWidget {
  const _TimezoneSheet({
    required this.options,
    required this.selected,
    required this.onPick,
    required this.onCancel,
  });

  final List<TimezoneOption> options;
  final String? selected;
  final ValueChanged<String> onPick;
  final VoidCallback onCancel;

  @override
  State<_TimezoneSheet> createState() => _TimezoneSheetState();
}

class _TimezoneSheetState extends State<_TimezoneSheet> {
  String _query = '';

  List<TimezoneOption> get _matches {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return widget.options;
    return [
      for (final o in widget.options)
        if (o.city.toLowerCase().contains(q) ||
            o.region.toLowerCase().contains(q) ||
            o.name.toLowerCase().contains(q) ||
            o.offsetLabel.toLowerCase().contains(q))
          o,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final matches = _matches;

    return PrismBottomSheet(
      title: 'Time zone',
      sub: 'The clock this venue’s schedule runs on.',
      // Tapping a row commits, so the footer only ever closes. Both buttons do
      // the same thing on purpose: a picker with an inert "Save" invites the
      // reading that your tap did not count.
      cancelLabel: 'Close',
      primaryLabel: 'Done',
      onPrimary: widget.onCancel,
      onCancel: widget.onCancel,
      children: [
        const SizedBox(height: 14),
        TextField(
          autofocus: true,
          onChanged: (v) => setState(() => _query = v),
          style: PrismType.bodySm.copyWith(color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: 'Search a city, region or offset',
            hintStyle:
                PrismType.bodySm.copyWith(color: palette.textTertiary),
            filled: true,
            fillColor: palette.tile,
            contentPadding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: palette.accent),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (matches.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Text('No zone matches “$_query”.',
                textAlign: TextAlign.center,
                style: PrismType.bodySm.copyWith(color: palette.textTertiary)),
          )
        else
          // Bounded rather than shrink-wrapped: the full tz database is ~600
          // rows, and a sheet that grows to fit them has no scroll of its own.
          SizedBox(
            height: 320,
            child: ListView.separated(
              itemCount: matches.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, i) => _row(palette, matches[i]),
            ),
          ),
      ],
    );
  }

  Widget _row(PrismPalette palette, TimezoneOption option) {
    final on = option.name == widget.selected;
    return GestureDetector(
      onTap: () => widget.onPick(option.name),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11, horizontal: 13),
        decoration: BoxDecoration(
          color: on ? palette.accentSoft : palette.tile,
          border: Border.all(color: on ? palette.accent : palette.border),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(option.city,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PrismType.button.copyWith(
                          fontSize: 13,
                          color:
                              on ? palette.accentText : palette.textPrimary)),
                  const SizedBox(height: 1),
                  Text(option.region,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PrismType.microHelper
                          .copyWith(color: palette.textTertiary)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(option.offsetLabel,
                style: PrismType.bodySm.copyWith(
                    fontSize: 12,
                    color: on ? palette.accentText : palette.textSecondary)),
          ],
        ),
      ),
    );
  }
}
