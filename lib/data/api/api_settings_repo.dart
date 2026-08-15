import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../models/guardrails.dart';
import '../repositories/settings_repo.dart';
import 'api_client.dart';
import 'api_scope.dart';
import 'watchable.dart';

/// `SettingsRepo` against the real API.
///
/// Three field-level mismatches between the app's `Guardrails` model and the
/// wire contract are resolved here, so no screen has to know about any of them:
///
/// * **Alert delays.** The model stores an INDEX into a client-side string
///   array (`['2 min','5 min','15 min','30 min']`); the API stores real
///   minutes. The app's own docs flagged the index as fragile — adding a fifth
///   option later silently reinterprets every stored row. [_minutesToIndex]
///   maps by closest value, so a delay set anywhere else still renders sensibly
///   instead of falling back to the first option.
///
/// * **"At close".** The fourth takeover-alert option is not a duration at all.
///   It travels as its own boolean rather than as a magic minute value.
///
/// * **Quiet-hours start and cap.** These exist on the server but have no field
///   in `Guardrails` (`volume_policy_screen.dart` hardcodes the display string).
///   Since the app PUTs the whole object on every toggle, they are simply
///   omitted here and the server preserves them. Sending nulls would wipe them.
class ApiSettingsRepo implements SettingsRepo {
  ApiSettingsRepo(
    this._client,
    this._scope, {
    this.writeDebounce = const Duration(milliseconds: 400),
  });

  final ApiClient _client;
  final ApiScope _scope;

  /// How long the guardrails PUT waits for the value to settle. The volume
  /// sliders call [updateGuardrails] on every pixel of a drag — the screen's
  /// `onChanged` fires per frame, by the interface's own design — which
  /// against a real network meant one drag produced hundreds of writes (403
  /// were observed) that also starved the browser's ~6-per-origin connection
  /// pool. Zero in tests that want the write immediately.
  final Duration writeDebounce;

  Timer? _guardrailsTimer;
  Guardrails? _pendingGuardrails;
  bool _flushing = false;
  Completer<void>? _settled;

  late final _guardrails = Watchable<Guardrails>(
    _fetchGuardrails,
    scopeKey: _scope.zoneKey,
  );
  late final _openHours = Watchable<OpenHours>(
    _fetchOpenHours,
    scopeKey: _scope.venueKey,
  );

  // --- Guardrails ------------------------------------------------------------

  final _failures = StreamController<Object>.broadcast();

  @override
  Stream<Object> get guardrailFailures => _failures.stream;

  @override
  Stream<Guardrails> watchGuardrails() => _guardrails.watch();

  /// Emits immediately, writes once the value settles.
  ///
  /// The emit is what makes the slider track the manager's finger; the
  /// debounced flush is what keeps a drag from being hundreds of PUTs.
  /// Consecutive calls within [writeDebounce] coalesce — the interface sends
  /// the whole object every time, so the newest value IS the whole intended
  /// state and the intermediate ones carry no information.
  ///
  /// The returned future completes when the burst has been flushed. It never
  /// errors: on a failed write the repo refreshes from the server, so the UI
  /// visibly snaps back to truth rather than silently keeping a value that
  /// never landed. (No screen awaits this today — a thrown error would be an
  /// unhandled async exception, not feedback.)
  @override
  Future<void> updateGuardrails(Guardrails next) {
    _guardrails.emit(next);
    _pendingGuardrails = next;
    _settled ??= Completer<void>();
    final settled = _settled!.future;

    _guardrailsTimer?.cancel();
    _guardrailsTimer = Timer(writeDebounce, () {
      unawaited(_flushGuardrails());
    });
    return settled;
  }

  /// Serialized: one PUT in flight at a time, so writes cannot land out of
  /// order and resurrect a value the manager already dragged past.
  Future<void> _flushGuardrails() async {
    if (_flushing) return;
    _flushing = true;
    try {
      while (_pendingGuardrails != null) {
        final toWrite = _pendingGuardrails!;
        _pendingGuardrails = null;
        try {
          await _client.put(
            '/zones/${_scope.requireZone()}/guardrails',
            body: _guardrailsToJson(toWrite),
          );
        } catch (e) {
          // Not rethrown — see updateGuardrails, which nine fire-and-forget
          // call sites rely on not throwing. Reported on the failure stream
          // instead, so the screens can say what happened rather than leaving
          // the revert below as the only clue.
          if (!_failures.isClosed) _failures.add(e);
        }
      }
      // One sync with server truth per burst — after success it confirms the
      // write (a clamped value wins over the optimistic emit), after failure
      // it reverts. Skipped if the manager has already moved on; the next
      // flush will do it.
      if (_pendingGuardrails == null) {
        await _guardrails.refresh().catchError((_) {});
      }
    } finally {
      _flushing = false;
      final settled = _settled;
      if (_pendingGuardrails == null) {
        _settled = null;
        settled?.complete();
      } else {
        // A change arrived while we were refreshing — go again.
        unawaited(_flushGuardrails());
      }
    }
  }

  /// Re-reads guardrails from the server. Exposed for the test that proves a
  /// stream survives a failed first fetch; production code reaches this
  /// through the provider resubscribing when the current zone changes.
  @visibleForTesting
  Future<void> refreshGuardrailsForTest() => _guardrails.refresh();

  Future<Guardrails> _fetchGuardrails() async {
    final json = await _client.get('/zones/${_scope.requireZone()}/guardrails')
        as Map<String, dynamic>;
    return _guardrailsFromJson(json);
  }

  // --- Open hours ------------------------------------------------------------

  @override
  Stream<OpenHours> watchOpenHours() => _openHours.watch();

  @override
  Future<void> setEverydayHours({
    required int openHour,
    required int closeHour,
  }) async {
    await _client.put(
      '/venues/${_scope.requireVenue()}/open-hours',
      body: {'open_hour': openHour, 'close_hour': closeHour},
    );
    await _openHours.refresh();
  }

  @override
  Future<void> addException(HoursException exception) async {
    await _client.post(
      '/venues/${_scope.requireVenue()}/open-hours/exceptions',
      body: _exceptionToJson(exception),
    );
    await _openHours.refresh();
  }

  @override
  Future<void> updateException(HoursException exception) async {
    await _client.patch(
      '/open-hours/exceptions/${exception.id}',
      body: _exceptionToJson(exception),
    );
    await _openHours.refresh();
  }

  @override
  Future<void> deleteException(String id) async {
    await _client.delete('/open-hours/exceptions/$id');
    await _openHours.refresh();
  }

  static Map<String, dynamic> _exceptionToJson(HoursException e) => {
        'days': e.days.toList()..sort(),
        'open_hour': e.openHour,
        'close_hour': e.closeHour,
        'closed_all_day': e.closedAllDay,
        'every_week': e.everyWeek,
        // The sheet collects no label. Null means "leave it alone" on update —
        // the server coalesces rather than clearing it.
        'label': null,
      };

  Future<OpenHours> _fetchOpenHours() async {
    final json = await _client.get('/venues/${_scope.requireVenue()}/open-hours')
        as Map<String, dynamic>;
    return OpenHours(
      openHour: json['open_hour'] as int,
      closeHour: json['close_hour'] as int,
      exceptions: [
        for (final raw in (json['exceptions'] as List? ?? const []))
          _exceptionFromJson((raw as Map).cast<String, dynamic>()),
      ],
    );
  }

  /// `label` is still dropped — nothing displays or edits it — but it is
  /// round-tripped by the server, not lost. `id` is kept now: editing and
  /// deleting an exception need something to address.
  static HoursException _exceptionFromJson(Map<String, dynamic> json) {
    return HoursException(
      id: json['id'] as String?,
      days: {for (final d in (json['days'] as List? ?? const [])) d as int},
      openHour: json['open_hour'] as int? ?? 0,
      closeHour: json['close_hour'] as int? ?? 0,
      closedAllDay: json['closed_all_day'] as bool? ?? false,
      everyWeek: json['every_week'] as bool? ?? true,
    );
  }

  // --- Mapping ---------------------------------------------------------------

  /// Real minutes behind each client-side option label.
  static const _offlineAlertMinutes = [2, 5, 15, 30];

  /// The fourth option is "At close", which is not a duration — it has no entry
  /// here and travels as [Guardrails.takeoverAlertIndex] == 3 ⇄
  /// `takeover_alert_at_close`.
  static const _takeoverAlertMinutes = [60, 120, 240];

  static const _atCloseIndex = 3;

  static Guardrails _guardrailsFromJson(Map<String, dynamic> json) {
    final atClose = json['takeover_alert_at_close'] as bool? ?? false;
    return Guardrails(
      volumeMin: json['volume_min_pct'] as int? ?? 26,
      volumeMax: json['volume_max_pct'] as int? ?? 70,
      quietHoursOn: json['quiet_hours_on'] as bool? ?? true,
      floorLeeway: switch (json['floor_leeway'] as String?) {
        'view_only' => FloorLeeway.viewOnly,
        'full_band' => FloorLeeway.fullBand,
        _ => FloorLeeway.nudge10,
      },
      transition: switch (json['transition'] as String?) {
        'seamless' => TransitionSmoothness.seamless,
        'lively' => TransitionSmoothness.lively,
        _ => TransitionSmoothness.gentle,
      },
      takeoverAccess: json['takeover_access'] == 'managers'
          ? TakeoverAccess.managers
          : TakeoverAccess.managersPlusFloor,
      offlineAlertIndex: _minutesToIndex(
        json['offline_alert_minutes'] as int?,
        _offlineAlertMinutes,
        fallback: 1,
      ),
      takeoverAlertIndex: atClose
          ? _atCloseIndex
          : _minutesToIndex(
              json['takeover_alert_minutes'] as int?,
              _takeoverAlertMinutes,
              fallback: 1,
            ),
    );
  }

  static Map<String, dynamic> _guardrailsToJson(Guardrails g) {
    final atClose = g.takeoverAlertIndex == _atCloseIndex;
    return {
      'volume_min_pct': g.volumeMin,
      'volume_max_pct': g.volumeMax,
      'quiet_hours_on': g.quietHoursOn,
      // quiet_hours_start_local / quiet_hours_cap_pct deliberately absent —
      // the model has no field for them and the server keeps what it has.
      'floor_leeway': switch (g.floorLeeway) {
        FloorLeeway.viewOnly => 'view_only',
        FloorLeeway.nudge10 => 'nudge_10',
        FloorLeeway.fullBand => 'full_band',
      },
      'transition': switch (g.transition) {
        TransitionSmoothness.seamless => 'seamless',
        TransitionSmoothness.gentle => 'gentle',
        TransitionSmoothness.lively => 'lively',
      },
      'takeover_access': switch (g.takeoverAccess) {
        TakeoverAccess.managers => 'managers',
        TakeoverAccess.managersPlusFloor => 'managers_plus_floor',
      },
      'offline_alert_minutes': _indexToMinutes(
        g.offlineAlertIndex,
        _offlineAlertMinutes,
        fallback: 5,
      ),
      // Kept at the last real duration while "At close" is selected, so
      // toggling back restores the previous choice instead of a default.
      'takeover_alert_minutes': atClose
          ? 120
          : _indexToMinutes(
              g.takeoverAlertIndex,
              _takeoverAlertMinutes,
              fallback: 120,
            ),
      'takeover_alert_at_close': atClose,
    };
  }

  /// Closest option to [minutes], so a value set outside the app (or by a
  /// future option list) still renders as something sensible.
  static int _minutesToIndex(
    int? minutes,
    List<int> options, {
    required int fallback,
  }) {
    if (minutes == null) return fallback;
    var best = 0;
    var bestDistance = (options.first - minutes).abs();
    for (var i = 1; i < options.length; i++) {
      final distance = (options[i] - minutes).abs();
      if (distance < bestDistance) {
        best = i;
        bestDistance = distance;
      }
    }
    return best;
  }

  static int _indexToMinutes(
    int index,
    List<int> options, {
    required int fallback,
  }) =>
      (index >= 0 && index < options.length) ? options[index] : fallback;

  void dispose() {
    _guardrailsTimer?.cancel();
    // Best effort for a change made in the debounce window just before
    // teardown — fired without awaiting, since there is nothing left to
    // update on failure.
    final pending = _pendingGuardrails;
    _pendingGuardrails = null;
    if (pending != null) {
      unawaited(_client
          .put(
            '/zones/${_scope.requireZone()}/guardrails',
            body: _guardrailsToJson(pending),
          )
          .catchError((_) => null));
    }
    _settled?.complete();
    _settled = null;
    _failures.close();
    _guardrails.dispose();
    _openHours.dispose();
  }
}
