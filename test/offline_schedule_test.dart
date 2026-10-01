/// Finding #7 — the room keeps playing when the internet does not.
///
/// The predicate in [OfflinePlan] is a second implementation of
/// `app.scheduled_mood_for` and `app.venue_open_window`, which is a thing worth
/// being nervous about: two implementations of one rule disagree eventually,
/// and the way this one would disagree is a room playing the wrong mood in an
/// outage nobody is watching. So the cases here are chosen to be the ones the
/// SQL gets right and a naive port does not — the past-midnight wrap, the gap
/// between blocks, overlapping blocks, and the boundary minutes themselves.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/api/offline_plan_cache.dart';

/// A UTC instant that reads as [local] on a venue four hours ahead.
///
/// Deliberately not the device's own zone: the whole failure this feature
/// exists to prevent is the tablet reasoning in its own time rather than the
/// venue's, and a test that ran in the venue's zone would never see it.
const _offset = 4 * 60; // Asia/Dubai

DateTime _utcFor(int weekday, int hour, int minute) {
  // 2026-09-28 is a Monday. weekday here is 0 = Monday.
  final local = DateTime.utc(2026, 9, 28 + weekday, hour, minute);
  return local.subtract(const Duration(minutes: _offset));
}

OfflinePlan _plan(List<OfflineBlock> blocks, {int? open, int? close}) =>
    OfflinePlan(
      blocks: blocks,
      venueOffsetMinutes: _offset,
      openMinutes: open,
      closeMinutes: close,
      lastMoodId: 'daytime-flow',
      lastPlayerInstallationId: 'this-tablet',
    );

OfflineBlock _block(int day, int startMin, int endMin, String mood) =>
    OfflineBlock(
      dayIndex: day,
      startMinutes: startMin,
      endMinutes: endMin,
      moodId: mood,
    );

void main() {
  group('the plan, run on the device', () {
    test('a block in progress is the one playing', () {
      final plan = _plan([_block(0, 8 * 60, 12 * 60, 'morning-calm')]);

      expect(plan.moodAt(_utcFor(0, 9, 0)), 'morning-calm');
    });

    test('start is inclusive and end is exclusive, to the minute', () {
      // The same `start <= now < end` the executor uses. A block that is still
      // playing one minute after it ended is the disagreement that made the
      // Floor rail and the room contradict each other before finding #16.
      final plan = _plan([_block(0, 8 * 60, 12 * 60, 'morning-calm')]);

      expect(plan.moodAt(_utcFor(0, 7, 59)), isNot('morning-calm'));
      expect(plan.moodAt(_utcFor(0, 8, 0)), 'morning-calm');
      expect(plan.moodAt(_utcFor(0, 11, 59)), 'morning-calm');
      expect(plan.moodAt(_utcFor(0, 12, 0)), isNot('morning-calm'));
    });

    test('nothing covering this moment is null, not the first block', () {
      // A gap is a real answer: migration 010 holds the last mood through one
      // rather than snapping the room to silence or to a default, and so does
      // this. Answering with block zero is exactly the bug finding #16 fixed
      // on the rail.
      final plan = _plan([
        _block(0, 8 * 60, 10 * 60, 'morning-calm'),
        _block(0, 14 * 60, 18 * 60, 'afternoon-lift'),
      ]);

      expect(plan.moodAt(_utcFor(0, 12, 0)), isNull);
      expect(plan.moodAt(_utcFor(0, 6, 0)), isNull);
      expect(plan.moodAt(_utcFor(0, 20, 0)), isNull);
    });

    test('where two blocks overlap, the later start wins', () {
      // `order by start_local desc limit 1`. Overlap is deliberately allowed
      // by the schema; only an exact tie is refused.
      final plan = _plan([
        _block(0, 8 * 60, 18 * 60, 'morning-calm'),
        _block(0, 12 * 60, 16 * 60, 'afternoon-lift'),
      ]);

      expect(plan.moodAt(_utcFor(0, 13, 0)), 'afternoon-lift');
      expect(plan.moodAt(_utcFor(0, 17, 0)), 'morning-calm');
    });

    test('a block running past midnight still plays after midnight', () {
      // 22:00–02:00 on Monday is Tuesday's mood at 01:00. Without the wrap the
      // room goes quiet at midnight in exactly the venues that are busiest.
      final plan = _plan([_block(0, 22 * 60, 2 * 60, 'peak')]);

      expect(plan.moodAt(_utcFor(0, 23, 0)), 'peak');
      expect(plan.moodAt(_utcFor(1, 1, 0)), 'peak');
      expect(plan.moodAt(_utcFor(1, 3, 0)), isNull);
      // And not on the wrong night.
      expect(plan.moodAt(_utcFor(2, 1, 0)), isNull);
    });

    test('a day with no blocks plays nothing of another day\'s', () {
      final plan = _plan([_block(0, 8 * 60, 12 * 60, 'morning-calm')]);

      expect(plan.moodAt(_utcFor(3, 9, 0)), isNull);
    });

    test('self-drive runs nothing, because the server runs nothing', () {
      // Getting this backwards would have an offline tablet start following a
      // plan the venue deliberately switched off — migration 010's job skips
      // self-driving zones, and so must this.
      final plan = OfflinePlan(
        blocks: [_block(0, 8 * 60, 12 * 60, 'morning-calm')],
        venueOffsetMinutes: _offset,
        selfDrive: true,
        lastMoodId: 'peak',
      );

      expect(plan.moodAt(_utcFor(0, 9, 0)), isNull);
      // ...and the room holds what it had rather than going silent.
      expect(plan.stateAt(_utcFor(0, 9, 0), null)!.moodId, 'peak');
    });

    test('the venue clock decides, not the device clock', () {
      // 21:00 UTC is 01:00 the next day in Dubai. A tablet reasoning in its own
      // zone would play Monday evening's mood on Tuesday morning.
      final plan = _plan([
        _block(0, 20 * 60, 23 * 60, 'peak'),
        _block(1, 0, 6 * 60, 'wind-down'),
      ]);

      expect(plan.moodAt(DateTime.utc(2026, 9, 28, 21, 0)), 'wind-down');
    });
  });

  group('open hours, run on the device', () {
    test('inside the window is open, outside is closed', () {
      final plan = _plan([], open: 10 * 60 + 30, close: 19 * 60);

      expect(plan.closedAt(_utcFor(0, 10, 29)), isTrue);
      expect(plan.closedAt(_utcFor(0, 10, 30)), isFalse);
      expect(plan.closedAt(_utcFor(0, 18, 59)), isFalse);
      expect(plan.closedAt(_utcFor(0, 19, 0)), isTrue);
    });

    test('a window that closes after midnight wraps', () {
      final plan = _plan([], open: 18 * 60, close: 2 * 60);

      expect(plan.closedAt(_utcFor(0, 23, 0)), isFalse);
      expect(plan.closedAt(_utcFor(1, 1, 0)), isFalse);
      expect(plan.closedAt(_utcFor(1, 3, 0)), isTrue);
    });

    test('no hours recorded means open, never closed', () {
      // Absent hours are missing data, not a closed sign. Inferring silence
      // from it would take rooms off the air for a setup step nobody knew
      // about — the same reading the server takes.
      expect(_plan([]).closedAt(_utcFor(0, 3, 0)), isFalse);
    });
  });

  group('what the room falls back to', () {
    test('the plan wins over the last known mood', () {
      final plan = _plan([_block(0, 8 * 60, 12 * 60, 'morning-calm')]);

      expect(plan.stateAt(_utcFor(0, 9, 0), 'this-tablet')!.moodId,
          'morning-calm');
    });

    test('with nothing scheduled it holds the last known mood', () {
      // A power cut at 3pm must not come back to silence. This is the half of
      // finding #7 that a plan alone does not cover: a tablet that restarts in
      // a gap has no block to play and still has a room to fill.
      final plan = _plan([_block(0, 8 * 60, 10 * 60, 'morning-calm')]);

      expect(plan.stateAt(_utcFor(0, 15, 0), 'this-tablet')!.moodId,
          'daytime-flow');
    });

    test('with no plan and no last mood it has nothing to say', () {
      // Null, so the caller rethrows and the screen shows the error rather
      // than the app inventing a mood for a room it knows nothing about.
      expect(const OfflinePlan().stateAt(DateTime.now(), null), isNull);
    });

    test('the device that was driving the room keeps driving it', () {
      // Finding #2 does not lapse because the Wi-Fi did — and a tablet that
      // was NOT the player must not start playing just because it went
      // offline, which would be two rooms of music a few hundred ms apart.
      final plan = _plan([]);

      expect(plan.stateAt(_utcFor(0, 9, 0), 'this-tablet')!.playsHere, isTrue);
      expect(plan.stateAt(_utcFor(0, 9, 0), 'other-tablet')!.playsHere, isFalse);
      expect(plan.stateAt(_utcFor(0, 9, 0), null)!.playsHere, isFalse);
    });

    test('a closed venue stays quiet offline too', () {
      // Otherwise every outage reopens finding #4: a clinic that shut at 7pm
      // playing Wind-down all night.
      final plan = _plan(
        [_block(0, 8 * 60, 23 * 60, 'daytime-flow')],
        open: 10 * 60,
        close: 19 * 60,
      );

      expect(plan.stateAt(_utcFor(0, 20, 0), 'this-tablet')!.closed, isTrue);
      expect(plan.stateAt(_utcFor(0, 12, 0), 'this-tablet')!.closed, isFalse);
    });

    test('the context line is dropped rather than carried forward', () {
      // It describes the room as the server saw it, and while offline nobody
      // is seeing it. A stale "~60% full" would be the app stating something
      // it cannot know.
      expect(_plan([]).stateAt(_utcFor(0, 9, 0), null)!.contextLine, '');
    });

    test('a paused room comes back paused', () {
      final plan = OfflinePlan(
        venueOffsetMinutes: _offset,
        lastMoodId: 'peak',
        lastPaused: true,
      );

      expect(plan.stateAt(_utcFor(0, 9, 0), null)!.paused, isTrue);
    });
  });

  group('the venue offset, read from its wall clock', () {
    test('reads a whole-hour offset', () {
      expect(
        venueOffsetFrom('16:00', now: DateTime.utc(2026, 9, 28, 12, 0)),
        4 * 60,
      );
    });

    test('reads a half-hour offset', () {
      expect(
        venueOffsetFrom('17:30', now: DateTime.utc(2026, 9, 28, 12, 0)),
        5 * 60 + 30,
      );
    });

    test('reads an offset behind UTC', () {
      expect(
        venueOffsetFrom('07:00', now: DateTime.utc(2026, 9, 28, 12, 0)),
        -5 * 60,
      );
    });

    test('handles the venue and UTC being on different days', () {
      // 23:00 UTC is 03:00 tomorrow in Dubai. A raw subtraction gives -20
      // hours, which is not an offset any venue has.
      expect(
        venueOffsetFrom('03:00', now: DateTime.utc(2026, 9, 28, 23, 0)),
        4 * 60,
      );
      // ...and the other way: 02:00 UTC is 21:00 yesterday in Los Angeles.
      expect(
        venueOffsetFrom('21:00', now: DateTime.utc(2026, 9, 28, 2, 0)),
        -5 * 60,
      );
    });

    test('an absent or unreadable clock is null, not zero', () {
      // Zero is UTC, which is a real place. Answering "I do not know" with
      // "London" would move an Asia/Dubai venue's whole day by four hours.
      expect(venueOffsetFrom(null), isNull);
      expect(venueOffsetFrom('not a clock'), isNull);
      expect(venueOffsetFrom('25'), isNull);
    });
  });

  group('round trip', () {
    test('a plan survives being written and read back', () {
      final plan = _plan(
        [_block(0, 8 * 60, 12 * 60, 'morning-calm')],
        open: 10 * 60 + 30,
        close: 19 * 60,
      );

      final back = OfflinePlan.fromJson(plan.toJson());

      expect(back.moodAt(_utcFor(0, 9, 0)), 'morning-calm');
      expect(back.closedAt(_utcFor(0, 10, 0)), isTrue);
      expect(back.venueOffsetMinutes, _offset);
      expect(back.lastPlayerInstallationId, 'this-tablet');
    });
  });
}
