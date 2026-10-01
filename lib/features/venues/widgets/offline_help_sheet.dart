import 'package:flutter/material.dart';

import '../../../app/env.dart';
import '../../../data/models/zone.dart';
import '../../../theme/palette.dart';
import '../../../theme/typography.dart';

/// What to do about a room that has stopped reporting.
///
/// Finding #16: the row said "Offline" and nothing else. That is a dead end —
/// it names a problem, gives no idea of its age, and offers no next step, so
/// the only available action is to ring whoever set the venue up.
///
/// Everything here is deliberately checkable by one person standing in the
/// room, in the order that resolves the most cases soonest: is it on, is the
/// app open, is it on the network. Nothing asks them to read a log or know
/// what a zone is.
///
/// The support line only appears when a contact has been configured
/// (`PRISM_SUPPORT_CONTACT`), because a screen that says "contact support" and
/// then names nobody is worse than one that stays quiet.
Future<void> showOfflineHelp(BuildContext context, Zone zone) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _OfflineHelpSheet(zone: zone),
  );
}

class _OfflineHelpSheet extends StatelessWidget {
  const _OfflineHelpSheet({required this.zone});

  final Zone zone;

  @override
  Widget build(BuildContext context) {
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final seen = lastSeenLabel(zone.lastSeenAt);

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${zone.name} is offline', style: PrismType.sheetTitle),
            const SizedBox(height: 6),
            Text(
              // The age of the problem is the first thing an owner needs, and
              // "never" is a different problem from "since this morning".
              seen == null
                  ? 'No Prism device has ever reported from this room. It may '
                      'not have been set up yet.'
                  : 'Prism last heard from this room $seen.',
              style: PrismType.bodySm.copyWith(color: palette.textSecondary),
            ),
            const SizedBox(height: 16),
            Text('What to check', style: PrismType.body),
            const SizedBox(height: 10),
            for (final step in const [
              'The tablet is switched on and awake.',
              'Prism is open on it — not just installed.',
              "It's connected to the venue's Wi-Fi.",
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('·  ',
                        style: PrismType.bodySm
                            .copyWith(color: palette.textSecondary)),
                    Expanded(
                      child: Text(step,
                          style: PrismType.bodySm
                              .copyWith(color: palette.textSecondary)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Text(
              'A room keeps playing its schedule while it is offline, so the '
              'music may be fine even when this says otherwise.',
              style: PrismType.bodySm.copyWith(color: palette.textSecondary),
            ),
            if (Env.supportContact.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text('Still stuck? ${Env.supportContact}',
                  style: PrismType.bodySm.copyWith(color: palette.accent)),
            ],
            const SizedBox(height: 18),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('Close',
                    style: PrismType.body.copyWith(color: palette.accent)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
