import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/session.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/models/venue.dart';
import 'package:prism_venues/data/models/zone.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/features/floor/widgets/hero_card.dart';
import 'package:prism_venues/features/venues/portfolio_screen.dart';
import 'package:prism_venues/main.dart';
import 'package:prism_venues/shared/widgets/confirm_dialog.dart';
import 'package:prism_venues/shared/widgets/mood_tile.dart';
import 'package:prism_venues/shared/widgets/zone_row.dart' as rows;

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
        // Overridden only to stop the noise ticker, which never lets a pump
        // settle. The zone resolver has to be passed through as well —
        // without it the mock collapses every room into one bucket and the
        // estate looks like it shares a single mood, which is precisely what
        // the tests below exist to disprove.
        final repo = MockPlaybackRepo(
          tickNoise: false,
          zoneId: () => ref.read(currentZoneIdProvider),
        );
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
        // Overridden only to stop the noise ticker, which never lets a pump
        // settle. The zone resolver has to be passed through as well —
        // without it the mock collapses every room into one bucket and the
        // estate looks like it shares a single mood, which is precisely what
        // the tests below exist to disprove.
        final repo = MockPlaybackRepo(
          tickNoise: false,
          zoneId: () => ref.read(currentZoneIdProvider),
        );
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

    // Every row EXCEPT the one already being operated. Main floor is the
    // signed-in zone, so offering to switch to it would be a control that
    // does nothing; the Terrace is the only real destination.
    expect(find.text('Open floor'), findsOneWidget);

    await tester.tap(find.text('Open floor'));
    await _settle(tester);

    // Landed on Floor, and the whole session now points at the Terrace —
    // the top bar follows the switched zone.
    expect(find.text('NOW PLAYING'), findsOneWidget);
    expect(find.text('Terrace · online'), findsOneWidget);
    expect(find.text('Main floor · online'), findsNothing);
  });

  testWidgets('a single-zone venue in the estate still offers "Open floor"',
      (tester) async {
    // The inverse of the assertion this replaced, and the reason it changed.
    //
    // The rule used to be `venue.zones.length > 1` — "one zone, nothing to
    // switch between" — which is true inside a venue and wrong across an
    // estate. Harbor House holds one zone, but it is a DIFFERENT venue from
    // the one this session is operating, so pointing the app at it is exactly
    // the switch an owner needs. Under the old rule an owner whose venues each
    // held one zone had no way to change venue at all: every Floor, Schedule
    // and Settings tab stayed on whichever room sign-in happened to pick.
    await pumpPortfolio(tester);

    await tester.tap(find.text('Harbor House'));
    await _settle(tester);

    expect(find.text('Dining room'), findsOneWidget);
    expect(find.text('Open floor'), findsOneWidget);
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

  // --- Operating several venues independently --------------------------------

  /// Points the app at [zoneName] inside [venueName] the way a manager does:
  /// Venues → the venue → "Open floor" on that row.
  Future<void> openFloorOf(
      WidgetTester tester, String venueName, String zoneName) async {
    await tester.tap(find.text('Venues'));
    await _settle(tester);
    await tester.tap(find.text(venueName));
    await _settle(tester);
    // The row's own action, not the first on screen — venues hold several.
    await tester.tap(find.descendant(
        of: find.ancestor(
            of: find.text(zoneName), matching: find.byType(rows.ZoneRow)),
        matching: find.text('Open floor')));
    await _settle(tester);
  }

  Future<void> switchMoodTo(WidgetTester tester, String mood) async {
    await tester.tap(find.descendant(
        of: find.byType(MoodTile), matching: find.text(mood)));
    await _settle(tester);
    // S01-3: nothing the room will hear happens without a confirm.
    await tester.tap(find.text('Switch the vibe'));
    await _settle(tester);
  }

  testWidgets('each venue holds its own mood', (tester) async {
    // The headline of the whole estate flow: an owner sets Harbor House to
    // Morning calm and Marina Café to Peak, and neither move touches the
    // other. `zone_state` has one row per zone, so this is what the schema
    // already says — the app just had no way to express it, because "Open
    // floor" was hidden on single-zone venues and the mock held one shared
    // PlaybackState for the entire estate.
    await pumpPortfolio(tester);

    await openFloorOf(tester, 'Harbor House', 'Dining room');
    await switchMoodTo(tester, 'Morning calm');
    expect(find.text('Dining room · online'), findsOneWidget);

    await openFloorOf(tester, 'Marina Café', 'Terrace');
    // Arriving at a room nobody has touched shows ITS state, not the mood just
    // set two screens ago.
    expect(find.descendant(of: find.byType(HeroCard),
        matching: find.text('Morning calm')), findsNothing);
    await switchMoodTo(tester, 'Peak');

    // Back to Harbor House: still Morning calm. If the two rooms shared state
    // this would read Peak.
    await openFloorOf(tester, 'Harbor House', 'Dining room');
    expect(
        find.descendant(
            of: find.byType(HeroCard), matching: find.text('Morning calm')),
        findsOneWidget);
  });

  testWidgets('each venue holds its own schedule mode', (tester) async {
    // "…and manage independently like the schedule". `zone_guardrails` is
    // per-zone too, so switching Harbor House onto a custom plan must leave
    // Marina Café self-driving.
    await pumpPortfolio(tester);

    await openFloorOf(tester, 'Harbor House', 'Dining room');
    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    await tester.tap(find.text('Custom plan'));
    await _settle(tester);
    expect(find.text('Custom plan'), findsWidgets);

    await openFloorOf(tester, 'Marina Café', 'Terrace');
    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    // Untouched, so still on the S03-1 entry frame.
    expect(find.text('Prism is self-driving'), findsOneWidget);
  });

  testWidgets('a venue with no zones can be given one', (tester) async {
    // Removing a venue's last zone used to be terminal: every zone-scoped
    // screen throws `no_zone_selected`, and no control anywhere could create a
    // zone — they existed only as part of POST /venues. An owner looking at a
    // "0 zones" row had nothing they could do about it.
    await pumpPortfolio(tester);

    await tester.tap(find.text('Harbor House'));
    await _settle(tester);
    await tester.tap(find.text('Dining room'));
    await _settle(tester);
    await tester.tap(find.text('Remove zone'));
    await _settle(tester);
    // The screen's button and the dialog's confirm share a label.
    await tester.tap(find.descendant(
        of: find.byType(ConfirmDialog), matching: find.text('Remove zone')));
    await _settle(tester);

    // Removal lands back on the venue, which now has nothing to show.
    expect(find.text('No zones yet'), findsOneWidget);

    await tester.tap(find.text('+ Zone'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Dining room');
    await tester.tap(find.text('Add zone'));
    await _settle(tester);

    expect(find.text('No zones yet'), findsNothing);
    expect(find.text('Dining room'), findsOneWidget);
    // A fresh zone lands on auto with the server's default mood, so it is
    // immediately operable rather than needing a second fix.
    expect(find.text('Auto · Daytime flow'), findsOneWidget);
  });

  testWidgets('a duplicate zone name is refused, not silently dropped',
      (tester) async {
    // zones has unique (venue_id, name). The mock has to fail the way the API
    // fails or the screen's error path is never really exercised.
    await pumpPortfolio(tester);

    await tester.tap(find.text('Marina Café'));
    await _settle(tester);
    await tester.tap(find.text('+ Zone'));
    await _settle(tester);
    await tester.enterText(find.byType(TextField).last, 'Terrace');
    await tester.tap(find.text('Add zone'));
    await _settle(tester);

    expect(find.textContaining('already uses that name'), findsOneWidget);
  });
}

/// Bounded settle — chrome may host looping animations.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
