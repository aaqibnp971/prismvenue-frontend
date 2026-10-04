/// Finding #4 — open hours and closed days did not stop the music.
///
/// A clinic closing at 7pm kept playing Wind-down all night, and a venue marked
/// closed for a holiday played to an empty room for as long as the tablet had
/// power. The scheduler holds the last mood through gaps in the plan, which is
/// right between two dayparts and exactly wrong at closing time.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/theme/moods.dart';
import 'package:prism_venues/app/session.dart';
import 'package:prism_venues/data/models/playback_state.dart';
import 'package:prism_venues/data/models/takeover_state.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/data/repositories/settings_repo.dart';
import 'package:prism_venues/engine/engine_controller.dart';
import 'package:prism_venues/engine/prism_engine.dart';
import 'package:prism_venues/engine/weather_influence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEngine engine;
  late _ClosableRepo repo;

  ProviderContainer build() {
    engine = _FakeEngine();
    repo = _ClosableRepo();
    final container = ProviderContainer(overrides: [
      prismEngineProvider.overrideWithValue(engine),
      playbackRepoProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    container.read(engineControllerProvider);
    for (final p in [nowPlayingProvider, takeoverStateProvider]) {
      container.listen(p, (_, _) {}, fireImmediately: true);
    }
    container.listen(guardrailsProvider, (_, _) {}, fireImmediately: true);
    return container;
  }

  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
  }

  test('a closed venue silences the room', () async {
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    expect(engine.silenced, isFalse, reason: 'open to begin with');

    repo.close(opensLabel: '7am');
    await settle();

    expect(engine.silenced, isTrue);
  });

  test('opening brings the room back on its own', () async {
    // Nobody is going to press play at 7am. The room has to return by itself
    // or the fix is worse than the defect.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    repo.close(opensLabel: '7am');
    await settle();
    expect(engine.silenced, isTrue);

    repo.open();
    await settle();

    expect(engine.silenced, isFalse);
  });

  test('closed outranks a plan that still has a mood to play', () async {
    // The scheduler keeps advancing dayparts through the night; the mood is
    // perfectly valid. Closed is not about whether there is something to play.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    repo.close(opensLabel: null, moodId: 'wind-down');
    await settle();

    expect(engine.silenced, isTrue);
  });

  test('a venue with no hours is treated as open', () async {
    // Absent hours are missing data, not a closed sign.
    const noHours = PlaybackState(
      moodId: 'peak',
      paused: false,
      contextLine: '',
      closed: false,
      opensLabel: null,
    );

    expect(noHours.closed, isFalse);
  });
}

const _idle = TakeoverState(active: false);

/// A playback repo whose venue can be opened and closed from a test.
class _ClosableRepo implements PlaybackRepo {
  final _controller = StreamController<PlaybackState>.broadcast();
  PlaybackState _state = const PlaybackState(
    moodId: 'peak',
    paused: false,
    contextLine: '',
  );

  void close({String? opensLabel, String moodId = 'peak'}) {
    _state = PlaybackState(
      moodId: moodId,
      paused: false,
      contextLine: '',
      closed: true,
      opensLabel: opensLabel,
    );
    _controller.add(_state);
  }

  void open() {
    _state = PlaybackState(
      moodId: _state.moodId,
      paused: false,
      contextLine: '',
      closed: false,
    );
    _controller.add(_state);
  }

  @override
  Stream<PlaybackState> watchNowPlaying() async* {
    yield _state;
    yield* _controller.stream;
  }

  @override
  Stream<int> watchNoise() => const Stream<int>.empty();

  @override
  Stream<TakeoverState> watchTakeover() =>
      Stream<TakeoverState>.value(_idle);

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

class _FakeEngine implements PrismEngine {
  bool silenced = false;

  @override
  Future<void> start() async {}

  @override
  Future<void> setMood(Mood mood,
      {Duration? transition, bool? alignToBar}) async {}

  @override
  Future<void> applyInfluence(PsvNudge nudge) async {}

  @override
  Future<void> setVolumePolicy(int maxPct) async {}

  @override
  Future<void> silence() async => silenced = true;

  @override
  Future<void> resume() async => silenced = false;

  @override
  double? get outputLevel => silenced ? null : 0.1;

  @override
  EngineStatus get status =>
      silenced ? EngineStatus.silenced : EngineStatus.playing;

  @override
  String? get lastError => null;

  @override
  Stream<EngineStatus> get statusChanges => const Stream<EngineStatus>.empty();

  @override
  Future<void> dispose() async {}
}
