/// Findings #21, #12 and #9 — three small defects with one thing in common:
/// each let the app tell an owner something that was not true.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/session.dart';
import 'package:prism_venues/data/models/venue.dart';
import 'package:prism_venues/data/models/zone.dart';
import 'package:prism_venues/features/venues/portfolio_screen.dart';
import 'package:prism_venues/main.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  Future<ProviderContainer> pumpApp(WidgetTester tester,
      {Size size = const Size(1024, 768)}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const PrismVenuesApp(),
    ));
    await _settle(tester);
    return container;
  }

  group('#21 sign-in checks the fields before sending', () {
    testWidgets('an empty password is refused on the device', (tester) async {
      // It used to go to the server, which answers with the deliberately vague
      // "That email or password is not right" — correct for a wrong password
      // and useless for a blank box.
      final container = await pumpApp(tester);

      await tester.enterText(
          find.byType(TextField).first, 'owner@marinacafe.com');
      await tester.tap(find.text('Sign in'));
      await _settle(tester);

      expect(find.text('Enter your password.'), findsOneWidget);
      expect(container.read(sessionProvider), isNull,
          reason: 'nothing should have been sent');
    });

    testWidgets('an empty email is refused, and named', (tester) async {
      await pumpApp(tester);

      await tester.enterText(find.byType(TextField).at(1), 'hunter22');
      await tester.tap(find.text('Sign in'));
      await _settle(tester);

      expect(find.text('Enter your email.'), findsOneWidget);
    });

    testWidgets('both blank says so once, not twice', (tester) async {
      await pumpApp(tester);

      await tester.tap(find.text('Sign in'));
      await _settle(tester);

      expect(find.text('Enter your email and password.'), findsOneWidget);
    });

    testWidgets('a filled form still signs in', (tester) async {
      // The guard must not become the new defect.
      final container = await pumpApp(tester);

      await tester.enterText(
          find.byType(TextField).first, 'owner@marinacafe.com');
      await tester.enterText(find.byType(TextField).at(1), 'hunter22');
      await tester.tap(find.text('Sign in'));
      await _settle(tester);

      expect(container.read(sessionProvider), isNotNull);
    });
  });

  group('#12 the Self-drive card says what the product does', () {
    testWidgets('it no longer claims to read the room', (tester) async {
      // "Prism reads the room — crowd, time of day, noise — and picks the vibe
      // on its own." Nothing reads a room: there is no venues context profile,
      // and a self-driving zone is skipped by the scheduler, so it holds one
      // mood. That copy is why an owner would choose the option that silently
      // stops their plan.
      await pumpApp(tester);
      await tester.enterText(
          find.byType(TextField).first, 'manager@marinacafe.com');
      await tester.enterText(find.byType(TextField).at(1), 'hunter22');
      await tester.tap(find.text('Sign in'));
      await _settle(tester);

      await tester.tap(find.text('Schedule'));
      await _settle(tester);

      expect(find.textContaining('reads the room'), findsNothing);
      expect(find.textContaining('crowd'), findsNothing);
      // And says the thing that actually matters to somebody choosing it.
      expect(find.textContaining('does not follow your weekly plan'),
          findsOneWidget);
    });
  });

  group('#9 a venue needs at least one zone', () {
    testWidgets('creating one with no zones is refused, with a reason',
        (tester) async {
      // "Test Clinic" was created with 0 zones in the walkthrough and sat in
      // the portfolio among the quiet healthy rows, unable to play anything.
      await pumpApp(tester);
      await tester.enterText(
          find.byType(TextField).first, 'owner@marinacafe.com');
      await tester.enterText(find.byType(TextField).at(1), 'hunter22');
      await tester.tap(find.text('Sign in'));
      await _settle(tester);

      await tester.tap(find.text('+ Venue'));
      await _settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Test Clinic');
      await _settle(tester);

      await tester.tap(find.text('Add venue'));
      await _settle(tester);

      expect(find.textContaining('Add at least one zone'), findsOneWidget);
    });

    test('one that already has none is ranked with the rows needing attention',
        () {
      // Refusing new ones does nothing for the ones that already exist — made
      // before the check, or left behind when a venue's last zone is removed.
      // A zero-zone venue has no zone to be unhealthy, so it ranked as healthy.
      const empty = Venue(id: 'v-empty', name: 'Test Clinic', zones: []);
      const healthy = Venue(id: 'v-ok', name: 'Harbor House', zones: [
        Zone(
          id: 'z-1',
          name: 'Dining',
          status: ZoneStatus.auto,
          moodId: 'daytime-flow',
        ),
      ]);

      expect(needsAttentionFirst([healthy, empty]).first.id, 'v-empty');
    });
  });
}
