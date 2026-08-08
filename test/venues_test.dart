import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/models/venue.dart';
import 'package:prism_venues/data/models/zone.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/features/venues/portfolio_screen.dart';
import 'package:prism_venues/main.dart';

/// §2 S04 Venues: owner triage portfolio, quick-fix, drill-in, and the
/// add-venue → add-zone flow.
void main() {
  group('S04-2 needs-attention ordering', () {
    Venue venue(String name, ZoneStatus status) => Venue(
          id: name,
          name: name,
          zones: [Zone(id: '$name-z', name: 'Z', status: status, moodId: 'peak')],
        );

    test('problems rise above healthy venues', () {
      // The API orders by created_at, so this is the shape that used to reach
      // the screen: an offline venue sitting below healthy ones, under a chip
      // reading "Needs attention".
      final sorted = needsAttentionFirst([
        venue('Healthy A', ZoneStatus.auto),
        venue('Healthy B', ZoneStatus.auto),
        venue('Offline', ZoneStatus.offline),
        venue('Off schedule', ZoneStatus.offSchedule),
      ]);

      expect([for (final v in sorted) v.name],
          ['Offline', 'Off schedule', 'Healthy A', 'Healthy B']);
    });

    test('offline outranks off-schedule', () {
      // A room nobody can reach needs someone to walk to it; an overridden one
      // is a tap away from fixed.
      final sorted = needsAttentionFirst([
        venue('Off schedule', ZoneStatus.offSchedule),
        venue('Offline', ZoneStatus.offline),
      ]);

      expect(sorted.first.name, 'Offline');
    });

    test('ties keep the server order, so the list does not reshuffle', () {
      final sorted = needsAttentionFirst([
        venue('First', ZoneStatus.auto),
        venue('Second', ZoneStatus.auto),
        venue('Third', ZoneStatus.auto),
      ]);

      expect([for (final v in sorted) v.name], ['First', 'Second', 'Third']);
    });
  });

  Future<void> pumpPortfolio(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
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
    await tester.enterText(
        find.byType(TextField).first, 'owner@marinacafe.com');
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
  }

  testWidgets('S04-2 portfolio: needs-attention order, shouting problems, '
      'quiet healthy rows', (tester) async {
    await pumpPortfolio(tester);

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('+ Venue'), findsOneWidget);
    expect(find.text('Dockside'), findsOneWidget);
    expect(find.text('Marina Café'), findsOneWidget);
    expect(find.text('Harbor House'), findsOneWidget);

    // Problems shout: offline (red) and off-schedule (amber + quick-fix).
    expect(find.textContaining('Offline'), findsOneWidget);
    expect(find.textContaining('Off schedule'), findsOneWidget);
    expect(find.text('Return to Auto'), findsOneWidget);
    // Healthy rows whisper — the S04-2 example sub, no % values anywhere.
    expect(find.text('1 zone · Peak'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('S04-2 quick-fix: Return to Auto quiets the row',
      (tester) async {
    await pumpPortfolio(tester);

    await tester.tap(find.text('Return to Auto'));
    await _settle(tester);
    expect(find.text('Return to Auto'), findsNothing);
    expect(find.textContaining('Off schedule'), findsNothing);
    expect(find.text('2 zones · Afternoon lift'), findsOneWidget);
  });

  testWidgets('S04-1 drill-in: venue header + zone rows with statuses',
      (tester) async {
    await pumpPortfolio(tester);

    await tester.tap(find.text('Marina Café'));
    await _settle(tester);
    expect(find.text('Main floor'), findsOneWidget);
    expect(find.text('Terrace'), findsOneWidget);
    expect(find.text('Auto · Afternoon lift'), findsOneWidget);
    expect(find.text('Off schedule · auto in 42 min'), findsOneWidget);

    // Quick-fix works here too.
    await tester.tap(find.text('Return to Auto'));
    await _settle(tester);
    expect(find.text('Auto · Evening warmth'), findsOneWidget);
  });

  testWidgets('S04-1 "Open floor": switches the whole app to that zone',
      (tester) async {
    // Manager with two zones — the picker's home case.
    await tester.binding.setSurfaceSize(const Size(1024, 768));
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
    await tester.enterText(
        find.byType(TextField).first, 'priya@marinacafe.com');
    await tester.tap(find.text('Sign in'));
    await _settle(tester);

    // Signed in operating Main floor.
    expect(find.text('Main floor · online'), findsOneWidget);

    await tester.tap(find.text('Venues'));
    await _settle(tester);

    // Two zones → every row offers Open floor.
    expect(find.text('Open floor'), findsNWidgets(2));

    // Open the Terrace's floor: rows follow mock order, so .at(1) is Terrace.
    await tester.tap(find.text('Open floor').at(1));
    await _settle(tester);

    // Landed on Floor, and the whole session now points at the Terrace —
    // the top bar follows the switched zone.
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Terrace · online'), findsOneWidget);
    expect(find.text('Main floor · online'), findsNothing);
  });

  testWidgets('a single-zone venue offers no "Open floor"', (tester) async {
    await pumpPortfolio(tester);

    await tester.tap(find.text('Harbor House'));
    await _settle(tester);

    expect(find.text('Dining room'), findsOneWidget);
    // One zone: there is nothing to switch between.
    expect(find.text('Open floor'), findsNothing);
  });


  testWidgets('M-04 an off-schedule zone can still be opened', (tester) async {
    await pumpPortfolio(tester);
    await tester.tap(find.text('Marina Café'));
    await _settle(tester);

    // Terrace is the seeded off-schedule zone. Its row used to be inert, so the
    // rows a manager most wants to inspect were the only ones they could not
    // open -- you had to fix a zone before you could look at why it needed
    // fixing.
    await tester.tap(find.text('Terrace'));
    await _settle(tester);

    expect(find.text('Zone name'), findsOneWidget);
  });

  testWidgets('S04-3/4: add venue with a zone from the sheet',
      (tester) async {
    await pumpPortfolio(tester);

    await tester.tap(find.text('+ Venue'));
    await _settle(tester);
    expect(find.text('Add a venue'), findsOneWidget);
    expect(find.text('Every day · 7am–11pm'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Sunset Rooftop');
    await tester.tap(find.text('+ Add zone'));
    await _settle(tester);
    expect(find.text('Add a zone'), findsOneWidget);
    expect(find.textContaining('one area with its own speakers'),
        findsOneWidget);

    // The field is empty — "Back patio" is a hint now, not a value. Shipped as
    // a default it meant "+ Add zone" then "Add zone" created a zone actually
    // called Back patio.
    await tester.tap(find.text('Add zone'));
    await _settle(tester);
    expect(find.text('Back patio'), findsNothing); // no zone chip added

    // Naming it works.
    await tester.tap(find.text('+ Add zone'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Rooftop bar');
    await tester.tap(find.text('Add zone'));
    await _settle(tester);
    expect(find.text('Rooftop bar'), findsOneWidget); // zone chip

    await tester.tap(find.text('Add venue'));
    await _settle(tester);
    expect(find.text('Sunset Rooftop'), findsOneWidget);
    expect(find.text('1 zone · Daytime flow'), findsOneWidget);
  });
}

/// Bounded settle — chrome may host looping animations.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
