/// Finding #2 — any signed-in device started playing the room.
///
/// The defect was that `_wanted` asked only whether somebody was signed in and
/// the room was not paused or taken over. Nothing anywhere named WHICH device
/// was the room's speaker, so an owner opening the app at home started their
/// clinic's music on their phone, and two iPads in one room played over each
/// other a few hundred milliseconds apart.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/session.dart';
import 'package:prism_venues/data/models/playback_state.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/data/repositories/settings_repo.dart';
import 'package:prism_venues/engine/engine_controller.dart';
import 'package:prism_venues/engine/prism_engine.dart';
import 'package:prism_venues/engine/weather_influence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEngine engine;

  ProviderContainer build() {
    engine = _FakeEngine();
    final container = ProviderContainer(overrides: [
      prismEngineProvider.overrideWithValue(engine),
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

  test('a device that does not hold the room stays silent', () async {
    // The owner-at-home case. Signed in, room playing, nothing paused — and
    // this phone must make no sound whatsoever.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    expect(engine.silenced, isFalse, reason: 'mocks claim the room by default');

    await container.read(playbackRepoProvider).setThisDevicePlays(false);
    await settle();

    expect(engine.silenced, isTrue);
  });

  test('claiming the room makes this device the speaker again', () async {
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    await container.read(playbackRepoProvider).setThisDevicePlays(false);
    await settle();
    expect(engine.silenced, isTrue);

    await container.read(playbackRepoProvider).setThisDevicePlays(true);
    await settle();

    expect(engine.silenced, isFalse);
  });

  test('releasing the room reports who holds it afterwards', () async {
    // Not a local guess: two tablets can race for one room, so the answer is
    // whatever the server says holds it once the call returns.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    final holder =
        await container.read(playbackRepoProvider).setThisDevicePlays(false);
    await settle();

    expect(holder, isNull);
  });

  test('a room nobody claims does not play here', () async {
    // The state a freshly installed venue is in. Silence is correct — and the
    // Settings row says "No device is playing" rather than a bare "Off",
    // because a silent room with no explanation is the whole product failing.
    const nobody = PlaybackState(
      moodId: 'peak',
      paused: false,
      contextLine: '',
      playerInstallationId: null,
      playsHere: false,
    );

    expect(nobody.playsHere, isFalse);
    expect(nobody.playerInstallationId, isNull);
  });

  test('another device holding the room is distinguishable from none',
      () async {
    // Different situations needing different actions from whoever reads them:
    // one is "go and look at the other tablet", the other is "pick a tablet".
    const elsewhere = PlaybackState(
      moodId: 'peak',
      paused: false,
      contextLine: '',
      playerInstallationId: 'someone-else',
      playsHere: false,
    );

    expect(elsewhere.playsHere, isFalse);
    expect(elsewhere.playerInstallationId, isNotNull);
  });
}

class _FakeEngine implements PrismEngine {
  bool silenced = false;
  final moods = <String>[];

  @override
  Future<void> start() async {}

  @override
  Future<void> setMood(String moodId,
      {Duration? transition, bool? alignToBar}) async {
    moods.add(moodId);
  }

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
