import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/session.dart';
import 'package:prism_venues/data/models/guardrails.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/data/repositories/settings_repo.dart';
import 'package:flutter/services.dart';
import 'package:prism_venues/engine/audio_focus.dart';
import 'package:prism_venues/engine/engine_controller.dart';
import 'package:prism_venues/engine/prism_engine.dart';
import 'package:prism_venues/engine/weather_influence.dart';

/// The first tests over `lib/engine/`.
///
/// CLAUDE.md records the gap: the engine seam is verified in C++ and in the
/// Dart binding host test against the real native library, so a change to
/// `engine_controller.dart` was uncovered by `flutter test`. That is fine for
/// the parts that are really about audio, and wrong for the parts that are
/// really about app state — which is all this file covers. A fake engine and
/// the mock repositories are enough to prove the controller reacts to the right
/// things, and neither needs an audio device.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeEngine engine;

  ProviderContainer build() {
    engine = _FakeEngine();
    final container = ProviderContainer(overrides: [
      prismEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);
    // Reading it is what attaches the listeners; main.dart watches it for the
    // same reason.
    container.read(engineControllerProvider);
    // Stands in for the screens.
    //
    // The controller's own `ref.listen` is not enough to DRIVE these: they are
    // autoDispose StreamProviders, and a listen from inside a provider build
    // creates them without keeping a subscription that makes them emit. In the
    // app the Floor screen is the listener. Worth knowing before reading a
    // green run here as proof the engine follows state with no screen mounted
    // — that is a separate question this file does not answer.
    for (final p in [nowPlayingProvider, takeoverStateProvider]) {
      container.listen(p, (_, _) {}, fireImmediately: true);
    }
    container.listen(guardrailsProvider, (_, _) {}, fireImmediately: true);
    container.listen(externalAudioProvider, (_, _) {}, fireImmediately: true);
    return container;
  }

  /// What the Windows runner sends when another program starts or stops making
  /// a sound. Delivered through the real channel so the handler wiring is
  /// exercised, not just the controller's reaction to it.
  Future<void> externalAudio(bool playing) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      audioFocusChannel.name,
      const StandardMethodCodec().encodeMethodCall(
        MethodCall('externalAudioChanged', playing),
      ),
      (_) {},
    );
  }

  /// The controller chains its engine work through futures and the providers
  /// are streams, so a few microtask turns are what "settle" means here.
  Future<void> settle() async {
    for (var i = 0; i < 12; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('signing out silences the room', () async {
    // Every other stream the controller watches is zone-scoped, and signing out
    // clears the zone — so they throw rather than emit, `next.value` is null,
    // and nothing else here can notice the session ended. Before this, the last
    // mood played on over the sign-in screen: on a shared venue iPad, the next
    // person's room still running on the last person's session.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    expect(engine.moods, isNotEmpty, reason: 'the room should be playing');
    expect(engine.silenced, isFalse);

    await container.read(authControllerProvider).signOut();
    await settle();

    expect(engine.silenced, isTrue);
  });

  test('signing back in starts the room again', () async {
    // Sign-in needs no handling of its own: the new session repoints the zone,
    // now-playing emits, and the playback path sets the mood and resumes. This
    // is here so a future "just silence on sign-out" cannot leave the app
    // permanently mute.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    await container.read(authControllerProvider).signOut();
    await settle();
    expect(engine.silenced, isTrue);

    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    expect(engine.silenced, isFalse);
  });

  test('the volume ceiling is held, never re-defaulted, when the stream empties',
      () async {
    // A volume guardrail must not fail upward. `guardrailsProvider` throws
    // `no_zone_selected` the moment the zone is cleared, and reading an empty
    // AsyncValue as "no policy" pushed the room back to the 70% seed — loudest
    // exactly where a manager had deliberately set a low ceiling.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    await container
        .read(settingsRepoProvider)
        .updateGuardrails(const Guardrails(volumeMin: 4, volumeMax: 12));
    await settle();
    expect(engine.volumes.last, 12);

    final beforeSignOut = engine.volumes.length;
    await container.read(authControllerProvider).signOut();
    await settle();

    expect(engine.volumes.length, beforeSignOut,
        reason: 'signing out must not touch the ceiling at all — the mocks '
            'keep emitting for the null zone, and the old code took that as '
            'licence to reset to the 70% seed');
    expect(engine.volumes.last, 12);
  });

  test('the room gets out of the way when something else plays', () async {
    // Windows has no audio focus — every process opens the shared mixer and
    // they all sound at once — so a video started on the same machine used to
    // play over the top of the room instead of replacing it.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    expect(engine.silenced, isFalse);

    await externalAudio(true);
    await settle();
    expect(engine.silenced, isTrue);

    // And comes back on its own. A venue is not somewhere anyone will remember
    // to press play again.
    await externalAudio(false);
    await settle();
    expect(engine.silenced, isFalse);
  });

  test('external audio ending does not override a pause', () async {
    // The four reasons to be silent are independent, and each used to resume
    // directly — so whichever cleared last un-silenced the room regardless of
    // the others. This is the shape of that bug.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    await externalAudio(true);
    await settle();
    await container.read(playbackRepoProvider).pause(by: 'Priya');
    await settle();
    expect(engine.silenced, isTrue);

    await externalAudio(false);
    await settle();
    expect(engine.silenced, isTrue,
        reason: 'the room is still paused, and nobody cancelled that');

    await container.read(playbackRepoProvider).resume();
    await settle();
    expect(engine.silenced, isFalse);
  });

  test('external audio while signed out changes nothing', () async {
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    await container.read(authControllerProvider).signOut();
    await settle();

    await externalAudio(false);
    await settle();
    expect(engine.silenced, isTrue);
  });
}

class _FakeEngine implements PrismEngine {
  final moods = <String>[];
  final volumes = <int>[];
  bool silenced = false;
  bool started = false;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> setMood(String moodId,
      {Duration? transition, bool? alignToBar}) async {
    moods.add(moodId);
  }

  @override
  Future<void> setVolumePolicy(int maxPct) async => volumes.add(maxPct);

  @override
  Future<void> silence() async => silenced = true;

  @override
  Future<void> resume() async => silenced = false;

  @override
  Future<void> applyInfluence(PsvNudge nudge) async {}

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
