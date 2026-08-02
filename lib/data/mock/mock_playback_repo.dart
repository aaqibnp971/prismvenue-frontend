import 'dart:async';
import 'dart:math';

import '../models/playback_state.dart';
import '../models/takeover_state.dart';
import '../repositories/playback_repo.dart';

/// In-memory playback seeded with the README's Marina Café example:
/// Afternoon lift playing, Prism driving, noise 62%, context
/// "mid-afternoon · ~60% full · clear".
class MockPlaybackRepo implements PlaybackRepo {
  MockPlaybackRepo({this.tickNoise = true});

  /// False in widget tests — a periodic timer never lets pumpAndSettle rest.
  final bool tickNoise;

  PlaybackState _state = const PlaybackState(
    moodId: 'afternoon-lift',
    paused: false,
    contextLine: 'mid-afternoon · ~60% full · clear',
  );
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
    _state = next;
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

  TakeoverState _takeover = TakeoverState.inactive;
  final _takeoverController = StreamController<TakeoverState>.broadcast();
  Timer? _takeoverTicker;

  @override
  Stream<TakeoverState> watchTakeover() async* {
    yield _takeover;
    yield* _takeoverController.stream;
  }

  void _emitTakeover(TakeoverState next) {
    _takeover = next;
    _takeoverController.add(next);
  }

  @override
  Future<void> startTakeover({required Duration handBackAfter}) async {
    _emitTakeover(TakeoverState(
      active: true,
      startedAt: DateTime.now(),
      remaining: handBackAfter,
      // Seed name matching the S02-2 frame footer; the API supplies the real
      // signed-in staff member.
      startedByName: 'Priya N',
    ));
    // One shared 1s clock drives the visible countdown and the automatic
    // hand-back ("Returns automatically after …", §6-A7). With auto-return
    // removed it keeps ticking but only re-emits, so the elapsed footer
    // stays live without anything counting down.
    _takeoverTicker?.cancel();
    _takeoverTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_takeover.hasAutoReturn) {
        _emitTakeover(_takeover);
        return;
      }
      final next = _takeover.remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        endTakeover();
      } else {
        _emitTakeover(_takeover.copyWith(remaining: next));
      }
    });
  }

  @override
  Future<void> extendTakeover(Duration by) async {
    if (!_takeover.active) return;
    // §6-A7: extend adds the chosen duration.
    _emitTakeover(_takeover.copyWith(remaining: _takeover.remaining + by));
  }

  @override
  Future<void> removeAutoReturn() async {
    if (!_takeover.active) return;
    _emitTakeover(_takeover.copyWith(
      hasAutoReturn: false,
      remaining: Duration.zero,
    ));
  }

  @override
  Future<void> endTakeover() async {
    _takeoverTicker?.cancel();
    _takeoverTicker = null;
    _emitTakeover(TakeoverState.inactive);
  }

  void dispose() {
    _stopTicking();
    _takeoverTicker?.cancel();
    _stateController.close();
    _noiseController.close();
    _takeoverController.close();
  }
}
