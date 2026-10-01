/// The client half of zone last-seen.
///
/// What is worth proving here is not that a timer fires — it is *what* the
/// device is willing to claim. A report saying "playing Peak" from a machine
/// that is not the player would put a falsehood in the one column an owner
/// checks when a room has gone quiet, and it would arrive every sixty seconds.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/last_seen_reporter.dart';
import 'package:prism_venues/app/local_playback.dart';
import 'package:prism_venues/app/session.dart';
import 'package:prism_venues/data/mock/mock_last_seen_repo.dart';
import 'package:prism_venues/data/repositories/last_seen_repo.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/data/repositories/settings_repo.dart';
import 'package:prism_venues/engine/engine_controller.dart';
import 'package:prism_venues/engine/prism_engine.dart';
import 'package:prism_venues/engine/weather_influence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockLastSeenRepo repo;
  late _FakeEngine engine;

  ProviderContainer build() {
    repo = MockLastSeenRepo();
    engine = _FakeEngine();
    final container = ProviderContainer(overrides: [
      lastSeenRepoProvider.overrideWithValue(repo),
      prismEngineProvider.overrideWithValue(engine),
    ]);
    addTearDown(container.dispose);
    // Stands in for the screens: these are autoDispose stream providers, and a
    // listen from inside a provider build creates them without keeping the
    // subscription that makes them emit. Same reason as engine_controller_test.
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

  Future<ProviderContainer> signedIn() async {
    final container = build();
    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();
    return container;
  }

  /// Make this app the proven player of the zone in hand, the way
  /// `engine_controller.dart` does when it actually drives audio.
  void nowPlayingHere(ProviderContainer container) {
    engine.playing = true;
    container
        .read(playedZonesProvider.notifier)
        .remember(container.read(currentZoneIdProvider)!);
  }

  test('reports presence even when this app is not the player', () async {
    // A tablet that is on with the app open is a completely different
    // situation from a tablet that is off, and an owner must be able to tell
    // them apart. Presence is not conditional on audio.
    final container = await signedIn();
    // Reading it starts the reporter, which reports once for the zone already
    // in hand. Clear after that, so each test asserts on its own report.
    final reporter = container.read(lastSeenReporterProvider);
    repo.reports.clear();

    await reporter.reportNow();

    expect(repo.reports, hasLength(1));
    expect(repo.reports.single.zoneId, container.read(currentZoneIdProvider));
  });

  test('does not claim a mood it is not playing', () async {
    // now-playing says a mood, but this app has never driven audio into the
    // zone — another iPad is the player. Echoing the mood back would report
    // the server's own desired state to it as though it had been observed.
    final container = await signedIn();
    expect(container.read(nowPlayingProvider).value?.moodId, isNotNull);
    // Reading it starts the reporter, which reports once for the zone already
    // in hand. Clear after that, so each test asserts on its own report.
    final reporter = container.read(lastSeenReporterProvider);
    repo.reports.clear();

    await reporter.reportNow();

    expect(repo.reports.single.moodId, isNull);
    expect(repo.reports.single.volumePct, isNull);
  });

  test('reports the mood and volume it is actually rendering', () async {
    final container = await signedIn();
    nowPlayingHere(container);
    // Reading it starts the reporter, which reports once for the zone already
    // in hand. Clear after that, so each test asserts on its own report.
    final reporter = container.read(lastSeenReporterProvider);
    repo.reports.clear();

    await reporter.reportNow();

    expect(
      repo.reports.single.moodId,
      container.read(nowPlayingProvider).value!.moodId,
    );
    expect(
      repo.reports.single.volumePct,
      container.read(guardrailsProvider).value!.volumeMax,
    );
  });

  test('reports paused, which the device can vouch for', () async {
    final container = await signedIn();
    await container.read(playbackRepoProvider).pause(by: 'Priya');
    await settle();
    // Reading it starts the reporter, which reports once for the zone already
    // in hand. Clear after that, so each test asserts on its own report.
    final reporter = container.read(lastSeenReporterProvider);
    repo.reports.clear();

    await reporter.reportNow();

    expect(repo.reports.single.mode, 'paused');
  });

  test('leaves the mode out while playing, rather than guessing', () async {
    // "auto" versus "manual" is a fact about the server's desired state, not
    // about this device. The server coalesces a missing field to whatever was
    // last reported, so saying nothing is better than filling the column in.
    final container = await signedIn();
    nowPlayingHere(container);
    // Reading it starts the reporter, which reports once for the zone already
    // in hand. Clear after that, so each test asserts on its own report.
    final reporter = container.read(lastSeenReporterProvider);
    repo.reports.clear();

    await reporter.reportNow();

    expect(repo.reports.single.mode, isNull);
  });

  test('says nothing at all when signed out', () async {
    // A shared venue iPad sits on the sign-in screen between shifts. That is
    // nobody's room to report on.
    final container = await signedIn();
    await container.read(authControllerProvider).signOut();
    await settle();
    // Reading it starts the reporter, which reports once for the zone already
    // in hand. Clear after that, so each test asserts on its own report.
    final reporter = container.read(lastSeenReporterProvider);
    repo.reports.clear();

    await reporter.reportNow();

    expect(repo.reports, isEmpty);
  });

  test('reports as soon as the operated zone changes', () async {
    // Otherwise a room opened from the portfolio sits "Offline" for up to a
    // minute, which is exactly when somebody is looking at it.
    final container = build();
    container.read(lastSeenReporterProvider).start();
    expect(repo.reports, isEmpty, reason: 'no session, no zone yet');

    await container.read(authControllerProvider).signIn('owner@x.com', 'pw');
    await settle();

    expect(repo.reports, isNotEmpty);
  });
}

class _FakeEngine implements PrismEngine {
  EngineStatus _status = EngineStatus.idle;

  set playing(bool value) =>
      _status = value ? EngineStatus.playing : EngineStatus.idle;

  @override
  EngineStatus get status => _status;

  @override
  Future<void> start() async {}

  @override
  Future<void> setMood(String moodId,
      {Duration? transition, bool? alignToBar}) async {}

  @override
  Future<void> applyInfluence(PsvNudge nudge) async {}

  @override
  Future<void> setVolumePolicy(int maxPct) async {}

  @override
  Future<void> silence() async {}

  @override
  Future<void> resume() async {}

  @override
  double? get outputLevel => null;

  @override
  String? get lastError => null;

  @override
  Stream<EngineStatus> get statusChanges => const Stream<EngineStatus>.empty();

  @override
  Future<void> dispose() async {}
}
