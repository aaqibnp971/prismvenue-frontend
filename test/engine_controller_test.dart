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

  /// Calls the app makes OUT to the platform, and a scripted answer to
  /// `requestFocus`.
  ///
  /// Android is the only platform that answers: its model is a request the
  /// system may refuse. Windows volunteers the information instead and
  /// implements neither method, which is why the default here is "no handler
  /// installed" rather than "granted".
  late List<String> platformCalls;
  bool? focusGranted;

  void installPlatformHandler() {
    platformCalls = [];
    focusGranted = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioFocusChannel, (call) async {
      platformCalls.add(call.method);
      if (call.method == 'requestFocus') return focusGranted ?? true;
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioFocusChannel, null));
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

  /// The controller chains its engine work through futures, the providers are
  /// streams, and asking for audio focus is a platform-channel round trip — so
  /// "settled" is several event-loop turns, not a couple of microtasks.
  ///
  /// A fixed count of `Duration.zero` turns was enough until the focus call
  /// added a hop, after which the first test in this file failed roughly one
  /// run in three — but only inside the full suite, where the machine is busy
  /// enough for the timing to matter. Real millisecond waits make the margin
  /// wide enough that load cannot decide the outcome.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
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

  test('the room asks for the speakers before it plays', () async {
    // Android grants or refuses; an app that never asks is one the system
    // cannot duck, and one that is never told a call has started.
    installPlatformHandler();
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    expect(platformCalls, contains('requestFocus'));
    expect(engine.silenced, isFalse);
  });

  test('a refused request leaves the room quiet', () async {
    // Somebody is mid-call. Staying silent is the correct outcome, not a
    // failure to report.
    installPlatformHandler();
    focusGranted = false;
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    expect(platformCalls, contains('requestFocus'));
    expect(engine.silenced, isTrue);
  });

  test('the speakers are handed back when the room stops for good', () async {
    // Focus outlives whatever took it, so holding it while silent keeps every
    // other app on the device ducked for no reason.
    installPlatformHandler();
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    platformCalls.clear();

    await container.read(authControllerProvider).signOut();
    await settle();
    expect(platformCalls, contains('abandonFocus'));
  });

  test('a transient loss keeps the request open', () async {
    // On Android a transient loss is followed by a gain — abandoning the
    // request is precisely what stops that arriving, so the room would never
    // come back after a phone call.
    installPlatformHandler();
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    platformCalls.clear();

    await externalAudio(true);
    await settle();

    expect(engine.silenced, isTrue);
    expect(platformCalls, isNot(contains('abandonFocus')),
        reason: 'giving the request up is what stops AUDIOFOCUS_GAIN arriving');
  });

  test('a platform with no focus concept never goes silent', () async {
    // No mock handler installed, so every call throws MissingPluginException —
    // the normal case on Windows, on the web and in most of this suite. A
    // platform that cannot answer must not be able to keep a venue quiet.
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    expect(engine.silenced, isFalse);
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
