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

  /// Throws a 409 `daypart_slot_taken` when another daypart on the same day
  /// already starts at the same time, unless [replace] is set.
  ///
  /// Same start time is the one overlap the scheduler cannot resolve:
  /// `app.scheduled_mood_for` ends `order by start_local desc limit 1`, and
  /// between equal keys that order is unspecified, so the room plays an
  /// arbitrary one of the two and can change its mind between ticks. Ordinary
  /// overlap stays allowed — it resolves to the later start, and a contiguous
  /// weekly plan means a drag can hardly move without touching a neighbour.
  ///
  /// [replace] is not a "force" flag for convenience: it is how the UI says the
  /// manager was shown what would be overwritten and agreed to it.
  Future<void> addDaypart(Daypart daypart, {bool replace = false});
  Future<void> updateDaypart(Daypart daypart, {bool replace = false});
  Future<void> deleteDaypart(String id);
}

/// Zone-scoped like the API repo — see [playbackRepoProvider] for why the
/// resolver is a closure rather than a captured value.
final scheduleRepoProvider = Provider<ScheduleRepo>((ref) {
  final repo = MockScheduleRepo(zoneId: () => ref.read(currentZoneIdProvider));
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
