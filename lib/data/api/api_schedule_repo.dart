import 'dart:async';

import '../models/schedule_entry.dart';
import '../repositories/schedule_repo.dart';
import 'api_client.dart';
import 'api_scope.dart';
import 'watchable.dart';

/// `ScheduleRepo` against the real API.
///
/// `TodaySchedule.nowIndex` is taken from the server, never computed here: it
/// depends on the current time in the *venue's* timezone, which the client does
/// not know. A device in another timezone would otherwise highlight the wrong
/// row on the Floor rail.
class ApiScheduleRepo implements ScheduleRepo {
  ApiScheduleRepo(this._client, this._scope);

  final ApiClient _client;
  final ApiScope _scope;

  late final _today = Watchable<TodaySchedule>(
    _fetchToday,
    scopeKey: _scope.zoneKey,
  );
  late final _mode = Watchable<ScheduleMode>(
    _fetchMode,
    scopeKey: _scope.zoneKey,
  );
  late final _plan = Watchable<List<Daypart>>(
    _fetchPlan,
    scopeKey: _scope.zoneKey,
  );

  @override
  Stream<TodaySchedule> watchToday() => _today.watch();

  @override
  Stream<ScheduleMode> watchMode() => _mode.watch();

  @override
  Future<void> setMode(ScheduleMode mode) async {
    await _client.post(
      '/zones/${_scope.requireZone()}/mode',
      body: {'mode': mode == ScheduleMode.selfDrive ? 'self_drive' : 'custom'},
    );
    await _mode.refresh();
    // Switching between self-drive and a custom plan changes what the Floor
    // rail should show, so today has to come along.
    await _today.refresh();
  }

  /// The week currently being watched, so writes land in the right plan and
  /// the cached fetch is of the right thing.
  DateTime? _week;

  @override
  Stream<List<Daypart>> watchWeekPlan(DateTime? weekStart) {
    if (weekStart != _week) {
      _week = weekStart;
      // The cache is of a different week by definition; drop it rather than
      // serve last week's plan under this week's header.
      unawaited(_plan.refresh().catchError((_) {}));
    }
    return _plan.watch();
  }

  @override
  Future<void> forkWeek(DateTime weekStart) async {
    await _client.post(
      '/zones/${_scope.requireZone()}/dayparts/fork',
      body: {'week_start': _iso(weekStart)},
    );
    // The fork has new ids, so the screen must re-read before editing them —
    // this is why forking is its own endpoint rather than a flag on the writes.
    await _refreshPlan();
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Future<void> addDaypart(Daypart daypart) async {
    // The client's `id` is ignored — the server assigns the real one, which is
    // why the sheet can construct a Daypart with an empty id.
    await _client.post(
      '/zones/${_scope.requireZone()}/dayparts',
      body: _daypartToJson(daypart),
    );
    await _refreshPlan();
  }

  @override
  Future<void> updateDaypart(Daypart daypart) async {
    await _client.patch('/dayparts/${daypart.id}', body: _daypartToJson(daypart));
    await _refreshPlan();
  }

  @override
  Future<void> deleteDaypart(String id) async {
    await _client.delete('/dayparts/$id');
    await _refreshPlan();
  }

  /// Any plan change can move the "NOW" row, so both streams refresh together.
  Future<void> _refreshPlan() async {
    await _plan.refresh();
    await _today.refresh();
  }

  Future<TodaySchedule> _fetchToday() async {
    final json = await _client.get('/zones/${_scope.requireZone()}/today')
        as Map<String, dynamic>;
    return TodaySchedule(
      entries: [
        for (final raw in (json['entries'] as List? ?? const []))
          ScheduleEntry(
            timeLabel: (raw as Map)['time_label'] as String? ?? '',
            moodId: raw['mood_id'] as String? ?? 'daytime-flow',
          ),
      ],
      nowIndex: json['now_index'] as int? ?? 0,
      // Defaulted to "the day is done" rather than 0: a server that does not
      // send it must not make the first row claim to be next.
      nextIndex: json['next_index'] as int? ?? -1,
      auto: json['auto'] as bool? ?? true,
      // Absent from an older server: assume a plan IS running, so the rail
      // keeps its documented behaviour rather than hiding the schedule.
      selfDrive: json['self_drive'] as bool? ?? false,
    );
  }

  Future<ScheduleMode> _fetchMode() async {
    final json = await _client.get('/zones/${_scope.requireZone()}/mode')
        as Map<String, dynamic>;
    return json['mode'] == 'custom' ? ScheduleMode.custom : ScheduleMode.selfDrive;
  }

  Future<List<Daypart>> _fetchPlan() async {
    final week = _week;
    final query = week == null ? '' : '?week=${_iso(week)}';
    final json = await _client
        .get('/zones/${_scope.requireZone()}/dayparts$query') as List;
    return [
      for (final raw in json)
        _daypartFrom((raw as Map).cast<String, dynamic>()),
    ];
  }

  static Daypart _daypartFrom(Map<String, dynamic> json) => Daypart(
        id: json['id'] as String,
        dayIndex: json['day_index'] as int? ?? 0,
        startHour: json['start_hour'] as int? ?? 0,
        endHour: json['end_hour'] as int? ?? 0,
        // Defaulted, not required: a server that predates minute precision
        // sends neither, and whole hours are what it meant.
        startMinute: json['start_minute'] as int? ?? 0,
        endMinute: json['end_minute'] as int? ?? 0,
        moodId: json['mood_id'] as String? ?? 'daytime-flow',
        weekStart: json['week_start'] == null
            ? null
            : DateTime.tryParse(json['week_start'] as String),
        // Prefer the server's label so the two can never disagree about how a
        // range reads; Daypart derives its own if it is absent.
        serverRangeLabel: json['range_label'] as String?,
      );

  /// `range_label` is deliberately not sent — it is derived from the times
  /// server-side, so sending it would invite the two to drift apart.
  static Map<String, dynamic> _daypartToJson(Daypart d) => {
        'day_index': d.dayIndex,
        'start_hour': d.startHour,
        'end_hour': d.endHour,
        'start_minute': d.startMinute,
        'end_minute': d.endMinute,
        'mood_id': d.moodId,
        // Which plan the row belongs to. Null is the recurring plan, which is
        // also what an older server ignores harmlessly.
        'week_start': d.weekStart == null ? null : _iso(d.weekStart!),
      };

  void dispose() {
    _today.dispose();
    _mode.dispose();
    _plan.dispose();
  }
}
