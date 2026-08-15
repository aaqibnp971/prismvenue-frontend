import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/playback_state.dart';
import '../models/takeover_state.dart';
import '../repositories/playback_repo.dart';
import 'api_client.dart';
import 'api_scope.dart';
import 'token_store.dart';
import 'watchable.dart';

/// `PlaybackRepo` against the real API — the realtime one.
///
/// Two things here are not simple request/response:
///
/// **The takeover countdown ticks locally.** The server sends `started_at` and
/// a remaining figure once; this repository counts down every second between
/// server events. `BACKEND_INTEGRATION.md` is explicit that the server must not
/// push a message per second, and `takeoverCountdownProvider` renders `m:ss`
/// off this stream. When it reaches zero the app calls `endTakeover()` itself —
/// which is why the endpoint is idempotent, since a manager can tap "Return to
/// Prism" at the same moment.
///
/// **State arrives over SSE.** `/zones/{id}/events` carries now-playing, noise
/// and takeover for one zone. The plain GETs still provide the immediate value
/// on subscribe; the stream supplies changes after that, including ones made by
/// another manager on another iPad. If the stream drops, the repository falls
/// back to polling rather than going silent — a Floor screen that quietly stops
/// updating is worse than one that updates slowly.
class ApiPlaybackRepo implements PlaybackRepo {
  ApiPlaybackRepo(this._client, this._scope, this._tokens, {http.Client? sseClient})
      : _sse = sseClient ?? http.Client();

  final ApiClient _client;
  final ApiScope _scope;
  final TokenStore _tokens;
  final http.Client _sse;

  late final _now = Watchable<PlaybackState>(_fetchNow, scopeKey: _scope.zoneKey);
  late final _noise = Watchable<int>(_fetchNoise, scopeKey: _scope.zoneKey);
  late final _takeover =
      Watchable<TakeoverState>(_fetchTakeover, scopeKey: _scope.zoneKey);

  StreamSubscription<String>? _events;
  Timer? _countdown;
  Timer? _pollFallback;
  int _listeners = 0;
  TakeoverState _lastTakeover = TakeoverState.inactive;

  /// Non-null while a connection attempt is in flight.
  ///
  /// Without this, the three watchers the Floor screen mounts in the same frame
  /// each see `_events == null` and open their own stream — and every
  /// navigation does it again. Browsers cap concurrent connections per origin
  /// at around six, so leaked streams silently starve every ordinary request
  /// on the same host until they time out.
  Future<void>? _connecting;

  // --- Now playing / noise ---------------------------------------------------

  @override
  Stream<PlaybackState> watchNowPlaying() => _tracked(_now.watch());

  @override
  Stream<int> watchNoise() => _tracked(_noise.watch());

  @override
  Stream<TakeoverState> watchTakeover() => _tracked(_takeover.watch());

  /// Starts the event stream while anything is listening and stops it when
  /// nothing is. The providers are `autoDispose`, so leaving the Floor screen
  /// should not leave a connection open.
  Stream<T> _tracked<T>(Stream<T> source) {
    late StreamController<T> controller;
    StreamSubscription<T>? sub;

    controller = StreamController<T>(
      onListen: () {
        _listeners++;
        _ensureStreaming();
        sub = source.listen(
          controller.add,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onCancel: () async {
        await sub?.cancel();
        _listeners--;
        if (_listeners <= 0) _stopStreaming();
      },
    );
    return controller.stream;
  }

  @override
  Future<void> setMood(String moodId) async {
    await _client.post('/zones/${_scope.requireZone()}/mood',
        body: {'mood_id': moodId});
    await _now.refresh();
  }

  @override
  Future<void> pause({required String by}) async {
    await _client.post('/zones/${_scope.requireZone()}/pause', body: {'by': by});
    await _now.refresh();
  }

  @override
  Future<void> resume() async {
    await _client.post('/zones/${_scope.requireZone()}/resume');
    await _now.refresh();
  }

  @override
  Future<void> returnToAuto() async {
    // Same endpoint the Venues quick-fix uses; the server sets
    // zone_state.desired_mode = 'auto' and bumps desired_revision. Refreshing
    // `_now` (not just the venue lists) is the point of putting this here — the
    // hero reads its override flag from this stream.
    await _client.post('/zones/${_scope.requireZone()}/return-to-auto');
    await _now.refresh();
  }

  // --- Takeover --------------------------------------------------------------

  @override
  Future<void> startTakeover({required Duration handBackAfter}) async {
    await _client.post(
      '/zones/${_scope.requireZone()}/takeover',
      body: {'hand_back_after_minutes': handBackAfter.inMinutes},
    );
    await _takeover.refresh();
    await _now.refresh();
  }

  @override
  Future<void> extendTakeover(Duration by) async {
    // ADDS to the remaining time rather than replacing it (§6-A7), which the
    // server also enforces — extend_sheet.dart assumes it on both sides.
    await _client.post(
      '/zones/${_scope.requireZone()}/takeover/extend',
      body: {'additional_minutes': by.inMinutes},
    );
    await _takeover.refresh();
  }

  @override
  Future<void> removeAutoReturn() async {
    await _client
        .post('/zones/${_scope.requireZone()}/takeover/remove-auto-return');
    await _takeover.refresh();
  }

  @override
  Future<void> endTakeover() async {
    await _client.post('/zones/${_scope.requireZone()}/takeover/end');
    await _takeover.refresh();
    await _now.refresh();
  }

  // --- The local clock -------------------------------------------------------

  void _startCountdown() {
    _countdown?.cancel();
    _countdown = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_lastTakeover.active) return;
      if (!_lastTakeover.hasAutoReturn) {
        // Nothing to count down, but the active screen's elapsed footer
        // ("Started by … · 12 min ago") still needs a heartbeat to stay live.
        _takeover.emit(_lastTakeover);
        return;
      }
      final next = _lastTakeover.remaining - const Duration(seconds: 1);
      if (next <= Duration.zero) {
        _countdown?.cancel();
        _countdown = null;
        // The app hands the room back itself. The server treats this as
        // idempotent, so racing its own auto-return is harmless.
        unawaited(endTakeover().catchError((_) {}));
      } else {
        _lastTakeover = _lastTakeover.copyWith(remaining: next);
        _takeover.emit(_lastTakeover);
      }
    });
  }

  // --- Realtime --------------------------------------------------------------

  /// Opens at most ONE stream, however many watchers ask for it.
  void _ensureStreaming() {
    if (_events != null || _pollFallback != null || _connecting != null) return;
    _connecting = _connect().whenComplete(() => _connecting = null);
  }

  void _stopStreaming() {
    _events?.cancel();
    _events = null;
    _countdown?.cancel();
    _countdown = null;
    _pollFallback?.cancel();
    _pollFallback = null;
  }

  Future<void> _connect() async {
    final zoneId = _scope.zoneId();
    final token = await _tokens.readAccessToken();
    if (zoneId == null || token == null) return _startPolling();

    // Nobody is watching any more. Leaving before _connect() finished meant
    // _stopStreaming() found _events still null, so the connection it could not
    // see was adopted afterwards and held open with zero listeners.
    if (_listeners <= 0) return;

    // Belt and braces: never leave a previous stream holding a socket.
    await _events?.cancel();
    _events = null;

    try {
      // EventSource cannot set headers, so the token travels as a query
      // parameter. Same origin, same TLS connection as every other request.
      final request = http.Request(
        'GET',
        Uri.parse('${_client.baseUrl}/zones/$zoneId/events'
            '?access_token=$token'),
      )..headers['Accept'] = 'text/event-stream';

      final response = await _sse.send(request);
      if (response.statusCode != 200) return _startPolling();
      // Same race, on the far side of the await.
      if (_listeners <= 0) {
        unawaited(response.stream.drain<void>().catchError((_) {}));
        return;
      }

      _events = response.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onEventLine,
            onError: (_) => _startPolling(),
            onDone: _startPolling,
            cancelOnError: true,
          );
    } catch (_) {
      _startPolling();
    }
  }

  void _onEventLine(String line) {
    if (!line.startsWith('data: ')) return;
    try {
      final payload = jsonDecode(line.substring(6)) as Map<String, dynamic>;

      if (payload['now'] case final Map now) {
        _now.emit(_playbackFrom(now.cast<String, dynamic>()));
      }
      if (payload['noise'] case final int noise) {
        _noise.emit(noise);
      }
      if (payload['takeover'] case final Map takeover) {
        _lastTakeover = _takeoverFrom(takeover.cast<String, dynamic>());
        _takeover.emit(_lastTakeover);
        if (_lastTakeover.active) {
          _startCountdown();
        } else {
          _countdown?.cancel();
          _countdown = null;
        }
      }
    } catch (_) {
      // A malformed frame is not worth tearing the connection down for.
    }
  }

  /// Fallback when SSE is unavailable — a proxy that buffers it, an older
  /// deployment, a dropped connection. Slower, but never silent.
  /// Consecutive polls since the last attempt to get the stream back.
  int _pollsSinceRetry = 0;

  /// How many 5s polls to serve before trying the stream again.
  ///
  /// Once _startPolling set _pollFallback, _ensureStreaming returned early
  /// forever: a single dropped frame degraded the screen to 5-second polling
  /// for as long as the user stayed on it, and recovery only happened by
  /// navigating away and back. Retrying on a timer costs one request a minute
  /// against a backend that has genuinely lost SSE, and restores push within a
  /// minute against one that has recovered.
  static const _pollsBeforeStreamRetry = 12; // ~60s

  void _startPolling() {
    _events?.cancel();
    _events = null;
    _pollsSinceRetry = 0;
    _pollFallback ??= Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_listeners <= 0) return;
      try {
        await _now.refresh();
        await _noise.refresh();
        await _takeover.refresh();
      } catch (_) {
        // Keep polling; a transient failure is not a reason to stop.
      }

      if (++_pollsSinceRetry < _pollsBeforeStreamRetry) return;
      _pollsSinceRetry = 0;
      // Try the stream again. _connect() falls straight back to polling if it
      // is still unavailable, and _pollFallback is cleared first so
      // _ensureStreaming's early return does not block the attempt.
      if (_connecting != null || _events != null) return;
      _pollFallback?.cancel();
      _pollFallback = null;
      _ensureStreaming();
    });
  }

  // --- Fetching / mapping ----------------------------------------------------

  Future<PlaybackState> _fetchNow() async {
    final json = await _client.get('/zones/${_scope.requireZone()}/now')
        as Map<String, dynamic>;
    return _playbackFrom(json);
  }

  Future<int> _fetchNoise() async {
    final json = await _client.get('/zones/${_scope.requireZone()}/noise')
        as Map<String, dynamic>;
    return json['noise_pct'] as int? ?? 0;
  }

  Future<TakeoverState> _fetchTakeover() async {
    final json = await _client.get('/zones/${_scope.requireZone()}/takeover')
        as Map<String, dynamic>;
    final state = _takeoverFrom(json);
    _lastTakeover = state;
    if (state.active) _startCountdown();
    return state;
  }

  static PlaybackState _playbackFrom(Map<String, dynamic> json) => PlaybackState(
        // moodById() throws on an unknown id, so a missing mood must resolve to
        // a real one rather than reaching the widget tree.
        moodId: (json['mood_id'] as String?) ?? 'daytime-flow',
        paused: json['paused'] as bool? ?? false,
        pausedBy: json['paused_by'] as String?,
        contextLine: json['context_line'] as String? ?? '',
        // Absent on older backends, and absence must read as "on schedule" —
        // showing a Back to Auto control for a room that is already on auto is
        // worse than not showing it at all.
        offSchedule: json['off_schedule'] as bool? ?? false,
      );

  static TakeoverState _takeoverFrom(Map<String, dynamic> json) {
    if (json['active'] != true) return TakeoverState.inactive;
    final startedAt = json['started_at'] as String?;
    return TakeoverState(
      active: true,
      startedAt: startedAt == null ? null : DateTime.tryParse(startedAt),
      remaining: Duration(seconds: json['remaining_seconds'] as int? ?? 0),
      hasAutoReturn: json['has_auto_return'] as bool? ?? true,
      startedByName: json['started_by_name'] as String?,
    );
  }

  void dispose() {
    _stopStreaming();
    _sse.close();
    _now.dispose();
    _noise.dispose();
    _takeover.dispose();
  }
}
