import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';
import '../mock/mock_schedule_repo.dart';
import '../models/schedule_entry.dart';

/// Schedule boundary — the Floor rail's today-view and the §2 S03 weekly
/// plan (self-drive ⇄ custom, daypart CRUD; the mock plan recurs weekly).
abstract class ScheduleRepo {
  /// Emits today's schedule immediately, then on any change.
  Stream<TodaySchedule> watchToday();

  /// S03-1 ⇄ S03-2 switch.
  Stream<ScheduleMode> watchMode();
  Future<void> setMode(ScheduleMode mode);

  /// The custom weekly plan (S03-2), all days, for one week.
  ///
  /// [weekStart] must be a Monday. Returns that week's fork if it has one,
  /// otherwise the recurring plan — never a merge of the two. Null asks for the
  /// recurring plan directly.
  ///
  /// Parameterised because it was not: the screen's week arrows moved a label
  /// and nothing else, so every week rendered the same dayparts and a manager
  /// editing "next week" was editing all of them.
  Stream<List<Daypart>> watchWeekPlan(DateTime? weekStart);

  /// "Just this week" — copy the recurring plan into [weekStart] so it can
  /// diverge. Idempotent; a week that is already forked is left alone.
  ///
  /// Forking is permanent in one direction: once a week has its own plan it
  /// stops tracking changes to the recurring one. The sheet says so before
  /// asking.
  Future<void> forkWeek(DateTime weekStart);

  Future<void> addDaypart(Daypart daypart);
  Future<void> updateDaypart(Daypart daypart);
  Future<void> deleteDaypart(String id);
}

final scheduleRepoProvider = Provider<ScheduleRepo>((ref) {
  final repo = MockScheduleRepo();
  ref.onDispose(repo.dispose);
  return repo;
});

/// Zone-scoped, so each resubscribes when sign-in establishes the zone.
final todayScheduleProvider = StreamProvider.autoDispose<TodaySchedule>((ref) {
  ref.watch(currentZoneIdProvider);
  return ref.watch(scheduleRepoProvider).watchToday();
});

final scheduleModeProvider = StreamProvider.autoDispose<ScheduleMode>((ref) {
  ref.watch(currentZoneIdProvider);
  return ref.watch(scheduleRepoProvider).watchMode();
});

/// Keyed by the week's Monday. A family, because the plan genuinely differs
/// week to week now — one provider for all weeks was the whole of H-09.
final weekPlanProvider =
    StreamProvider.autoDispose.family<List<Daypart>, DateTime?>((ref, week) {
  ref.watch(currentZoneIdProvider);
  return ref.watch(scheduleRepoProvider).watchWeekPlan(week);
});
