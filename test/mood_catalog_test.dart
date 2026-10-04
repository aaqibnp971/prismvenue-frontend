/// The mood catalogue: moods as data rather than as six compiled constants.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/roles.dart';
import 'package:prism_venues/app/session.dart';
import 'package:prism_venues/data/mock/mock_mood_repo.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/models/playback_state.dart';
import 'package:prism_venues/data/models/user.dart';
import 'package:prism_venues/data/repositories/mood_repo.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/engine/prism_engine.dart';
import 'package:prism_venues/engine/prism_engine_native.dart';
import 'package:prism_venues/features/floor/widgets/confirm_vibe_dialog.dart';
import 'package:prism_venues/features/floor/widgets/mood_grid.dart';
import 'package:prism_venues/features/schedule/starter_templates.dart';
import 'package:prism_venues/main.dart';
import 'package:prism_venues/shared/widgets/mood_tile.dart';
import 'package:prism_venues/theme/moods.dart';
import 'package:prism_venues/theme/palette.dart';
import 'package:prism_venues/theme/theme.dart';

const _ownSet = '11111111-2222-4333-8444-555555555555';

/// A venue's own two moods: one with a tempo, one without.
const _quietPremium = Mood(
  id: 'lnl-quiet-premium',
  name: 'Quiet Premium',
  dotDark: Color(0xFFF5A623),
  dotLight: Color(0xFFE08F0E),
  gradStart: Color(0xFFF7AE33),
  gradEnd: Color(0xFFD9820E),
  bpm: 64,
  energy: 2,
  arousal: 0.35,
  valence: 0.70,
  cognitiveLoad: 0.50,
  readiness: 0.50,
  modeHint: 'venue_sustain',
  sceneManifest: 'mood_lnl_quiet_premium.json',
  lowpassFloorHz: 8000,
  moodSetId: _ownSet,
  sortOrder: 1,
  isDefault: true,
);

const _steadyFocus = Mood(
  id: 'lnl-steady-focus',
  name: 'Steady Focus',
  dotDark: Color(0xFF2DD4A7),
  dotLight: Color(0xFF1FA982),
  gradStart: Color(0xFF34D3A8),
  gradEnd: Color(0xFF0FA37B),
  bpm: null,
  energy: 1,
  arousal: 0.30,
  valence: 0.60,
  cognitiveLoad: 0.70,
  readiness: 0.55,
  modeHint: 'venue_sustain',
  sceneManifest: 'mood_lnl_steady_focus.json',
  lowpassFloorHz: 8000,
  moodSetId: _ownSet,
  sortOrder: 2,
);

/// A repo whose per-zone read always fails — offline, or a backend that
/// predates `GET /zones/{id}/moods`.
class _NoZoneMoods implements MoodRepo {
  const _NoZoneMoods({this.catalogue = const []});
  final List<Mood> catalogue;

  @override
  Stream<List<Mood>> watchCatalogue() => catalogue.isEmpty
      ? Stream.error(StateError('offline'))
      : Stream.value(catalogue);

  @override
  Stream<List<Mood>> watchZoneMoods() => Stream.error(StateError('offline'));
}

Widget _host(Widget child) => MaterialApp(
      theme: buildPrismTheme(PrismPalette.dark),
      home: Scaffold(body: Padding(padding: const EdgeInsets.all(16), child: child)),
    );

void main() {
  setUp(MoodCatalog.instance.reset);

  group('the row', () {
    test('a server row maps field for field, and its nulls stay null', () {
      final mood = Mood.fromJson(const {
        'id': 'lnl-steady-focus',
        'name': 'Steady Focus',
        'mood_set_id': _ownSet,
        'sort_order': 2,
        'is_default': false,
        'arousal': 0.3,
        'valence': 0.6,
        'cognitive_load': 0.7,
        'readiness': 0.55,
        'bpm': null,
        'energy': 1,
        'dot_dark': '#2DD4A7',
        'dot_light': '#1FA982',
        'grad_start': '#34D3A8',
        'grad_end': '#0FA37B',
        'mode_hint': 'venue_sustain',
        'scene_manifest': 'mood_lnl_steady_focus.json',
        'lowpass_floor_hz': 8000,
      });

      expect(mood.name, 'Steady Focus');
      expect(mood.moodSetId, _ownSet);
      expect(mood.bpm, isNull);
      expect(mood.tempoLabel, isNull);
      expect(mood.lowpassFloorHz, 8000);
      expect(mood.cognitiveLoad, 0.7);
      expect(mood.dotDark, const Color(0xFF2DD4A7));
      expect(mood.sceneManifest, 'mood_lnl_steady_focus.json');
      expect(mood.known, isTrue);
    });

    test('a row survives the on-device copy unchanged', () {
      for (final mood in [...builtInMoods, _quietPremium, _steadyFocus]) {
        final back = Mood.fromJson(mood.toJson());
        expect(back.toJson(), mood.toJson(), reason: mood.id);
        expect(back.bpm, mood.bpm);
        expect(back.lowpassFloorHz, mood.lowpassFloorHz);
        expect(back.dotLight, mood.dotLight);
      }
    });

    test('a mood with a tempo labels it; one without has no label at all', () {
      expect(_quietPremium.tempoLabel, '64 BPM');
      expect(_steadyFocus.tempoLabel, isNull);
    });
  });

  group('the lookup', () {
    test('an id no catalogue has is a placeholder, not a throw', () {
      // moodById() used to throw here — a red screen for a venue whose moods
      // the app had not been compiled with.
      final mood = moodById('lnl-steady-focus');
      expect(mood.known, isFalse);
      expect(mood.name, 'lnl-steady-focus');
      expect(mood.tempoLabel, isNull);
      expect(mood.sceneManifest, isEmpty);
    });

    test('server rows are merged over the built-in six, never instead', () {
      MoodCatalog.instance.merge([_quietPremium, _steadyFocus]);

      expect(moodById('lnl-quiet-premium').name, 'Quiet Premium');
      // The six are still there: a venue's own moods arriving must not turn
      // somebody else's room into an unknown one.
      expect(moodById('peak').known, isTrue);
      expect(MoodCatalog.instance.inSet(_ownSet).map((m) => m.id),
          ['lnl-quiet-premium', 'lnl-steady-focus']);
      expect(MoodCatalog.instance.inSet(kDefaultMoodSetId), hasLength(6));
    });

    test('signing out drops everything but the built-in six', () {
      MoodCatalog.instance.merge([_quietPremium]);
      MoodCatalog.instance.reset();
      expect(moodById('lnl-quiet-premium').known, isFalse);
      expect(moodById('daytime-flow').known, isTrue);
    });
  });

  group('what a room offers', () {
    ProviderContainer container(MoodRepo moods, {String playing = 'peak'}) {
      final c = ProviderContainer(overrides: [
        moodRepoProvider.overrideWithValue(moods),
        nowPlayingProvider.overrideWith(
            (ref) => Stream.value(PlaybackState(
                moodId: playing, paused: false, contextLine: ''))),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<List<Mood>> offered(ProviderContainer c) async {
      // Listen, as a screen would: these are autoDispose.
      final sub = c.listen(zoneMoodsProvider, (_, _) {});
      addTearDown(sub.close);
      // Until both inputs have answered, one way or the other. A fixed wait
      // passed alone and failed inside the full suite, where the machine is
      // busy enough for the timing to decide the outcome.
      for (var i = 0; i < 200; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
        final catalogue = c.read(moodCatalogProvider);
        if (c.read(nowPlayingProvider).hasValue &&
            (catalogue.hasValue || catalogue.hasError)) {
          break;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return c.read(zoneMoodsProvider);
    }

    test('the server\'s list, when there is one', () async {
      final c = container(const MockMoodRepo(
        catalogue: [...builtInMoods, _quietPremium, _steadyFocus],
        zoneMoods: [_quietPremium, _steadyFocus],
      ));
      expect((await offered(c)).map((m) => m.id),
          ['lnl-quiet-premium', 'lnl-steady-focus']);
    });

    test('with no answer, an existing venue still gets its six', () async {
      // Offline, or a backend without the endpoint. The room is playing a
      // built-in mood, so its set is the built-in six — exactly what the grid
      // showed when they were compiled in.
      final c = container(const _NoZoneMoods(), playing: 'evening-warmth');
      expect((await offered(c)).map((m) => m.id),
          builtInMoods.map((m) => m.id));
    });

    test('with no answer, a venue with its own moods is offered nothing',
        () async {
      // NOT the Default six. An empty grid is a visible gap; six moods that
      // room cannot play would be an invitation to tap one.
      final c = container(const _NoZoneMoods(), playing: 'lnl-quiet-premium');
      expect(await offered(c), isEmpty);
    });

    test('with no answer but a known catalogue, it is offered its own set',
        () async {
      // The catalogue loaded (or was restored from the device) but the
      // per-zone read did not. Signed in, because the catalogue belongs to an
      // account and is dropped without one.
      final c = container(
        const _NoZoneMoods(catalogue: [_quietPremium, _steadyFocus]),
        playing: 'lnl-steady-focus',
      );
      c.read(sessionProvider.notifier).set(const User(
            id: 'u-1',
            name: 'Lobo',
            role: Role.owner,
            initials: 'LL',
            avatarColor: Color(0xFFF5A623),
          ));
      expect((await offered(c)).map((m) => m.id),
          ['lnl-quiet-premium', 'lnl-steady-focus']);
    });

    test('starter plans are offered only to a room that has those moods', () {
      expect(starterTemplatesFit(builtInMoods), isTrue);
      expect(starterTemplatesFit([_quietPremium, _steadyFocus]), isFalse);
      expect(starterTemplatesFit(const []), isFalse);
    });
  });

  group('the card', () {
    testWidgets('the grid draws the moods it is given and no others',
        (tester) async {
      await tester.pumpWidget(_host(const MoodGrid(
        moods: [_quietPremium, _steadyFocus],
        currentMoodId: 'lnl-quiet-premium',
        paused: true,
      )));

      expect(find.byType(MoodTile), findsNWidgets(2));
      expect(find.text('Quiet Premium'), findsOneWidget);
      expect(find.text('Steady Focus'), findsOneWidget);
      expect(find.text('Peak'), findsNothing);
      expect(find.text('Morning calm'), findsNothing);
    });

    testWidgets('a mood with no tempo shows no BPM line', (tester) async {
      await tester.pumpWidget(_host(const MoodGrid(
        moods: [_quietPremium, _steadyFocus],
        currentMoodId: 'none-of-these',
        paused: false,
      )));

      expect(find.text('64 BPM'), findsOneWidget);
      // One tile has a tempo. The other has no meta line — not "0 BPM", not
      // "null BPM", not a dash.
      expect(find.textContaining('BPM'), findsOneWidget);
      expect(find.textContaining('null'), findsNothing);
    });

    testWidgets('an empty set says so instead of drawing nothing',
        (tester) async {
      await tester.pumpWidget(_host(const MoodGrid(
        moods: [],
        currentMoodId: 'lnl-quiet-premium',
        paused: false,
      )));
      expect(find.byType(MoodTile), findsNothing);
      expect(find.textContaining("haven't loaded"), findsOneWidget);
    });

    testWidgets('the confirm dialog leaves the tempo out, not blank',
        (tester) async {
      Future<void> open(Mood mood) async {
        await tester.pumpWidget(_host(Builder(
          builder: (context) => TextButton(
            onPressed: () => showConfirmVibeDialog(context, mood: mood),
            child: const Text('open'),
          ),
        )));
        await tester.tap(find.text('open'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
      }

      await open(_steadyFocus);
      expect(find.text('Switch to Steady Focus?'), findsOneWidget);
      expect(
          find.textContaining('The room eases over ~40s. Energy 1/5.',
              findRichText: true),
          findsOneWidget);
      expect(find.textContaining('BPM', findRichText: true), findsNothing);
    });

    testWidgets('the confirm dialog still quotes a tempo when there is one',
        (tester) async {
      await tester.pumpWidget(_host(Builder(
        builder: (context) => TextButton(
          onPressed: () => showConfirmVibeDialog(context, mood: _quietPremium),
          child: const Text('open'),
        ),
      )));
      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(
          find.textContaining('64 BPM · energy 2/5.', findRichText: true),
          findsOneWidget);
    });
  });

  group('the Floor of a venue with its own moods', () {
    testWidgets('offers that room\'s moods and none of the six',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(1024, 768));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(overrides: [
        playbackRepoProvider.overrideWith((ref) {
          final repo = MockPlaybackRepo(tickNoise: false);
          ref.onDispose(repo.dispose);
          return repo;
        }),
        moodRepoProvider.overrideWithValue(const MockMoodRepo(
          catalogue: [...builtInMoods, _quietPremium, _steadyFocus],
          zoneMoods: [_quietPremium, _steadyFocus],
        )),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: const PrismVenuesApp(),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField).first, 'floor@lobo.example');
      await tester.enterText(find.byType(TextField).at(1), 'hunter22');
      await tester.tap(find.text('Sign in'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(MoodTile), findsNWidgets(2));
      expect(find.widgetWithText(MoodTile, 'Quiet Premium'), findsOneWidget);
      expect(find.widgetWithText(MoodTile, 'Steady Focus'), findsOneWidget);
      expect(find.widgetWithText(MoodTile, 'Peak'), findsNothing);
      expect(find.widgetWithText(MoodTile, 'Wind-down'), findsNothing);
    });
  });

  group('the engine fails closed', () {
    test('a mood no catalogue has silences the room and says why', () async {
      final engine = PlatformPrismEngine();
      addTearDown(engine.dispose);

      await engine.setMood(const Mood.unknown('lnl-quiet-premium'));

      expect(engine.status, EngineStatus.unavailable);
      expect(engine.lastError, contains('lnl-quiet-premium'));
      expect(engine.lastError, contains('Nothing is playing'));
      expect(engine.outputLevel, isNull);
    });

    test('pausing and resuming does not make it look like an ordinary pause',
        () async {
      final engine = PlatformPrismEngine();
      addTearDown(engine.dispose);

      await engine.setMood(const Mood.unknown('lnl-quiet-premium'));
      await engine.silence();
      expect(engine.status, EngineStatus.silenced);
      await engine.resume();
      expect(engine.status, EngineStatus.unavailable);
      expect(engine.lastError, contains('lnl-quiet-premium'));
    });

    test('a later unknown mood replaces the reason, never plays the first',
        () async {
      final engine = PlatformPrismEngine();
      addTearDown(engine.dispose);

      await engine.setMood(const Mood.unknown('one'));
      await engine.setMood(const Mood.unknown('two'));

      expect(engine.status, EngineStatus.unavailable);
      expect(engine.lastError, contains('"two"'));
    });
  });
}
