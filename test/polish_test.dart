import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/main.dart';

/// Phase 4 — §6-A1 portrait reflow, §6-A3 disabled behavior. Pressed states
/// (§6-A2) are transient visuals; covered by the running app, not asserted.
void main() {
  Future<void> pumpApp(WidgetTester tester,
      {required Size size, required String email}) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
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
    // Finding #21 refuses an empty password, as a person would be
    // refused. The mocks accept any non-empty one.
    await tester.enterText(find.byType(TextField).at(1), 'hunter22');
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
  }

  testWidgets('S00-1: the password hint matches the email hint style',
      (tester) async {
    // The obscured field's 18/ls3 treatment is for the typed dots only. When
    // the hint inherited it, "Password" rendered visibly different from
    // "Email" on the sign-in screen.
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: PrismVenuesApp()));
    await _settle(tester);

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .where((f) => f.decoration?.hintText != null)
        .toList();
    final email =
        fields.singleWhere((f) => f.decoration!.hintText == 'Email');
    final password =
        fields.singleWhere((f) => f.decoration!.hintText == 'Password');

    expect(password.decoration!.hintStyle!.fontSize,
        email.decoration!.hintStyle!.fontSize);
    expect(password.decoration!.hintStyle!.letterSpacing,
        email.decoration!.hintStyle!.letterSpacing);
    // The dots themselves keep the wide treatment.
    expect(password.style!.letterSpacing, 3);
  });

  testWidgets('portrait floor: rail renders as a strip below the grid',
      (tester) async {
    await pumpApp(tester,
        size: const Size(768, 1024), email: 'priya@marinacafe.com');

    // Same content as landscape — hero, grid, and the rail (as a strip);
    // an overflow would fail the test via FlutterError. The mock starts
    // self-driving, so the strip carries that state rather than dayparts —
    // it still has to reflow without overflowing.
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('RIGHT NOW'), findsOneWidget);
    expect(find.text('Prism is picking the vibe'), findsOneWidget);
    expect(find.text('Take over'), findsOneWidget);
  });

  testWidgets('portrait floor: daypart strip reflows on a custom plan',
      (tester) async {
    await pumpApp(tester,
        size: const Size(768, 1024), email: 'priya@marinacafe.com');

    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    await tester.tap(find.text('Custom plan'));
    await _settle(tester);
    await tester.tap(find.text('Floor'));
    await _settle(tester);

    // The horizontally-scrolling daypart strip is the wider layout — this is
    // the case that would overflow if the chips did not scroll.
    expect(find.text("TODAY'S SCHEDULE"), findsOneWidget);
    expect(find.text('NOW'), findsOneWidget);
  });

  testWidgets('portrait: takeover, schedule, venues, settings all reflow',
      (tester) async {
    await pumpApp(tester,
        size: const Size(768, 1024), email: 'priya@marinacafe.com');

    await tester.tap(find.text('Take over'));
    await _settle(tester);
    expect(find.text('Use your own audio'), findsOneWidget);

    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    expect(find.text('Prism is self-driving'), findsOneWidget);

    await tester.tap(find.text('Venues'));
    await _settle(tester);
    expect(find.text('Main floor'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await _settle(tester);
    expect(find.text("Marina Café · you're a manager"), findsOneWidget);
  });

  testWidgets(
      '§6-A3 disabled: Add exception with no days selected is inert at 40%',
      (tester) async {
    await pumpApp(tester,
        size: const Size(1024, 768), email: 'priya@marinacafe.com');
    await tester.tap(find.text('Settings'));
    await _settle(tester);
    // Below the fold since findings #10 and #17 added two groups above it.
    await tester.ensureVisible(find.text('Zones & open hours'));
    await _settle(tester);
    await tester.tap(find.text('Zones & open hours'));
    await _settle(tester);
    await tester.tap(find.text('+ Add exception'));
    await _settle(tester);

    // Deselect the prefilled Fri & Sat.
    await tester.tap(find.text('Fri').last);
    await _settle(tester);
    await tester.tap(find.text('Sat').last);
    await _settle(tester);

    // Disabled CTA: tap does nothing, sheet stays open.
    await tester.tap(find.text('Add exception'), warnIfMissed: false);
    await _settle(tester);
    expect(find.text('Which days'), findsOneWidget);

    // Re-select a day → enabled again → adds and closes.
    await tester.tap(find.text('Mon').last);
    await _settle(tester);
    await tester.tap(find.text('Add exception'));
    await _settle(tester);
    expect(find.text('Which days'), findsNothing);
    expect(find.text('Mon'), findsOneWidget); // new exception row
  });
}

/// Bounded settle — chrome may host looping animations.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
