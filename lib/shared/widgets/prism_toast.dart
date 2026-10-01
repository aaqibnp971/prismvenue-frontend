import 'package:flutter/material.dart';

import '../../theme/palette.dart';
import '../../theme/typography.dart';

/// A short confirmation that something reached the room.
///
/// Finding #14: nothing in the app confirmed a change. A manager tapped a
/// mood, moved a slider or saved a daypart and the screen simply carried on
/// looking the way it had. That is worse here than in most apps, because every
/// mutation is deliberately fire-and-forget — the repo awaits the POST and
/// then refreshes a stream, so there is a real gap between "I pressed it" and
/// "the room changed", and nothing filled it.
///
/// Deliberately a confirmation of DELIVERY, not of success. The zone-write
/// contract is "accepted, not done": the API records intent and returns
/// without waiting for hardware. So the words are "Sent to the room", never
/// "Playing" — claiming the second would be the same lie the status chips used
/// to tell.
///
/// Uses the ScaffoldMessenger rather than a custom overlay so it survives
/// navigation, stacks properly, and is dismissed by the framework rather than
/// by a timer of ours.
void showPrismToast(BuildContext context, String message) {
  final palette = Theme.of(context).extension<PrismPalette>()!;
  final messenger = ScaffoldMessenger.maybeOf(context);
  // A screen with no Scaffold above it (a dialog mid-dismiss, a test pumping a
  // bare widget) must not throw for the sake of a courtesy message.
  if (messenger == null) return;

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(
        message,
        style: PrismType.bodySm.copyWith(color: palette.textPrimary),
      ),
      backgroundColor: palette.surface,
      behavior: SnackBarBehavior.floating,
      width: 320,
      // Long enough to read across a counter, short enough not to sit over the
      // mood grid while somebody is working.
      duration: const Duration(seconds: 2),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
}
