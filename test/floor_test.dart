import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/models/playback_state.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/features/floor/widgets/hero_card.dart';
import 'package:prism_venues/main.dart';
import 'package:prism_venues/theme/palette.dart';
import 'package:prism_venues/theme/theme.dart';
import 'package:prism_venues/shared/widgets/auto_button.dart';
import 'package:prism_venues/shared/widgets/mood_tile.dart';
import 'package:prism_venues/shared/widgets/schedule_rail.dart';

/// §2 S01 Floor behavior against the Marina Café seed: default state,
/// confirm-before-switch (S01-3), pause/resume (S01-2 ⇄ S01-1), account
/// menu sign-out (§2.0).
void main() {
  /// [email] decides the role — floor staff are gated out of /schedule, so a
  /// test that needs the mode switch has to sign in as a manager.
  Future<void> pumpFloor(WidgetTester tester,
      {String email = 'floor@marinacafe.com',
      Size size = const Size(1024, 768)}) async {
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
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
  }

  testWidgets('S01-1 default: Marina Café seed state', (tester) async {
    await pumpFloor(tester);

    expect(find.text('NOW PLAYING'), findsOneWidget);
    // Hero mood name + playing tile name. The rail no longer lists dayparts:
    // the mock starts self-driving (S03-1 is the entry frame), so no saved
    // plan is running to show.
    expect(find.text('Afternoon lift'), findsNWidgets(2));
    expect(find.text('Prism is driving'), findsOneWidget);
    expect(find.text('mid-afternoon · ~60% full · clear'), findsOneWidget);
    expect(find.text('Noise'), findsOneWidget);
    expect(find.text('62%'), findsOneWidget);
    expect(find.text('Take over'), findsOneWidget);

    // Moods block.
    expect(find.text('Moods'), findsOneWidget);
    expect(find.text('Tap to change the vibe · one tap'), findsOneWidget);

    // Rail in its self-drive state: no daypart rows, no NOW badge claiming a
    // schedule is running, and it names Schedule as where to change that.
    expect(find.text('RIGHT NOW'), findsOneWidget);
    expect(find.text('Self-drive'), findsOneWidget);
    expect(find.text('Prism is picking the vibe'), findsOneWidget);
    expect(find.text('NOW'), findsNothing);
    expect(find.text('up next'), findsNothing);
    expect(find.textContaining('Switch to Custom plan'), findsOneWidget);
  });

  testWidgets('rail shows the plan once a custom plan is running',
      (tester) async {
    // Manager: floor staff cannot reach /schedule to switch the mode.
    await pumpFloor(tester, email: 'priya@marinacafe.com');

    // Self-drive by default: the plan is hidden.
    expect(find.text('RIGHT NOW'), findsOneWidget);

    // Switching to a custom plan in Schedule must move the Floor rail too.
    await tester.tap(find.text('Schedule'));
    await _settle(tester);
    await tester.tap(find.text('Custom plan'));
    await _settle(tester);
    await tester.tap(find.text('Floor'));
    await _settle(tester);

    expect(find.text("TODAY'S SCHEDULE"), findsOneWidget);
    // The rail's own "Auto" chip, not the hero's AutoButton — both say "Auto",
    // so scope this to the rail or it matches two widgets.
    expect(
      find.descendant(
        of: find.byType(ScheduleRail),
        matching: find.text('Auto'),
      ),
      findsOneWidget,
    );
    expect(find.text('NOW'), findsOneWidget);
    expect(find.text('up next'), findsOneWidget);
    expect(find.text('Prism is picking the vibe'), findsNothing);
  });

  testWidgets('S01-3 confirm gate: cancel keeps mood, confirm switches',
      (tester) async {
    await pumpFloor(tester);

    // Scoped to the MoodTile: the hero shows mood names too.
    final eveningTile = find.descendant(
        of: find.byType(MoodTile), matching: find.text('Evening warmth'));

    // Tap an idle tile → confirm dialog.
    await tester.tap(eveningTile);
    await _settle(tester);
    expect(find.text('Switch to Evening warmth?'), findsOneWidget);
    expect(find.textContaining('energy 3/5', findRichText: true),
        findsOneWidget);

    // Cancel → no change (dismiss to parent, no state change §4).
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(find.text('Afternoon lift'), findsNWidgets(2));

    // Confirm → the room switches.
    await tester.tap(eveningTile);
    await _settle(tester);
    await tester.tap(find.text('Switch the vibe'));
    await _settle(tester);
    // Hero + playing tile switch. Counts are hero+tile / idle tile only —
    // the self-driving rail lists no dayparts to also match.
    expect(find.text('Evening warmth'), findsNWidgets(2));
    expect(find.text('Afternoon lift'), findsOneWidget);

    // Choosing a vibe by hand takes the room OFF its schedule, so the hero must
    // stop claiming Prism is driving — it is not any more — and must offer the
    // way back. The rail's pill follows for the same reason; the two sit inches
    // apart and used to contradict each other.
    expect(find.text('Prism is driving'), findsNothing);
    expect(find.text('Off schedule · you chose this vibe'), findsOneWidget);
    expect(find.text('Off schedule'), findsOneWidget); // rail pill
    // The Auto button is always on screen; overriding switches it out of its
    // resting state so it reads as the way back.
    expect(tester.widget<AutoButton>(find.byType(AutoButton)).active, isFalse);
  });

  testWidgets('Auto is a standing control, not one that appears on override',
      (tester) async {
    await pumpFloor(tester, email: 'manager@marinacafe.com');

    // The point of the feedback this replaced: a venue that has never
    // overridden must still be able to see that letting Prism drive is an
    // option. On the resting screen the button is present and reads as on.
    expect(find.byType(AutoButton), findsOneWidget);
    expect(tester.widget<AutoButton>(find.byType(AutoButton)).active, isTrue);
    expect(find.text('Prism is driving'), findsOneWidget);
  });

  testWidgets('Auto hands the room to the schedule again', (tester) async {
    await pumpFloor(tester, email: 'manager@marinacafe.com');

    // Take the room off schedule the way a manager does.
    await tester.tap(find.text('Evening warmth'));
    await _settle(tester);
    await tester.tap(find.text('Switch the vibe'));
    await _settle(tester);
    expect(tester.widget<AutoButton>(find.byType(AutoButton)).active, isFalse);

    // Confirmed, not immediate — this changes what the room plays (cf. S01-3).
    await tester.tap(find.byType(AutoButton));
    await _settle(tester);
    expect(find.text('Let Prism take it from here?'), findsOneWidget);

    // Cancel leaves the override in place.
    await tester.tap(find.text('Cancel'));
    await _settle(tester);
    expect(find.text('Off schedule · you chose this vibe'), findsOneWidget);

    await tester.tap(find.byType(AutoButton));
    await _settle(tester);
    await tester.tap(find.text('Let Prism drive'));
    await _settle(tester);

    // Back on schedule: the pill flips, the button returns to its resting
    // state, and the mood the manager chose keeps playing — handing back
    // control is not an undo.
    expect(find.text('Prism is driving'), findsOneWidget);
    expect(tester.widget<AutoButton>(find.byType(AutoButton)).active, isTrue);
    expect(find.text('Evening warmth'), findsNWidgets(2));
  });

  testWidgets('the hero survives a phone-width column', (tester) async {
    // Regression: adding the Auto button squeezed the hero's noise meter below
    // the width of its own thumb, and NoiseMeter's clamp(0, w - 14) threw
    // "Invalid argument: 0". A thrown exception renders as a red ErrorWidget
    // over the whole screen — in release too — so this was a crash, not a
    // squashed meter. Landscape had the room to hide it.
    //
    // The hero is pumped alone rather than through the Floor screen because the
    // rest of the app is landscape-first by design (§6-A1: portrait reflow is
    // Phase 4) and still overflows at this width in ways this change did not
    // cause and does not claim to fix.
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPrismTheme(PrismPalette.dark),
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: HeroCard(
              state: const PlaybackState(
                moodId: 'morning-calm',
                paused: false,
                contextLine: 'mid-afternoon · ~60% full · clear',
              ),
              noise: 62,
              onReturnToAuto: () {},
            ),
          ),
        ),
      ),
    );

    // The regression is specifically a *thrown* ArgumentError, which Flutter
    // paints as a red ErrorWidget over the whole screen — in release too.
    // Overflow warnings are not the same class of problem: they are cosmetic,
    // debug-only, and inflated here anyway because the test font (Ahem) draws
    // every glyph as a square, making the 31px mood name roughly twice its
    // real width.
    Object? thrownArgumentError;
    for (var ex = tester.takeException(); ex != null;
        ex = tester.takeException()) {
      if (ex is ArgumentError) thrownArgumentError = ex;
    }
    expect(thrownArgumentError, isNull,
        reason: 'NoiseMeter must not throw when its track is narrower '
            'than the 14px thumb');
    expect(find.byType(ErrorWidget), findsNothing);
    // Both controls still reachable — stacked onto their own row, not dropped.
    expect(find.byType(AutoButton), findsOneWidget);
    expect(find.text('Take over'), findsOneWidget);
  });

  testWidgets('Auto does nothing while it is already on', (tester) async {
    await pumpFloor(tester, email: 'manager@marinacafe.com');

    // Resting state: tapping must not raise the confirm dialog. A live-looking
    // control that re-asks a question already answered is worse than an inert
    // one that plainly reads as "already on".
    await tester.tap(find.byType(AutoButton));
    await _settle(tester);
    expect(find.text('Let Prism take it from here?'), findsNothing);
    expect(find.text('Prism is driving'), findsOneWidget);
  });

  testWidgets('S01-2 pause/resume via the hero button', (tester) async {
    await pumpFloor(tester);

    await tester.tap(find.byIcon(LucideIcons.pause));
    await _settle(tester);
    expect(find.textContaining('tap play to resume', findRichText: true),
        findsOneWidget);
    expect(find.text('Prism is driving'), findsNothing);

    await tester.tap(find.byIcon(LucideIcons.play));
    await _settle(tester);
    expect(find.text('Prism is driving'), findsOneWidget);
  });

  testWidgets('account menu: avatar → Sign out → back to sign-in',
      (tester) async {
    await pumpFloor(tester);

    await tester.tap(find.text('PN'));
    await _settle(tester);
    expect(find.text('Priya Nair'), findsOneWidget);
    expect(find.text('Floor staff'), findsOneWidget);

    await tester.tap(find.text('Sign out'));
    await _settle(tester);
    expect(find.text('Hello!'), findsOneWidget);
  });
}

/// Bounded settle — Floor's EqBars loop never lets pumpAndSettle rest.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));
}
