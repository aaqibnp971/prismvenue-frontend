import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../shared/widgets/confirm_dialog.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../theme/palette.dart';

/// Asks before a save overwrites the daypart already in that slot.
///
/// ## Why the collision is refused rather than allowed
///
/// Two dayparts on the same day at the same start time is the one overlap the
/// scheduler cannot resolve. `app.scheduled_mood_for` ends
/// `order by start_local desc limit 1`, and between equal start times that
/// order is unspecified — so the room plays an arbitrary one of the two, and
/// can change its mind between one minute's cron tick and the next. A rail
/// showing "11:05 Morning calm" above "11:05 Peak" is not describing anything
/// the venue can actually do.
///
/// Ordinary overlap stays allowed, deliberately: it resolves to the later
/// start, and a weekly plan is normally contiguous, so a block can hardly move
/// without touching a neighbour. See `week_grid.dart`.
///
/// ## Why it is a question and not a silent replace
///
/// The daypart being overwritten is something somebody wrote on purpose, and a
/// save that quietly deletes it gives no clue that it happened — the row simply
/// stops being in the list. Every other thing the room will hear is confirmed
/// first (S01-3, S02-3, delete daypart, remove zone); this is the same rule.
///
/// [replacedMoodName] is best-effort: the collision is detected by the server,
/// which answers 409 without saying what was in the way. The screen looks the
/// occupant up in the plan it already has, and falls back to naming only the
/// time when it cannot — another iPad may have added it a moment ago.
Future<bool?> showReplaceDaypartDialog(
  BuildContext context, {
  required String timeLabel,
  required String dayName,
  required String newMoodName,
  String? replacedMoodName,
}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon: Icon(LucideIcons.replace, size: 20, color: palette.accentText),
        title: 'Replace what starts at $timeLabel?',
        body: TextSpan(
          children: [
            TextSpan(
              text: replacedMoodName == null
                  ? 'Something already starts at $timeLabel on $dayName. '
                  : '$replacedMoodName already starts at $timeLabel on '
                      '$dayName. ',
            ),
            TextSpan(
              text: 'Saving $newMoodName',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const TextSpan(
              text: ' will take that slot — two dayparts starting at the same '
                  'minute leave the room picking between them at random.',
            ),
          ],
        ),
        confirmLabel: 'Replace',
        cancelLabel: 'Keep both times free',
        onConfirm: () => Navigator.of(dialogContext).pop(true),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ),
  );
}
