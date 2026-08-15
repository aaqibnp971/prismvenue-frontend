import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/prism_top_bar.dart';
import '../../../theme/palette.dart';

/// Answers a tap on Auto when there is no schedule for Auto to follow.
///
/// "Auto" means "follow the schedule". With nothing planned for today the
/// button is an offer the app cannot keep: `desired_mode` flips to auto,
/// `app.scheduled_mood_for` returns NULL because no daypart covers the moment,
/// and — by design, migration 010 — the room keeps whatever it was already
/// playing rather than being snapped to silence or a default. From the floor
/// that is indistinguishable from a button that did nothing.
///
/// So the tap is answered instead of swallowed. Dimming alone would say "not
/// available" without ever saying why, and the reason is both actionable and
/// one step away.
///
/// Reachable more often than it sounds. A week can be forked with only some
/// days filled in — migration 011 is explicit that a fork is a complete plan
/// and is never merged with the recurring one — so a zone with a full weekly
/// plan can still have an empty Friday.
///
/// [canEdit] is false for floor staff: the router denies them `/schedule`, so
/// offering to take them there would be a button that bounces them back to
/// Floor. They get told who can fix it instead.
Future<bool?> showNoScheduleDialog(BuildContext context,
    {required bool canEdit}) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  return showPrismDialog<bool>(
    context,
    topBarHeight: PrismTopBar.height,
    dialog: Builder(
      builder: (dialogContext) => ConfirmDialog(
        icon:
            Icon(LucideIcons.calendarPlus, size: 20, color: palette.accentText),
        title: 'Nothing is planned for today',
        body: TextSpan(
          text: canEdit
              ? 'Auto follows your weekly plan, and today has no dayparts in '
                  'it — so there is nothing for Prism to pick up. Add a '
                  'daypart and the room will follow it from then on.'
              : 'Auto follows the weekly plan, and today has no dayparts in '
                  'it — so there is nothing for Prism to pick up. A manager '
                  'can add one from the Schedule tab.',
        ),
        confirmLabel: canEdit ? 'Open Schedule' : 'Got it',
        cancelLabel: canEdit ? 'Not now' : null,
        onConfirm: () => Navigator.of(dialogContext).pop(canEdit),
        onCancel: () => Navigator.of(dialogContext).pop(false),
      ),
    ),
  );
}
