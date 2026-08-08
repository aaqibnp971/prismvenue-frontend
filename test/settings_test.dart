import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/router.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/main.dart';
import 'package:prism_venues/shared/widgets/confirm_dialog.dart';

/// §2 S05 Guardrails & settings: home values, volume policy, transitions,
/// open hours (+ sheets + time dial), zone detail, and the S05-4 takeover
/// gate on the floor role.
void main() {
  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester, {required String email}) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container = ProviderContainer(overrides: [
      playbackRepoProvider.overrideWith((ref) {
        final repo = MockPlaybackRepo(tickNoise: false);
        ref.onDispose(repo.dispose);
        return repo;
      }),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PrismVenuesApp(),
      ),
    );
    await _settle(tester);
    await tester.enterText(find.byType(TextField).first, email);
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
  }

  Future<void> toSettings(WidgetTester tester) async {
    await tester.tap(find.text('Settings'));
    await _settle(tester);
  }

  testWidgets('S05-1 home: pinned rows and seed values', (tester) async {
    await pumpApp(tester, email: 'priya@marinacafe.com');
    await toSettings(tester);

    expect(find.text("Marina Café · you're a manager"), findsOneWidget);
    expect(find.text('Volume policy'), findsOneWidget);
    expect(find.text('26–70%'), findsOneWidget);
    expect(find.text('Transition smoothness'), findsOneWidget);
    expect(find.text('Gentle'), findsOneWidget);
    expect(find.text('Who can take over'), findsOneWidget);
    expect(find.text('Managers + floor'), findsOneWidget);
    expect(find.text('Zones & open hours'), findsOneWidget);
    expect(find.text('2 · 7am–11pm'), findsOneWidget);
    expect(find.text('Venue / zone offline'), findsOneWidget);
    expect(find.text('Left in takeover too long'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('S05-2 volume policy: leeway seg + quiet-hours toggle persist',
      (tester) async {
    await pumpApp(tester, email: 'priya@marinacafe.com');
    await toSettings(tester);

    await tester.tap(find.text('Volume policy'));
    await _settle(tester);
    expect(find.text('This zone'), findsOneWidget);
    expect(find.text('Quietest it can go'), findsOneWidget);
    expect(find.text('26%'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
    expect(find.text('Quiet hours'), findsOneWidget);
    expect(find.text('After 10:00 pm · cap at 55%'), findsOneWidget);

    await tester.tap(find.text('Full band'));
    await _settle(tester);

    // Back → home still shows the band value.
    await tester.tap(find.byType(GestureDetector).first); // top-bar back
    await _settle(tester);
    expect(find.text('26–70%'), findsOneWidget);
  });

  testWidgets('S05-3 transitions: selecting updates the home row value',
      (tester) async {
    await pumpApp(tester, email: 'priya@marinacafe.com');
    await toSettings(tester);

    await tester.tap(find.text('Transition smoothness'));
    await _settle(tester);
    expect(find.text('Seamless'), findsOneWidget);
    expect(find.text('~35s'), findsOneWidget);

    await tester.tap(find.text('Seamless'));
    await _settle(tester);

    await tester.tap(find.byType(GestureDetector).first); // top-bar back
    await _settle(tester);
    expect(find.text('Seamless'), findsOneWidget); // home row value
  });

  testWidgets(
      'S05-6/10/11/12: everyday sheet, time dial, and adding an exception',
      (tester) async {
    await pumpApp(tester, email: 'priya@marinacafe.com');
    await toSettings(tester);

    await tester.tap(find.text('Zones & open hours'));
    await _settle(tester);
    expect(find.text('Everyday timings'), findsOneWidget);
    expect(find.text('Every day'), findsOneWidget);
    expect(find.text('7am–11pm'), findsOneWidget);
    // Seeded S05-10 exception.
    expect(find.text('Fri & Sat'), findsOneWidget);
    expect(find.text('7am–1am'), findsOneWidget);

    // S05-11 sheet → S05-12 dial via the Opens field.
    await tester.tap(find.text('Every day'));
    await _settle(tester);
    expect(find.text('Everyday hours'), findsOneWidget);
    expect(find.text('Open 16 hours.'), findsOneWidget);

    await tester.tap(find.text('7:00 am'));
    await _settle(tester);
    expect(find.text('Opening time'), findsOneWidget);
    await tester.tap(find.text('9:00')); // quick chip
    await _settle(tester);
    await tester.tap(find.textContaining('Set 9:00'));
    await _settle(tester);
    expect(find.text('9:00 am'), findsOneWidget);
    expect(find.text('Open 14 hours.'), findsOneWidget);

    await tester.tap(find.text('Save hours'));
    await _settle(tester);
    expect(find.text('9am–11pm'), findsOneWidget);

    // S05-10 add exception with defaults (Fri & Sat 7am–1am).
    await tester.tap(find.text('+ Add exception'));
    await _settle(tester);
    expect(find.text('Which days'), findsOneWidget);
    expect(find.text('Closed all day'), findsOneWidget);
    await tester.tap(find.text('Add exception'));
    await _settle(tester);
    expect(find.text('Fri & Sat'), findsNWidgets(2));
  });

  testWidgets('S05-5 zone detail: reached from S04-1, Remove zone works',
      (tester) async {
    await pumpApp(tester, email: 'priya@marinacafe.com');
    await tester.tap(find.text('Venues'));
    await _settle(tester);

    await tester.tap(find.text('Main floor'));
    await _settle(tester);
    expect(find.text('Zone name'), findsOneWidget);
    expect(find.text('Prism Player 01'), findsOneWidget);
    expect(find.text('Remove zone'), findsOneWidget);

    // Destructive, so it confirms. The app already gates *changing the music*
    // behind a modal; removing a room's whole configuration used to take one
    // undoable tap.
    await tester.tap(find.text('Remove zone'));
    await _settle(tester);
    expect(find.text('Remove this zone?'), findsOneWidget);

    // Cancel leaves the zone alone.
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(find.text('Remove this zone?'), findsNothing);
    expect(find.text('Zone name'), findsOneWidget);

    await tester.tap(find.text('Remove zone'));
    await _settle(tester);
    await tester.tap(find.descendant(
      of: find.byType(ConfirmDialog),
      matching: find.text('Remove zone'),
    ));
    await _settle(tester);
    expect(find.text('Main floor'), findsNothing);
    expect(find.text('Terrace'), findsOneWidget);
  });

  testWidgets('S05-4 gate: Manager-only locks floor takeover', (tester) async {
    await pumpApp(tester, email: 'priya@marinacafe.com');
    await toSettings(tester);

    await tester.tap(find.text('Who can take over'));
    await _settle(tester);
    expect(find.text('Manager + Floor'), findsOneWidget);
    await tester.tap(find.text('Manager'));
    await _settle(tester);
    expect(find.text('Manager'), findsOneWidget); // home row value updated

    // Sign out, sign in as floor staff: takeover is now gated.
    await tester.tap(find.text('PN'));
    await _settle(tester);
    await tester.tap(find.text('Sign out'));
    await _settle(tester);
    await tester.enterText(
        find.byType(TextField).first, 'floor@marinacafe.com');
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
    expect(find.text('NOW PLAYING'), findsOneWidget);

    container.read(routerProvider).go('/takeover');
    await _settle(tester);
    expect(find.text('NOW PLAYING'), findsOneWidget,
        reason: '/takeover must bounce floor staff when Manager-only');

    // Hero button tap also bounces back to Floor.
    await tester.tap(find.text('Take over'));
    await _settle(tester);
    expect(find.text('NOW PLAYING'), findsOneWidget);
  });
}

/// Bounded settle — chrome may host looping animations.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
