import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/repositories/mood_repo.dart';
import 'package:prism_venues/theme/moods.dart';
import 'package:prism_venues/app/session.dart';
import 'package:prism_venues/data/models/guardrails.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/data/repositories/settings_repo.dart';
import 'package:flutter/services.dart';
import 'package:prism_venues/engine/audio_focus.dart';
import 'package:prism_venues/engine/engine_controller.dart';
import 'package:prism_venues/engine/playback_service.dart';
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

  ProviderContainer build({MoodRepo? moods}) {
    engine = _FakeEngine();
    MoodCatalog.instance.reset();
    final container = ProviderContainer(overrides: [
      prismEngineProvider.overrideWithValue(engine),
      if (moods != null) moodRepoProvider.overrideWithValue(moods),
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
    // The catalogue too: every screen that draws a mood watches it.
    container.listen(moodCatalogProvider, (_, _) {}, fireImmediately: true);
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

  /// Calls the app makes to the foreground-service channel (finding #1).
  ///
  /// Android only implements it; every other platform throws
  /// MissingPluginException, which the Dart seam swallows. Installing a
  /// handler here stands in for Android so the ORDER and the PAIRING can be
  /// asserted — a service that outlives the audio is a notification lying to
  /// staff on a locked tablet.
  late List<String> serviceCalls;

  void installServiceHandler() {
    serviceCalls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(playbackServiceChannel, (call) async {
      serviceCalls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(playbackServiceChannel, null));
  }

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

  test('the foreground service starts with the room and stops with it',
      () async {
    // Finding #1: without the service Android reclaims the process once the
    // screen is off, and the room goes quiet with nothing to say why.
    installServiceHandler();
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    expect(serviceCalls, contains('startPlaying'),
        reason: 'a playing room must hold the service up');

    serviceCalls.clear();
    await container.read(authControllerProvider).signOut();
    await settle();

    expect(serviceCalls, contains('stopPlaying'),
        reason: 'a silent room must not keep the notification or the screen on');
  });

  test('every route to silence tears the service down', () async {
    // quiet() is the single place, so pause, takeover and external audio all
    // get this for free. External audio is the one that used to be easiest to
    // miss: the room is silent but nothing about the session changed.
    installServiceHandler();
    installPlatformHandler();
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    serviceCalls.clear();

    await externalAudio(true);
    await settle();

    expect(serviceCalls, contains('stopPlaying'));
    expect(engine.silenced, isTrue);
  });

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

  group('moods the catalogue does not have', () {
    const quietPremium = Mood(
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
      moodSetId: 'a-set-of-its-own',
      isDefault: true,
    );

    test('reach the engine as unknown, never as some other mood', () async {
      // The engine fails closed on an unknown mood. What must never happen is
      // the controller "helping" by handing it a mood it does have.
      final container = build();
      await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
      await settle();
      engine.received.clear();

      await container.read(playbackRepoProvider).setMood('lnl-quiet-premium');
      await settle();

      expect(engine.received, isNotEmpty);
      expect(engine.received.last.id, 'lnl-quiet-premium');
      expect(engine.received.last.known, isFalse);
      expect(engine.received.every((m) => m.id == 'lnl-quiet-premium'), isTrue);
    });

    test('are asked for again, complete, once the catalogue has them',
        () async {
      // Now-playing and the catalogue are separate requests and either can
      // land first. A room whose mood arrived before its row must not stay
      // silent for the rest of the session.
      final catalogue = StreamController<List<Mood>>.broadcast();
      addTearDown(catalogue.close);
      final container = build(moods: _LateCatalogue(catalogue.stream));
      await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
      await settle();

      await container.read(playbackRepoProvider).setMood('lnl-quiet-premium');
      await settle();
      expect(engine.received.last.known, isFalse);

      catalogue.add(const [quietPremium]);
      await settle();

      final last = engine.received.last;
      expect(last.id, 'lnl-quiet-premium');
      expect(last.known, isTrue);
      expect(last.sceneManifest, 'mood_lnl_quiet_premium.json');
      expect(last.lowpassFloorHz, 8000);
    });

    test('a built-in mood is handed over with no floor', () async {
      final container = build();
      await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
      await settle();

      expect(engine.received, isNotEmpty);
      for (final mood in engine.received) {
        expect(mood.known, isTrue, reason: mood.id);
        expect(mood.lowpassFloorHz, isNull, reason: mood.id);
      }
    });
  });
}

/// A catalogue that has not answered yet, and answers when the test says so.
class _LateCatalogue implements MoodRepo {
  _LateCatalogue(this._catalogue);
  final Stream<List<Mood>> _catalogue;

  @override
  Stream<List<Mood>> watchCatalogue() => _catalogue;

  @override
  Stream<List<Mood>> watchZoneMoods() => _catalogue;
}

class _FakeEngine implements PrismEngine {
  final moods = <String>[];

  /// The moods as handed over — what the engine would build its preset from.
  final received = <Mood>[];
  final volumes = <int>[];
  bool silenced = false;
  bool started = false;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> setMood(Mood mood,
      {Duration? transition, bool? alignToBar}) async {
    moods.add(mood.id);
    received.add(mood);
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
