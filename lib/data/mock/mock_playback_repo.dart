import 'dart:async';
import 'dart:math';

import '../models/playback_state.dart';
import '../models/takeover_state.dart';
import '../repositories/playback_repo.dart';

/// In-memory playback seeded with the README's Marina Café example:
/// Afternoon lift playing, Prism driving, noise 62%, context
/// "mid-afternoon · ~60% full · clear".
///
/// **State is per zone**, keyed by [zoneId], because that is what the schema
/// is: `zone_state` has one row per zone, so two rooms play two moods and
/// changing one must not move the other. The mock held a single shared
/// `PlaybackState`, which was invisible while the app had no way to change
/// rooms — and became actively misleading the moment "Open floor" started
/// working on every zone, since every venue then appeared to play whatever was
/// set last. A mock that cannot express independence documents the wrong shape.
class MockPlaybackRepo implements PlaybackRepo {
  MockPlaybackRepo({this.tickNoise = true, String? Function()? zoneId})
      : _zoneId = zoneId ?? (() => null);

  /// False in widget tests — a periodic timer never lets pumpAndSettle rest.
  final bool tickNoise;

  /// Resolved at call time, exactly as `ApiScope` does it, so switching the
  /// session's zone repoints this repository with nothing to rebuild.
  ///
  /// Defaults to a resolver returning null, which collapses every zone into
  /// one bucket — the pre-zone behaviour, and what a test constructing this
  /// directly still gets.
  final String? Function() _zoneId;

  static const _seed = PlaybackState(
    moodId: 'afternoon-lift',
    paused: false,
    contextLine: 'mid-afternoon · ~60% full · clear',
  );

  /// One entry per room the session has actually looked at. Absent means
  /// "never touched", which reads as the seed rather than as an error.
  final _states = <String?, PlaybackState>{};

  PlaybackState get _state => _states[_zoneId()] ?? _seed;
  int _noise = 62;

  final _stateController = StreamController<PlaybackState>.broadcast();
  late final _noiseController = StreamController<int>.broadcast(
    onListen: _startTicking,
    onCancel: _stopTicking,
  );
  Timer? _noiseTimer;
  final _random = Random(13);

  void _startTicking() {
    if (!tickNoise) return;
    // Gentle wander around the 62% seed so the meter looks alive (§5 "mock
    // ticks") without straying from the README's example value.
    _noiseTimer ??= Timer.periodic(const Duration(milliseconds: 2500), (_) {
      _noise = (_noise + _random.nextInt(5) - 2).clamp(58, 66);
      _noiseController.add(_noise);
    });
  }

  void _stopTicking() {
    _noiseTimer?.cancel();
    _noiseTimer = null;
  }

  @override
  Stream<PlaybackState> watchNowPlaying() async* {
    yield _state;
    yield* _stateController.stream;
  }

  @override
  Stream<int> watchNoise() async* {
    yield _noise;
    yield* _noiseController.stream;
  }

  void _emit(PlaybackState next) {
    _states[_zoneId()] = next;
    _stateController.add(next);
  }

  @override
  Future<void> setMood(String moodId) async {
    // Tapping a mood IS the override — that is what takes the room off its
    // schedule, and what the Floor screen's Back to Auto control undoes.
    _emit(_state.copyWith(moodId: moodId, paused: false, offSchedule: true));
  }

  @override
  Future<void> returnToAuto() async {
    _emit(_state.copyWith(offSchedule: false));
  }

  @override
  Future<void> pause({required String by}) async {
    _emit(_state.copyWith(paused: true, pausedBy: by));
  }

  @override
  Future<void> resume() async {
    _emit(_state.copyWith(paused: false));
  }

  // ---- Takeover (§2 S02) ----

  /// Per zone, like [_states] and for the same reason: `takeovers` is keyed by
  /// `zone_id`, so staff holding the Terrace must not make the Main floor look
  /// held too.
  final _takeovers = <String?, TakeoverState>{};

  /// One clock per held room. Keyed rather than single, because the zone the
  /// countdown belongs to is decided when it STARTS — reading `_zoneId()` from
  /// inside the tick would write the Terrace's remaining time into whichever
  /// room the manager happened to switch to since.
  final _takeoverTickers = <String?, Timer>{};

  final _takeoverController = StreamController<TakeoverState>.broadcast();

  TakeoverState get _takeover => _takeovers[_zoneId()] ?? TakeoverState.inactive;

  @override
  Stream<TakeoverState> watchTakeover() async* {
    yield _takeover;
    yield* _takeoverController.stream;
  }

  void _emitTakeover(String? zone, TakeoverState next) {
    _takeovers[zone] = next;
    // Only the room in view has listeners worth waking; emitting another
    // zone's countdown into them would tick the wrong screen.
    if (zone == _zoneId()) _takeoverController.add(next);
  }

  @override
  Future<void> startTakeover({required Duration handBackAfter}) async {
    final zone = _zoneId();
    _emitTakeover(
        zone,
        TakeoverState(
          active: true,
          startedAt: DateTime.now(),
          remaining: handBackAfter,
          // Seed name matching the S02-2 frame footer; the API supplies the
          // real signed-in staff member.
          startedByName: 'Priya N',
        ));
    // A 1s clock drives the visible countdown and the automatic hand-back
    // ("Returns automatically after …", §6-A7). With auto-return removed it
    // keeps ticking but only re-emits, so the elapsed footer stays live
    // without anything counting down.
    _takeoverTickers.remove(zone)?.cancel();
    _takeoverTickers[zone] = Timer.periodic(const Duration(seconds: 1), (_) {
      final current = _takeovers[zone] ?? TakeoverState.inactive;
      if (!current.hasAutoReturn) {
        _emitTakeover(zone, current);
        return;
      }
      final next = current.remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _endTakeoverFor(zone);
      } else {
        _emitTakeover(zone, current.copyWith(remaining: next));
      }
    });
  }

  @override
  Future<void> extendTakeover(Duration by) async {
    if (!_takeover.active) return;
    // §6-A7: extend adds the chosen duration.
    _emitTakeover(_zoneId(), _takeover.copyWith(remaining: _takeover.remaining + by));
  }

  @override
  Future<void> removeAutoReturn() async {
    if (!_takeover.active) return;
    _emitTakeover(
        _zoneId(),
        _takeover.copyWith(
          hasAutoReturn: false,
          remaining: Duration.zero,
        ));
  }

  @override
  Future<void> endTakeover() async => _endTakeoverFor(_zoneId());

  void _endTakeoverFor(String? zone) {
    _takeoverTickers.remove(zone)?.cancel();
    _emitTakeover(zone, TakeoverState.inactive);
  }

  void dispose() {
    _stopTicking();
    for (final ticker in _takeoverTickers.values) {
      ticker.cancel();
    }
    _takeoverTickers.clear();
    _stateController.close();
    _noiseController.close();
    _takeoverController.close();
  }
}
