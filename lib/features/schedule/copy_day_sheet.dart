import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/day_chips.dart';
import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// "Copy Monday to…" — finding #11.
///
/// A weekly plan is mostly one or two day shapes repeated: a weekday, a
/// weekend, sometimes a late night. Building the second one block by block is
/// where "five blocks a day across seven days takes 35 separate saves" came
/// from, and it is the one part of that number nothing else in this finding
/// removes — multi-select speeds up *writing the same block on several days*,
/// and this speeds up *repeating a day that already exists*.
///
/// Returns the day indices to copy onto, or null if cancelled. The source day
/// is never offered: copying Monday onto Monday is either a no-op or a
/// duplicate of everything on it, and neither is something to ask for.
Future<List<int>?> showCopyDaySheet(
  BuildContext context, {
  required int day,
  required bool hasBlocks,
}) {
  return showPrismSheet<List<int>>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: _CopyDaySheet(day: day, hasBlocks: hasBlocks),
  );
}

/// Asks before a copy overwrites what is already on those days.
///
/// Separate from [showReplaceDaypartDialog], which names one time on one day.
/// A copy collides across several days at once and the honest sentence is a
/// different one — naming a single minute here would describe a fraction of
/// what is about to happen.
Future<bool?> showReplaceOnCopyDialog(
  BuildContext context, {
  required String sourceDayName,
  required String targetDayNames,
  required int blockCount,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Icon(LucideIcons.replace, size: 20, color: palette.accentText),
        title: 'Replace what is already there?',
        body: TextSpan(
          children: [
            TextSpan(
              text: '$targetDayNames already ',
            ),
            TextSpan(
              text: blockCount == 1
                  ? 'has a block starting at the same time. '
                  : 'has blocks starting at the same times. ',
            ),
            TextSpan(
              text: 'Copying $sourceDayName',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const TextSpan(
              text: ' will take those slots — two dayparts starting at the '
                  'same minute leave the room picking between them at random. '
                  'Everything else already copied across stays.',
            ),
          ],
        ),
        confirmLabel: 'Replace',
        cancelLabel: 'Leave them alone',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ),
  );
}

class _CopyDaySheet extends StatefulWidget {
  const _CopyDaySheet({required this.day, required this.hasBlocks});

  final int day;

  /// Whether the source day has anything on it. A day with no blocks has
  /// nothing to copy, and the sheet says so rather than offering a button that
  /// would do nothing.
  final bool hasBlocks;

  @override
  State<_CopyDaySheet> createState() => _CopyDaySheetState();
}

class _CopyDaySheetState extends State<_CopyDaySheet> {
  final _targets = <int>{};

  static const _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final source = _dayNames[widget.day];

    return PrismBottomSheet(
      title: 'Copy $source to…',
      sub: widget.hasBlocks
          ? 'Every block on $source is added to the days you pick.'
          : 'There is nothing on $source to copy yet.',
      primaryLabel: _targets.isEmpty
          ? 'Copy'
          : 'Copy to ${_targets.length} '
              '${_targets.length == 1 ? 'day' : 'days'}',
      onPrimary: !widget.hasBlocks || _targets.isEmpty
          ? null
          : () => Navigator.of(context).pop(_targets.toList()..sort()),
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 16),
        DayChips(
          selected: _targets,
          // The source day is inert rather than hidden: a row of six chips
          // with a gap in it is harder to read than seven with one that does
          // not respond, and the gap would also move depending on the day.
          onToggle: (i) => setState(() {
            if (i == widget.day) return;
            if (!_targets.remove(i)) _targets.add(i);
          }),
        ),
        const SizedBox(height: 9),
        Text(
          widget.hasBlocks
              ? 'Anything already on those days at the same time is kept '
                  'until you say otherwise.'
              : 'Add a block to $source first.',
          style: PrismType.microHelper.copyWith(color: palette.textSecondary),
        ),
      ],
    );
  }
}
