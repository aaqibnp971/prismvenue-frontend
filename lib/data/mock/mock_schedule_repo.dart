import 'dart:async';

import '../models/schedule_entry.dart';
import '../repositories/schedule_repo.dart';

/// Marina Café schedule seeds. The rail's 5 rows come from the README
/// examples; the weekly plan mirrors them on every day within the S05-6
/// default open hours (7am–11pm). Exact times are seed data
/// (open_questions).
///
/// **Everything here is per zone**, keyed by [zoneId], because that is what the
/// schema is: `dayparts.zone_id` and `zone_guardrails.self_drive` are both
/// per-zone, so two rooms run two plans and switching one must not move the
/// other. The mock held one shared plan and one shared mode, which was
/// invisible while the app had no way to change rooms and became actively
/// misleading once "Open floor" started working on every zone.
class MockScheduleRepo implements ScheduleRepo {
  MockScheduleRepo({
    String? Function()? zoneId,
    this.emptyToday = false,
    this.nothingScheduledNow = false,
  }) : _zoneId = zoneId ?? (() => null);

  /// Today's rail comes back empty, as it does for a zone whose week is forked
  /// with nothing on this weekday — migration 011 never merges a fork with the
  /// recurring plan, so a full weekly plan can still have an empty Friday.
  /// Exercises the dimmed Auto button and its dialog.
  final bool emptyToday;

  /// Today's rail is FULL but nothing in it covers this moment — the plan
  /// resumes later in the evening. Distinct from [emptyToday] and much more
  /// confusing on screen, because the rail visibly has blocks in it while Auto
  /// correctly does nothing. Seen live on a zone whose only Saturday dayparts
  /// ran 20:00–21:00, viewed at 18:42.
  final bool nothingScheduledNow;

  /// Resolved at call time, exactly as `ApiScope` does it, so switching the
  /// session's zone repoints this repository with nothing to rebuild.
  ///
  /// Defaults to a resolver returning null, which collapses every zone into
  /// one bucket — the pre-zone behaviour, and what a test constructing this
  /// directly still gets.
  final String? Function() _zoneId;

  static const _todayEntries = [
    ScheduleEntry(timeLabel: '7:00 am', moodId: 'morning-calm'),
    ScheduleEntry(timeLabel: '11:00 am', moodId: 'daytime-flow'),
    ScheduleEntry(timeLabel: '2:00 pm', moodId: 'afternoon-lift'),
    ScheduleEntry(timeLabel: '6:00 pm', moodId: 'evening-warmth'),
    ScheduleEntry(timeLabel: '9:00 pm', moodId: 'peak'),
  ];

  /// (startHour, endHour, moodId) — the same blocks as before, now as real
  /// hours. Their derived labels are identical to the strings this used to
  /// hold: "7 – 11 am", "11 am – 2 pm", "2 – 6 pm", "6 – 9 pm", "9 – 11 pm".
  static const _dayTemplate = [
    (7, 11, 'morning-calm'),
    (11, 14, 'daytime-flow'),
    (14, 18, 'afternoon-lift'),
    (18, 21, 'evening-warmth'),
    (21, 23, 'peak'),
  ];

  final _zones = <String?, _ZoneSchedule>{};
  var _nextId = 0;

  /// This zone's plan, seeded on first look. A room nobody has opened yet
  /// starts on the same defaults a fresh zone gets from the server: self-drive
  /// (S03-1 is the entry frame) over the seeded weekly plan.
  _ZoneSchedule get _z =>
      _zones.putIfAbsent(_zoneId(), () => _ZoneSchedule(_seedPlan()));

  List<Daypart> _seedPlan() => [
        for (var day = 0; day < 7; day++)
          for (final (i, (start, end, moodId)) in _dayTemplate.indexed)
            Daypart(
              id: 'd${_nextId++}-$day-$i',
              dayIndex: day,
              startHour: start,
              endHour: end,
              moodId: moodId,
            ),
      ];

  /// Rebuilt per read so switching mode moves the Floor rail too — the plan
  /// only "runs" on a custom plan.
  ///
  /// `nowIndex` follows the entries rather than being a constant. The server
  /// returns -1 when nothing in the plan covers this moment, and an empty rail
  /// is the clearest case of that — a mock that answered 2 over no entries
  /// claimed a current daypart that does not exist, which is exactly the shape
  /// of bug the real rail had. The seeded plan is contiguous and covers the
  /// whole day, so a non-empty one always has something current; 2 keeps the
  /// afternoon block highlighted as before.
  TodaySchedule get _today => TodaySchedule(
        auto: true,
        nowIndex: (emptyToday || nothingScheduledNow) ? -1 : 2,
        selfDrive: _z.mode == ScheduleMode.selfDrive,
        entries: emptyToday ? const [] : _todayEntries,
      );

  final _todayController = StreamController<TodaySchedule>.broadcast();
  final _modeController = StreamController<ScheduleMode>.broadcast();
  final _planController = StreamController<List<Daypart>>.broadcast();

  @override
  Stream<TodaySchedule> watchToday() async* {
    yield _today;
    yield* _todayController.stream;
  }

  @override
  Stream<ScheduleMode> watchMode() async* {
    yield _z.mode;
    yield* _modeController.stream;
  }

  @override
  Future<void> setMode(ScheduleMode mode) async {
    _z.mode = mode;
    _modeController.add(mode);
    // The Floor rail shows whether the plan is running, so it has to hear
    // about the switch too.
    _todayController.add(_today);
  }

  /// The week currently being watched, so [_emitPlan] emits the right one.
  DateTime? _watching;

  List<Daypart> _effective(DateTime? week) {
    final fork = week == null ? null : _z.forks[week];
    return List.unmodifiable(fork ?? _z.plan);
  }

  @override
  Stream<List<Daypart>> watchWeekPlan(DateTime? weekStart) async* {
    _watching = weekStart;
    yield _effective(weekStart);
    yield* _planController.stream;
  }

  @override
  Future<void> forkWeek(DateTime weekStart) async {
    // Idempotent, like the server: a week that already has its own plan is left
    // alone, so a double tap cannot duplicate it.
    if (_z.forks.containsKey(weekStart)) return;
    _z.forks[weekStart] = [
      for (final d in _z.plan)
        Daypart(
          id: 'fork-${_nextId++}',
          dayIndex: d.dayIndex,
          startHour: d.startHour,
          endHour: d.endHour,
          startMinute: d.startMinute,
          endMinute: d.endMinute,
          moodId: d.moodId,
          weekStart: weekStart,
        ),
    ];
    _emitPlan();
  }

  /// The list a write should land in — the watched week's fork when it has one,
  /// otherwise the recurring plan.
  List<Daypart> get _target {
    final week = _watching;
    if (week != null && _z.forks.containsKey(week)) return _z.forks[week]!;
    return _z.plan;
  }

  void _emitPlan() => _planController.add(_effective(_watching));

  @override
  Future<void> addDaypart(Daypart daypart) async {
    _target.add(Daypart(
      id: 'new-${_nextId++}',
      dayIndex: daypart.dayIndex,
      startHour: daypart.startHour,
      endHour: daypart.endHour,
      startMinute: daypart.startMinute,
      endMinute: daypart.endMinute,
      moodId: daypart.moodId,
      weekStart: daypart.weekStart,
    ));
    _emitPlan();
  }

  @override
  Future<void> updateDaypart(Daypart daypart) async {
    // `_target`, not the recurring plan. Searching `_plan` meant a forked
    // week's rows — whose ids are `fork-N` and therefore never in it — matched
    // nothing, so editing a daypart in a week someone had chosen "just this
    // week" for was a silent no-op. Add and delete already used `_target`.
    final i = _target.indexWhere((d) => d.id == daypart.id);
    if (i != -1) _target[i] = daypart;
    _emitPlan();
  }

  @override
  Future<void> deleteDaypart(String id) async {
    _target.removeWhere((d) => d.id == id);
    _emitPlan();
  }

  void dispose() {
    _todayController.close();
    _modeController.close();
    _planController.close();
  }
}

/// One room's schedule: which mode it is in, its recurring plan, and any weeks
/// forked off it.
class _ZoneSchedule {
  _ZoneSchedule(this.plan);

  /// S03-1 is the entry frame, so an untouched zone is self-driving — the same
  /// default `GET /mode` applies to a zone with no guardrails row.
  var mode = ScheduleMode.selfDrive;

  final List<Daypart> plan;

  /// Forked weeks, keyed by Monday. Absent means the week shows [plan].
  final forks = <DateTime, List<Daypart>>{};
}
