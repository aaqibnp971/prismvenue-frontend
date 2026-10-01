/// Keeps the device's copy of the plan fresh while the connection is up, so
/// there is something to fall back to when it is not. Finding #7.
///
/// ## Why a worker rather than a screen
///
/// The obvious place to cache the plan is wherever it is already fetched — but
/// the Schedule tab is manager and owner only, and the Floor screen never asks
/// for dayparts at all. A floor-staff iPad, which is the device actually
/// standing in the venue, would have cached nothing. So this runs on its own
/// clock for the life of the process, like [LastSeenReporter], and does not
/// care what is on screen.
///
/// ## Timing
///
/// Every 15 minutes, and immediately whenever the operated zone changes. The
/// plan is a thing people edit a few times a month; the interval only has to
/// be short enough that an edit is picked up the same shift, and long enough
/// that a venue with a dozen rooms is not paying for it. It also runs once at
/// start, which is what makes a tablet that has been off for a week come back
/// with something to play before the network settles.
///
/// ## What it costs when it fails
///
/// Nothing. Every failure is swallowed: the cache simply keeps what it had,
/// and a cache that is a day stale still runs the room far better than no
/// cache does. It reads through the repository interfaces rather than the API
/// client, so it works unchanged against either backend and does no harm on
/// mocks.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api/offline_plan_cache.dart';
import '../data/api/providers.dart';
import '../data/models/schedule_entry.dart';
import '../data/repositories/schedule_repo.dart';
import '../data/repositories/settings_repo.dart';
import 'session.dart';

/// How often the cached plan is refreshed. See the library note.
const offlinePlanSyncInterval = Duration(minutes: 15);

/// Held for the life of the app. Constructed here but **not started** here —
/// `start()` is called by `main()`, for the same reason [LastSeenReporter] is:
/// a repeating timer is a side effect of the app running, and a widget test
/// that pumps the app should not inherit one.
final offlinePlanSyncProvider = Provider<OfflinePlanSync>((ref) {
  final sync = OfflinePlanSync(ref);
  ref.onDispose(sync.dispose);
  return sync;
});

class OfflinePlanSync {
  OfflinePlanSync(this._ref, {Duration interval = offlinePlanSyncInterval})
      : _interval = interval;

  final Ref _ref;
  final Duration _interval;
  final _subscriptions = <ProviderSubscription<Object?>>[];
  Timer? _timer;

  void start() {
    _timer = Timer.periodic(_interval, (_) => unawaited(syncNow()));
    _subscriptions.add(
      _ref.listen<String?>(
        currentZoneIdProvider,
        (previous, next) {
          if (next != null && next != previous) unawaited(syncNow());
        },
        fireImmediately: true,
      ),
    );
  }

  /// One refresh for the zone in hand. Safe to call at any time.
  Future<void> syncNow() async {
    if (_ref.read(sessionProvider) == null) return;
    final zoneId = _ref.read(currentZoneIdProvider);
    if (zoneId == null) return;
    final cache = _ref.read(offlinePlanCacheProvider);

    try {
      final schedule = _ref.read(scheduleRepoProvider);
      // The recurring plan, not the week in view: a fork is temporary by
      // definition, and during an outage the plan the venue means is the one
      // that repeats. `null` asks for the recurring plan directly.
      final plan = await schedule.watchWeekPlan(null).first;
      final mode = await schedule.watchMode().first;
      final today = await schedule.watchToday().first;
      final hours = await _ref.read(settingsRepoProvider).watchOpenHours().first;

      await cache.rememberPlan(
        zoneId,
        plan: plan,
        selfDrive: mode == ScheduleMode.selfDrive,
        hours: hours,
        // Null leaves whatever offset the cache already had, which is a better
        // guess than zero — UTC would silently move an Asia/Dubai venue's
        // whole day by four hours.
        venueOffsetMinutes: venueOffsetFrom(today.venueTime),
      );
    } catch (_) {
      // Offline, or a role that cannot read the schedule. Either way the cache
      // keeps what it had, which is the entire point of it.
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    for (final s in _subscriptions) {
      s.close();
    }
    _subscriptions.clear();
  }
}
