import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/router.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/main.dart';

/// §4 role journeys: real S00 auth + S01 Floor; remaining tab sections are
/// Phase 2 placeholders, replaced section by section through Phase 3.
///
/// Floor runs the EqBars loop (the app's only designed motion), so these
/// tests use bounded pumps instead of pumpAndSettle.
void main() {
  late ProviderContainer container;

  Future<void> pumpApp(WidgetTester tester) async {
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
    await settle(tester);
  }

  Future<void> go(WidgetTester tester, String location) async {
    container.read(routerProvider).go(location);
    await settle(tester);
  }

  /// Signs in via the real S00-1 screen; MockAuthRepo lands the role from
  /// the email (floor@… → floor, owner@… → owner, else manager).
  Future<void> signInAs(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField).first, email);
    await tester.tap(find.text('Sign in'));
    await settle(tester);
  }

  testWidgets('signed out: any location redirects to /signin', (tester) async {
    await pumpApp(tester);
    expect(find.text('Hello!'), findsOneWidget);

    await go(tester, '/floor');
    expect(find.text('Hello!'), findsOneWidget);

    await go(tester, '/settings');
    expect(find.text('Hello!'), findsOneWidget);
  });

  testWidgets('reset flow edges: email → code → new → sign-in',
      (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Forgot Password'));
    await settle(tester);
    expect(find.text('Reset your password'), findsOneWidget);

    // The field no longer arrives pre-filled. It used to ship seeded with
    // priya@marinacafe.com — the frame's sample value as a production default —
    // so tapping straight through mailed a reset code to a real inbox.
    await tester.tap(find.text('Send verification code'));
    await settle(tester);
    expect(find.text('Enter your email address.'), findsOneWidget);
    expect(find.text('Enter the code'), findsNothing);

    await tester.enterText(
        find.byType(TextField).first, 'manager@marinacafe.com');
    await tester.tap(find.text('Send verification code'));
    await settle(tester);
    expect(find.text('Enter the code'), findsOneWidget);

    await tester.tap(find.text('Verify'));
    await settle(tester);
    expect(find.text('Set a new password'), findsOneWidget);

    // The confirm field is actually compared now. It used to be declared,
    // wired to a field and disposed without ever being read, so a mistyped
    // confirm locked the user out of the account they were recovering.
    final passwordFields = find.byType(TextField);
    await tester.enterText(passwordFields.at(0), 'a-good-password');
    await tester.enterText(passwordFields.at(1), 'a-good-passwrod');
    await tester.tap(find.text('Save new password'));
    await settle(tester);
    expect(find.text('Those two passwords do not match.'), findsOneWidget);

    // Too short is caught before the server has to say so.
    await tester.enterText(passwordFields.at(0), 'short');
    await tester.enterText(passwordFields.at(1), 'short');
    await tester.tap(find.text('Save new password'));
    await settle(tester);
    expect(find.text('Use at least 8 characters.'), findsOneWidget);

    await tester.enterText(passwordFields.at(0), 'a-good-password');
    await tester.enterText(passwordFields.at(1), 'a-good-password');
    await tester.tap(find.text('Save new password'));
    await settle(tester);
    expect(find.text('Hello!'), findsOneWidget);
  });

  testWidgets('floor journey: lands on Floor, gated routes bounce back, '
      'locked nav taps are inert', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'floor@marinacafe.com');
    expect(find.text('NOW PLAYING'), findsOneWidget);

    // Direct navigation to gated routes bounces back to /floor.
    for (final gated in [
      '/schedule',
      '/venues',
      '/venues/add',
      '/venues/marina-cafe',
      '/settings',
    ]) {
      await go(tester, gated);
      expect(find.text('NOW PLAYING'), findsOneWidget,
          reason: '$gated should redirect floor staff back to /floor');
    }

    // Takeover is allowed — real hero "Take over" button → real S02-1.
    await tester.tap(find.text('Take over'));
    await settle(tester);
    expect(find.text('Use your own audio'), findsOneWidget);

    // All three locked nav tabs render locked and taps do nothing.
    await go(tester, '/floor');
    for (final lockedTab in ['Schedule', 'Venues', 'Settings']) {
      await tester.tap(find.text(lockedTab));
      await settle(tester);
      expect(find.text('NOW PLAYING'), findsOneWidget,
          reason: 'locked $lockedTab tab tap must be inert');
    }
  });

  testWidgets('manager journey: lands on Floor, sees single venue, '
      'cannot reach /venues/add', (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'priya@marinacafe.com');
    expect(find.text('NOW PLAYING'), findsOneWidget);

    await go(tester, '/venues');
    expect(find.text('Main floor'), findsOneWidget,
        reason: "manager's /venues IS their single venue (S04-1)");
    expect(find.text('+ Venue'), findsNothing);

    await go(tester, '/venues/add');
    expect(find.text('Main floor'), findsOneWidget,
        reason: '/venues/add must redirect managers back to /venues');

    await go(tester, '/venues/marina-cafe');
    expect(find.text('Main floor'), findsOneWidget);

    await go(tester, '/schedule');
    expect(find.text('Prism is self-driving'), findsOneWidget);

    await go(tester, '/settings');
    expect(find.text("Marina Café · you're a manager"), findsOneWidget);
  });

  testWidgets('owner journey: lands on Venues portfolio, everything open',
      (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'owner@marinacafe.com');
    expect(find.text('Needs attention'), findsOneWidget);

    await tester.tap(find.text('+ Venue'));
    await settle(tester);
    expect(find.text('Add a venue'), findsOneWidget);

    await go(tester, '/venues/marina-cafe');
    expect(find.text('Main floor'), findsOneWidget);

    await go(tester, '/floor');
    expect(find.text('NOW PLAYING'), findsOneWidget);

    await go(tester, '/schedule');
    expect(find.text('Prism is self-driving'), findsOneWidget);
  });

  testWidgets('signed-in user visiting auth routes is sent to their landing',
      (tester) async {
    await pumpApp(tester);
    await signInAs(tester, 'owner@marinacafe.com');
    await go(tester, '/signin');
    expect(find.text('Needs attention'), findsOneWidget);

    await go(tester, '/reset/email');
    expect(find.text('Needs attention'), findsOneWidget);
  });
}

/// Bounded settle: enough pumps to flush routing, zero-latency mocks and the
/// ≤200ms modal transitions, without waiting on infinite animations.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
