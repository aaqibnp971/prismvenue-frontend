import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/router.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/main.dart';

/// Every screen, at phone size, with nothing overflowing.
///
/// The app is iPad-landscape first and says so, but "designed for a tablet" and
/// "unusable on a phone" are different claims. A RenderFlex overflow is not a
/// cosmetic complaint: Flutter paints the striped banner over the content, so
/// whatever was in that corner is gone — and on a venue floor the thing in the
/// corner is a mood tile or a Save button.
///
/// 390×844 is an iPhone 14/15 in portrait, and 320×568 is the smallest phone
/// anyone still carries. Both are checked because they fail differently: the
/// first runs out of width, the second out of height.
///
/// Overflow throws in a test binding, so every route below is its own
/// assertion — no `expect` needed for the layout itself. What the `expect`s
/// check is that the screen actually rendered rather than falling back to an
/// error state that happens not to overflow.
void main() {
  late ProviderContainer container;

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    container = ProviderContainer(overrides: [
      playbackRepoProvider.overrideWith((ref) {
        // The noise ticker never settles, and this file pumps a lot.
        final repo = MockPlaybackRepo(tickNoise: false);
        ref.onDispose(repo.dispose);
        return repo;
      }),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const PrismVenuesApp(),
    ));
    await _settle(tester);
  }

  Future<void> signIn(WidgetTester tester, String email) async {
    await tester.enterText(find.byType(TextField).first, email);
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
  }

  Future<void> go(WidgetTester tester, String location) async {
    container.read(routerProvider).go(location);
    await _settle(tester);
  }

  for (final (label, size) in const [
    ('iPhone portrait', Size(390, 844)),
    ('a small phone', Size(320, 568)),
  ]) {
    testWidgets('$label: sign-in and the reset flow fit', (tester) async {
      await pumpAt(tester, size);
      expect(find.text('Hello!'), findsOneWidget);

      await tester.tap(find.text('Forgot Password'));
      await _settle(tester);
      expect(find.byType(TextField), findsWidgets);
    });

    testWidgets('$label: Floor, Schedule and Settings fit', (tester) async {
      await pumpAt(tester, size);
      await signIn(tester, 'manager@marinacafe.com');

      // Floor — the mood grid, the hero and the schedule rail.
      expect(find.text('Moods'), findsOneWidget);

      await go(tester, '/schedule');
      await _settle(tester);

      await go(tester, '/settings');
      await _settle(tester);
      expect(find.text('Time zone'), findsOneWidget);

      await go(tester, '/takeover');
      await _settle(tester);
    });

    testWidgets('$label: the owner portfolio and a venue fit', (tester) async {
      await pumpAt(tester, size);
      await signIn(tester, 'owner@marinacafe.com');
      expect(find.text('Your venues'), findsOneWidget);

      await go(tester, '/venues/add');
      await _settle(tester);
    });

    testWidgets('$label: the settings sub-screens fit', (tester) async {
      await pumpAt(tester, size);
      await signIn(tester, 'manager@marinacafe.com');

      for (final route in const [
        '/settings/volume',
        '/settings/transitions',
        '/settings/hours',
      ]) {
        await go(tester, route);
        await _settle(tester);
      }
    });
  }
}

/// Bounded settle — the playing mood tile's EqBars loop never lets
/// pumpAndSettle rest.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}
