import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/venue_header.dart';
import '../../data/models/guardrails.dart';
import '../../data/repositories/settings_repo.dart';
import '../../shared/widgets/prism_top_bar.dart';
import '../../shared/widgets/seg_toggle.dart';
import '../../shared/widgets/settings_row.dart';
import '../../theme/palette.dart';
import '../../theme/typography.dart';
import 'everyday_hours_sheet.dart';
import 'exception_sheet.dart';

/// S05-6 "Open hours — one default, only the exceptions stand out". Title
/// "Open hours"; seg "Everyday timings" (single full-width option, accent);
/// default row "Every day · 7am–11pm" → S05-11; exceptions list + "+ Add
/// exception" → S05-10.
class OpenHoursScreen extends ConsumerWidget {
  const OpenHoursScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider);
    if (user == null) return const SizedBox.shrink(); // router redirects
    final palette = Theme.of(context).extension<PrismPalette>()!;
    final hours = ref.watch(openHoursProvider).value ?? const OpenHours();

    return Scaffold(
      body: Column(
        children: [
          // §2.0: venue name stays in the title slot; "Open hours" is the
          // pinned context-line example.
          PrismTopBar(
            title: ref.watch(venueNameProvider),
            subtitle: 'Open hours',
            showBack: true,
            onBack: () => context.go('/settings'),
            user: user,
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: SizedBox(
                width: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // §1.4 screenTitle ("Open hours" is its named example).
                    Text('Open hours',
                        style: PrismType.displaySerif.copyWith(
                            fontSize: 22, color: palette.textPrimary)),
                    const SizedBox(height: 14),
                    const SegToggle(
                      options: ['Everyday timings'],
                      selected: 0,
                    ),
                    const SizedBox(height: 12),
                    SettingsRow(
                      title: 'Every day',
                      value: hours.rangeLabel,
                      onTap: () => showEverydayHoursSheet(context, ref),
                    ),
                    const SizedBox(height: 16),
                    Text('EXCEPTIONS',
                        style: PrismType.labelCaps
                            .copyWith(color: palette.textSecondary)),
                    const SizedBox(height: 8),
                    for (final exception in hours.exceptions) ...[
                      SettingsRow(
                        title: exception.daysLabel,
                        sub: exception.everyWeek ? 'Every week' : 'Just once',
                        value: exception.closedAllDay
                            ? 'Closed'
                            : '${OpenHours.timeLabel(exception.openHour, exception.openMinute)}–'
                                '${OpenHours.timeLabel(exception.closeHour, exception.closeMinute)}',
                        // Tap to edit or delete. The chevron is what signals
                        // it is tappable at all — without it these rows read
                        // as permanent, which is exactly how they behaved.
                        onTap: () => showExceptionSheet(context, ref,
                            existing: exception),
                      ),
                      const SizedBox(height: 8),
                    ],
                    GestureDetector(
                      onTap: () => showExceptionSheet(context, ref),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text('+ Add exception',
                            style: PrismType.button.copyWith(
                                fontSize: 12.5, color: palette.accent)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
