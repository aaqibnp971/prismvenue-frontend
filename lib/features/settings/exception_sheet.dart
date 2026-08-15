import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/guardrails.dart';
import '../../data/repositories/settings_repo.dart';
import '../../shared/widgets/day_chips.dart';
import '../../shared/widgets/error_note.dart';
import '../../shared/widgets/prism_bottom_sheet.dart';
import '../../shared/widgets/prism_toggle.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/seg_toggle.dart';
import '../../shared/widgets/settings_row.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'widgets/time_field.dart';

/// S05-10 "Add an exception — pick days, hours & repeat". BottomSheet:
/// sub "Different hours for some days — everything else keeps the
/// default."; Which days — DayChips (Fri & Sat selected); Hours — Opens
/// "7:00 am" / Closes "1:00 am" fields + "Tap a time to set it on the
/// dial."; "Closed all day" toggle row + "e.g. a public holiday"; Repeat
/// seg Just this once / [Every week]; Cancel / "Add exception" (1:2).
///
/// Pass [existing] to edit one instead: every control pre-fills and a
/// full-width "Delete exception" appears at the bottom, following the
/// S03-4/S03-5 pattern the daypart sheet already uses for add-vs-edit. Until
/// this existed an exception could only be added — never changed or removed
/// (`open_questions.md` #26).
Future<void> showExceptionSheet(
  BuildContext context,
  WidgetRef ref, {
  HoursException? existing,
}) async {
  final result = await showPrismSheet<_ExceptionResult>(
    context,
    topBarHeight: PrismTopBar.height,
    sheet: _ExceptionSheet(existing: existing),
  );
  if (result == null) return;
  final repo = ref.read(settingsRepoProvider);
  try {
    switch (result) {
      case _Save(:final exception):
        if (existing?.id == null) {
          await repo.addException(exception);
        } else {
          await repo.updateException(exception);
        }
      case _Delete(:final id):
        await repo.deleteException(id);
    }
  } catch (e) {
    if (context.mounted) showPrismError(context, e);
  }
}

sealed class _ExceptionResult {}

class _Save extends _ExceptionResult {
  _Save(this.exception);
  final HoursException exception;
}

class _Delete extends _ExceptionResult {
  _Delete(this.id);
  final String id;
}

class _ExceptionSheet extends StatefulWidget {
  const _ExceptionSheet({this.existing});

  final HoursException? existing;

  @override
  State<_ExceptionSheet> createState() => _ExceptionSheetState();
}

class _ExceptionSheetState extends State<_ExceptionSheet> {
  // Fri & Sat / 7am–1am are the frame's defaults for a NEW exception; editing
  // starts from what is already saved.
  late final Set<int> _days = {...?widget.existing?.days} .isEmpty
      ? {4, 5}
      : {...widget.existing!.days};
  late int _open = widget.existing?.openHour ?? 7;
  late int _close = widget.existing?.closeHour ?? 1;
  late bool _closedAllDay = widget.existing?.closedAllDay ?? false;
  late bool _everyWeek = widget.existing?.everyWeek ?? true;

  bool get _editing => widget.existing?.id != null;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    return PrismBottomSheet(
      title: _editing ? 'Edit exception' : 'Add an exception',
      sub: 'Different hours for some days — everything else keeps the '
          'default.',
      primaryLabel: _editing ? 'Save' : 'Add exception',
      onPrimary: _days.isEmpty
          ? null
          : () => Navigator.of(context).pop(_Save(HoursException(
                id: widget.existing?.id,
                days: Set.of(_days),
                openHour: _open,
                closeHour: _close,
                closedAllDay: _closedAllDay,
                everyWeek: _everyWeek,
              ))),
      onCancel: () => Navigator.of(context).pop(),
      children: [
        const SizedBox(height: 16),
        Text('Which days',
            style: PrismType.label.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 8),
        DayChips(
          selected: _days,
          onToggle: (i) => setState(
              () => _days.contains(i) ? _days.remove(i) : _days.add(i)),
        ),
        const SizedBox(height: 14),
        Text('Hours',
            style: PrismType.label.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TimeField(
                label: 'Opens',
                minutes: _open * 60,
                dialTitle: 'Opening time',
                // The dial reports minutes; with the default 60-minute step
                // that is always a whole hour, and `open_hour`/`close_hour`
                // are what the wire carries.
                onChanged: (m) => setState(() => _open = m ~/ 60),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TimeField(
                label: 'Closes',
                minutes: _close * 60,
                dialTitle: 'Closing time',
                // The dial reports minutes; with the default 60-minute step
                // that is always a whole hour, and `open_hour`/`close_hour`
                // are what the wire carries.
                onChanged: (m) => setState(() => _close = m ~/ 60),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        Text('Tap a time to set it on the dial.',
            style:
                PrismType.microHelper.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 14),
        SettingsRow(
          title: 'Closed all day',
          sub: 'e.g. a public holiday',
          chevron: false,
          trailing: PrismToggle(
            on: _closedAllDay,
            onChanged: (on) => setState(() => _closedAllDay = on),
          ),
        ),
        const SizedBox(height: 14),
        Text('Repeat',
            style: PrismType.label.copyWith(color: palette.textSecondary)),
        const SizedBox(height: 8),
        SegToggle(
          options: const ['Just this once', 'Every week'],
          selected: _everyWeek ? 1 : 0,
          onChanged: (i) => setState(() => _everyWeek = i == 1),
        ),
        if (_editing) ...[
          const SizedBox(height: 16),
          // Same treatment as "Delete daypart" (S03-5): full-width red text
          // button below the controls, no confirm step — consistent with the
          // rest of the app's destructive actions.
          GestureDetector(
            onTap: () =>
                Navigator.of(context).pop(_Delete(widget.existing!.id!)),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              alignment: Alignment.center,
              child: Text('Delete exception',
                  style: PrismType.button
                      .copyWith(fontSize: 13, color: palette.red)),
            ),
          ),
        ],
      ],
    );
  }
}
