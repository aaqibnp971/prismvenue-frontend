/// Finding #16 — "Offline" with no detail and no next step.
///
/// The old row named a problem and stopped there: an owner could not tell five
/// minutes from five days, and had nothing to do about it but phone whoever
/// installed the venue. These cover the two halves of the fix — the age of the
/// problem, and something to act on.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/models/zone.dart';
import 'package:prism_venues/features/venues/widgets/offline_help_sheet.dart';
import 'package:prism_venues/theme/palette.dart';
import 'package:prism_venues/theme/theme.dart';

void main() {
  group('lastSeenLabel', () {
    final now = DateTime(2026, 9, 26, 12, 0);

    test('a zone nothing has ever reported on has no time at all', () {
      // Null must not be rendered as a time. "Never" is a setup problem, and
      // it reads completely differently from an outage.
      expect(lastSeenLabel(null, now: now), isNull);
    });

    test('very recent reads as just now, not "0 minutes ago"', () {
      expect(
        lastSeenLabel(now.subtract(const Duration(seconds: 20)), now: now),
        'just now',
      );
    });

    test('singular and plural are both right', () {
      expect(
        lastSeenLabel(now.subtract(const Duration(minutes: 1)), now: now),
        '1 minute ago',
      );
      expect(
        lastSeenLabel(now.subtract(const Duration(minutes: 12)), now: now),
        '12 minutes ago',
      );
      expect(
        lastSeenLabel(now.subtract(const Duration(hours: 1)), now: now),
        '1 hour ago',
      );
      expect(
        lastSeenLabel(now.subtract(const Duration(days: 5)), now: now),
        '5 days ago',
      );
    });

    test('coarsens as it ages, so the unit matches the decision', () {
      // 90 minutes is "1 hour ago", not "90 minutes ago": the exact figure is
      // noise to somebody deciding whether to walk across a building.
      expect(
        lastSeenLabel(now.subtract(const Duration(minutes: 90)), now: now),
        '1 hour ago',
      );
      expect(
        lastSeenLabel(now.subtract(const Duration(hours: 30)), now: now),
        '1 day ago',
      );
    });

    test('a clock skewed into the future reads as just now, never negative', () {
      // The venue tablet's clock and the server's need not agree, and
      // "-3 minutes ago" would look like a bug in the product.
      expect(
        lastSeenLabel(now.add(const Duration(minutes: 3)), now: now),
        'just now',
      );
    });
  });

  group('the offline help sheet', () {
    Future<void> show(WidgetTester tester, Zone zone) async {
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
          // The sheet reads PrismPalette off the theme, as every Prism widget
          // does; a bare MaterialApp has no such extension.
          theme: buildPrismTheme(PrismPalette.dark),
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => showOfflineHelp(context, zone),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
    }

    testWidgets('says how long the room has been quiet', (tester) async {
      await show(
        tester,
        Zone(
          id: 'z1',
          name: 'Bar',
          status: ZoneStatus.offline,
          moodId: 'peak',
          lastSeenAt: DateTime.now().subtract(const Duration(hours: 3)),
        ),
      );

      expect(find.textContaining('Bar is offline'), findsOneWidget);
      expect(find.textContaining('3 hours ago'), findsOneWidget);
    });

    testWidgets('a room never reported on is a setup problem, not an outage',
        (tester) async {
      await show(
        tester,
        const Zone(
          id: 'z1',
          name: 'Treatment Room 1',
          status: ZoneStatus.offline,
          moodId: 'peak',
        ),
      );

      expect(find.textContaining('has ever reported'), findsOneWidget);
      expect(find.textContaining('ago'), findsNothing);
    });

    testWidgets('gives steps one person in the room can actually do',
        (tester) async {
      await show(
        tester,
        const Zone(
          id: 'z1',
          name: 'Bar',
          status: ZoneStatus.offline,
          moodId: 'peak',
        ),
      );

      expect(find.textContaining('switched on'), findsOneWidget);
      expect(find.textContaining('Prism is open'), findsOneWidget);
      expect(find.textContaining('Wi-Fi'), findsOneWidget);
    });

    testWidgets('says the music may still be playing', (tester) async {
      // The most reassuring fact available, and the least obvious: the room
      // keeps its schedule through an outage because the engine is on-device.
      await show(
        tester,
        const Zone(
          id: 'z1',
          name: 'Bar',
          status: ZoneStatus.offline,
          moodId: 'peak',
        ),
      );

      expect(find.textContaining('keeps playing its schedule'), findsOneWidget);
    });

    testWidgets('names nobody when no support contact is configured',
        (tester) async {
      // A screen that says "contact support" and then names nobody is worse
      // than one that stays quiet. PRISM_SUPPORT_CONTACT is unset in tests.
      await show(
        tester,
        const Zone(
          id: 'z1',
          name: 'Bar',
          status: ZoneStatus.offline,
          moodId: 'peak',
        ),
      );

      expect(find.textContaining('Still stuck?'), findsNothing);
    });
  });
}
