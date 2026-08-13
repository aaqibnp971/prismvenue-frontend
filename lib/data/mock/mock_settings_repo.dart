import 'dart:async';

import '../models/guardrails.dart';
import '../repositories/settings_repo.dart';

/// Marina Café settings seed — §2 S05 frame values: band 26–70%, quiet
/// hours on, Nudge ±10%, Gentle, Managers + floor, default hours 7am–11pm
/// with the S05-10 Fri & Sat 7am–1am exception. Alert defaults are not
/// pinned (open_questions).
///
/// Guardrails are **per zone** and open hours are **per venue**, matching the
/// schema (`zone_guardrails.zone_id`, `open_hours.venue_id`) — so two rooms
/// hold two volume bands, while both rooms of one venue share its opening
/// times. Shared state here was invisible until "Open floor" started working
/// on every zone; after that it made every venue look like it had the same
/// settings.
class MockSettingsRepo implements SettingsRepo {
  MockSettingsRepo({String? Function()? zoneId, String? Function()? venueId})
      : _zoneId = zoneId ?? (() => null),
        _venueId = venueId ?? (() => null);

  /// Resolved at call time, exactly as `ApiScope` does it. Both default to a
  /// resolver returning null, which collapses everything into one bucket — the
  /// pre-scope behaviour, and what a test constructing this directly gets.
  final String? Function() _zoneId;
  final String? Function() _venueId;

  final _guardrailsByZone = <String?, Guardrails>{};

  Guardrails get _guardrails =>
      _guardrailsByZone[_zoneId()] ?? const Guardrails();

  static const _seedHours = OpenHours(
    exceptions: [
      HoursException(id: 'e-seed', days: {4, 5}, openHour: 7, closeHour: 1),
    ],
  );

  final _hoursByVenue = <String?, OpenHours>{};

  OpenHours get _hours => _hoursByVenue[_venueId()] ?? _seedHours;

  var _nextExceptionId = 0;

  final _guardrailsController = StreamController<Guardrails>.broadcast();
  final _hoursController = StreamController<OpenHours>.broadcast();

  @override
  Stream<Guardrails> watchGuardrails() async* {
    yield _guardrails;
    yield* _guardrailsController.stream;
  }

  @override
  Stream<Object> get guardrailFailures => const Stream.empty();

  @override
  Future<void> updateGuardrails(Guardrails next) async {
    _guardrailsByZone[_zoneId()] = next;
    _guardrailsController.add(next);
  }

  @override
  Stream<OpenHours> watchOpenHours() async* {
    yield _hours;
    yield* _hoursController.stream;
  }

  void _emitHours(OpenHours next) {
    _hoursByVenue[_venueId()] = next;
    _hoursController.add(next);
  }

  @override
  Future<void> setEverydayHours(
      {required int openHour, required int closeHour}) async {
    _emitHours(_hours.copyWith(openHour: openHour, closeHour: closeHour));
  }

  @override
  Future<void> addException(HoursException exception) async {
    // The server assigns the real id; the mock stands in for that so edit and
    // delete have something to address.
    final saved = HoursException(
      id: 'e-${_nextExceptionId++}',
      days: exception.days,
      openHour: exception.openHour,
      closeHour: exception.closeHour,
      closedAllDay: exception.closedAllDay,
      everyWeek: exception.everyWeek,
    );
    _emitHours(_hours.copyWith(exceptions: [..._hours.exceptions, saved]));
  }

  @override
  Future<void> updateException(HoursException exception) async {
    _emitHours(_hours.copyWith(exceptions: [
      for (final e in _hours.exceptions)
        if (e.id == exception.id) exception else e,
    ]));
  }

  @override
  Future<void> deleteException(String id) async {
    _emitHours(_hours.copyWith(
        exceptions: _hours.exceptions.where((e) => e.id != id).toList()));
  }

  void dispose() {
    _guardrailsController.close();
    _hoursController.close();
  }
}
