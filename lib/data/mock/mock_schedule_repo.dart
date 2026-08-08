import 'dart:async';

import '../models/schedule_entry.dart';
import '../repositories/schedule_repo.dart';

/// Marina Café schedule seeds. The rail's 5 rows come from the README
/// examples; the weekly plan mirrors them on every day within the S05-6
/// default open hours (7am–11pm). Exact times are seed data
/// (open_questions).
class MockScheduleRepo implements ScheduleRepo {
  /// Rebuilt per read so switching mode moves the Floor rail too — the plan
  /// only "runs" on a custom plan.
  TodaySchedule get _today => TodaySchedule(
        auto: true,
        nowIndex: 2,
        selfDrive: _mode == ScheduleMode.selfDrive,
        entries: _todayEntries,
      );

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

  var _mode = ScheduleMode.selfDrive; // S03-1 is the entry frame
  late final List<Daypart> _plan = [
    for (var day = 0; day < 7; day++)
      for (final (i, (start, end, moodId)) in _dayTemplate.indexed)
        Daypart(
          id: 'd$day-$i',
          dayIndex: day,
          startHour: start,
          endHour: end,
          moodId: moodId,
        ),
  ];
  var _nextId = 0;

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
    yield _mode;
    yield* _modeController.stream;
  }

  @override
  Future<void> setMode(ScheduleMode mode) async {
    _mode = mode;
    _modeController.add(mode);
    // The Floor rail shows whether the plan is running, so it has to hear
    // about the switch too.
    _todayController.add(_today);
  }

  /// Forked weeks, keyed by Monday. Absent means the week shows [_plan].
  final _forks = <DateTime, List<Daypart>>{};

  /// The week currently being watched, so [_emitPlan] emits the right one.
  DateTime? _watching;

  List<Daypart> _effective(DateTime? week) {
    final fork = week == null ? null : _forks[week];
    return List.unmodifiable(fork ?? _plan);
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
    if (_forks.containsKey(weekStart)) return;
    _forks[weekStart] = [
      for (final d in _plan)
        Daypart(
          id: 'fork-${_nextId++}',
          dayIndex: d.dayIndex,
          startHour: d.startHour,
          endHour: d.endHour,
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
    if (week != null && _forks.containsKey(week)) return _forks[week]!;
    return _plan;
  }

  void _emitPlan() => _planController.add(_effective(_watching));

  @override
  Future<void> addDaypart(Daypart daypart) async {
    _target.add(Daypart(
      id: 'new-${_nextId++}',
      dayIndex: daypart.dayIndex,
      startHour: daypart.startHour,
      endHour: daypart.endHour,
      moodId: daypart.moodId,
      weekStart: daypart.weekStart,
    ));
    _emitPlan();
  }

  @override
  Future<void> updateDaypart(Daypart daypart) async {
    final i = _plan.indexWhere((d) => d.id == daypart.id);
    if (i != -1) _plan[i] = daypart;
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
