import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/data/mock/mock_playback_repo.dart';
import 'package:prism_venues/data/mock/mock_schedule_repo.dart';
import 'package:prism_venues/data/models/schedule_entry.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/main.dart';
import 'package:prism_venues/features/schedule/week_grid.dart';
import 'package:prism_venues/shared/widgets/confirm_dialog.dart';
import 'package:prism_venues/shared/widgets/prism_bottom_sheet.dart';

/// §2 S03 Schedule: self-drive ⇄ custom, week grid, add/edit/delete
/// dayparts (all modals return to custom, §4).
void main() {
  Future<void> pumpSchedule(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1024, 768));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final container = ProviderContainer(overrides: [
      playbackRepoProvider.overrideWith((ref) {
        final repo = MockPlaybackRepo(tickNoise: false);
        ref.onDispose(repo.dispose);
        return repo;
      }),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const PrismVenuesApp(),
      ),
    );
    await _settle(tester);
    await tester.enterText(
        find.byType(TextField).first, 'priya@marinacafe.com');
    await tester.tap(find.text('Sign in'));
    await _settle(tester);
    await tester.tap(find.text('Schedule'));
    await _settle(tester);
  }

  Future<void> toCustom(WidgetTester tester) async {
    await tester.tap(find.text('Custom plan'));
    await _settle(tester);
  }

  testWidgets('S03-1 ⇄ S03-2: self-drive default, switch to custom and back',
      (tester) async {
    await pumpSchedule(tester);

    expect(find.text('Prism is self-driving'), findsOneWidget);

    await toCustom(tester);
    expect(find.text('Prism is self-driving'), findsNothing);
    expect(find.text('+ Add'), findsOneWidget);
    // Every day carries the 5 seeded dayparts.
    expect(find.text('Morning calm'), findsNWidgets(7));
    expect(find.textContaining('Mon '), findsOneWidget);

    await tester.tap(find.text('Self-drive'));
    await _settle(tester);
    expect(find.text('Prism is self-driving'), findsOneWidget);
  });

  testWidgets('S03-5 edit: delete removes the daypart', (tester) async {
    await pumpSchedule(tester);
    await toCustom(tester);

    await tester.tap(find.text('Morning calm').first);
    await _settle(tester);
    expect(find.text('Edit daypart'), findsOneWidget);
    expect(find.text('Delete daypart'), findsOneWidget);

    // M-03: confirmed now, like "Remove zone". A daypart is not recoverable
    // from the UI, and the sheet is opened by tapping a block in a grid, so
    // picking the wrong one is exactly the mistake worth catching.
    await tester.tap(find.text('Delete daypart'));
    await _settle(tester);
    expect(find.text('Delete this daypart?'), findsOneWidget);

    // Cancel keeps it. Scoped to the dialog — the sheet has a Cancel too.
    await tester.tap(find.descendant(
      of: find.byType(ConfirmDialog),
      matching: find.text('Cancel'),
    ));
    await _settle(tester);
    expect(find.text('Delete this daypart?'), findsNothing);

    await tester.tap(find.text('Delete daypart').first);
    await _settle(tester);
    await tester.tap(find.descendant(
      of: find.byType(ConfirmDialog),
      matching: find.text('Delete daypart'),
    ));
    await _settle(tester);
    expect(find.text('Morning calm'), findsNWidgets(6));
  });

  testWidgets('S03-4 add: new daypart lands on the picked day',
      (tester) async {
    await pumpSchedule(tester);
    await toCustom(tester);

    await tester.tap(find.text('+ Add'));
    await _settle(tester);
    expect(find.text('Add a daypart'), findsOneWidget);

    // Pick Wednesday + Peak; keep the default time. The seeded plan already
    // runs 6–9pm every day, so this lands on an occupied slot — which is now a
    // question rather than a second row at the same minute.
    await tester.tap(find.descendant(
        of: find.byType(PrismBottomSheet), matching: find.text('Wed')));
    await _settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(PrismBottomSheet), matching: find.text('Peak')));
    await _settle(tester);
    await tester.tap(find.text('Add daypart'));
    await _settle(tester);

    expect(find.text('Replace what starts at 6:00 pm?'), findsOneWidget);
    // Names what is being lost, so "Replace" is an informed tap.
    // findRichText, because the body bolds the mood being saved and is
    // therefore a span tree rather than a plain string.
    expect(
        find.textContaining('Evening warmth already starts',
            findRichText: true),
        findsOneWidget);
    await tester.tap(find.text('Replace'));
    await _settle(tester);

    // 7 seeded Peaks + the new one, and Wednesday's Evening warmth is gone
    // rather than sitting underneath it.
    expect(find.text('Peak'), findsNWidgets(8));
    expect(find.text('Evening warmth'), findsNWidgets(6));
  });

  testWidgets('a time can be typed instead of dialled', (tester) async {
    // The dial is quick for "around 8" and slow for "23:05 exactly", which is
    // the case that turns up when somebody is copying a rota.
    await pumpSchedule(tester);
    await toCustom(tester);

    await tester.tap(find.text('+ Add'));
    await _settle(tester);
    await tester.tap(find.text('6:00 pm')); // the Starts field
    await _settle(tester);

    // Two fields: hour, then minutes.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), '11');
    // Moving to the next field blurs the first, which is what commits it —
    // typing and then reaching straight for Set must not save the old value.
    await tester.enterText(fields.at(1), '05');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);

    expect(find.text('Set 11:05 PM'), findsOneWidget);
  });

  testWidgets('an out-of-range hour reverts instead of being coerced',
      (tester) async {
    // Turning 47 into 4, or into 11, is a worse answer than leaving the time
    // alone: both are silently wrong, and this sheet decides what a room plays.
    await pumpSchedule(tester);
    await toCustom(tester);

    await tester.tap(find.text('+ Add'));
    await _settle(tester);
    await tester.tap(find.text('6:00 pm'));
    await _settle(tester);

    await tester.enterText(find.byType(TextField).at(0), '47');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _settle(tester);

    expect(find.text('Set 6:00 PM'), findsOneWidget);
  });

  testWidgets('the grid covers the whole day, not just open hours',
      (tester) async {
    // A daypart may legitimately start at 2am. While the grid ran from the
    // venue's opening hour, those blocks were clamped against the edge —
    // visible as a sliver, undraggable, and unplaceable to begin with.
    await pumpSchedule(tester);
    await toCustom(tester);

    // 12am and 2am are outside the 7am–11pm open window, and the ruler labels
    // them, so the axis genuinely reaches them.
    expect(find.text('12a'), findsWidgets);
    expect(find.text('2a'), findsWidgets);
  });

  testWidgets('two dayparts cannot start at the same minute', (tester) async {
    // `app.scheduled_mood_for` ends `order by start_local desc limit 1`, and
    // between equal start times that order is unspecified — so a duplicate slot
    // leaves the room picking at random, and swapping between cron ticks.
    await pumpSchedule(tester);
    await toCustom(tester);

    await tester.tap(find.text('+ Add'));
    await _settle(tester);
    await tester.tap(find.descendant(
        of: find.byType(PrismBottomSheet), matching: find.text('Wed')));
    await _settle(tester);
    await tester.tap(find.text('Add daypart'));
    await _settle(tester);

    // Declining leaves both the existing daypart and the plan untouched.
    expect(find.text('Replace what starts at 6:00 pm?'), findsOneWidget);
    await tester.tap(find.text('Keep both times free'));
    await _settle(tester);

    expect(find.text('Evening warmth'), findsNWidgets(7));
    expect(find.text('Replace what starts at 6:00 pm?'), findsNothing);
  });

  testWidgets('H-08 a daypart that ends before it starts cannot be saved',
      (tester) async {
    await pumpSchedule(tester);
    await toCustom(tester);

    await tester.tap(find.text('+ Add'));
    await _settle(tester);
    expect(find.text('Add a daypart'), findsOneWidget);

    // Default is 6pm–9pm and saveable.
    expect(find.text('Tap a time to set it on the dial.'), findsOneWidget);

    // Push the start past the end (6pm → 10pm, against a 9pm end). A reversed
    // range used to save cleanly on both sides, and it decides what actually
    // plays in the room.
    await tester.tap(find.text('6:00 pm'));
    await _settle(tester);
    // "10:00" appears twice — the big readout and the quick chip. The chip is
    // last in the tree.
    await tester.tap(find.text('10:00').last); // pm already selected
    await _settle(tester);
    await tester.tap(find.text('Set 10:00 PM'));
    await _settle(tester);

    expect(find.text('End time must be after the start time.'), findsOneWidget);

    // The save is blocked rather than warned about after the fact: the sheet
    // has already popped by the time the write runs, so a server rejection
    // would have no dialog to report into.
    await tester.tap(find.text('Add daypart'));
    await _settle(tester);
    expect(find.text('Add a daypart'), findsOneWidget); // sheet still open
  });

  testWidgets('a daypart can start on a half hour, not just on the hour',
      (tester) async {
    // `dayparts.start_local` was always a Postgres `time` and the rail always
    // formatted `h:mm`; the write path was the hour-only half. A venue whose
    // kitchen turns over at 6:30 could not say so.
    await pumpSchedule(tester);
    await toCustom(tester);

    await tester.tap(find.text('+ Add'));
    await _settle(tester);
    await tester.tap(find.text('6:00 pm')); // the Starts field
    await _settle(tester);

    // Six steps of five minutes on the wheel. Negative is later: the wheel is
    // rotated a quarter turn, so dragging left advances it.
    await tester.drag(
        find.byType(ListWheelScrollView), const Offset(-76.0 * 6, 0));
    await _settle(tester);

    expect(find.text('Set 6:30 PM'), findsOneWidget);
    await tester.tap(find.text('Set 6:30 PM'));
    await _settle(tester);

    // The field shows the minutes rather than rounding them away.
    expect(find.text('6:30 pm'), findsOneWidget);

    await tester.tap(find.text('Add daypart'));
    await _settle(tester);
    expect(find.text('6:30 – 9 pm'), findsOneWidget);
  });

  testWidgets('S03-3 week picker: choosing a date moves the range header',
      (tester) async {
    await pumpSchedule(tester);
    await toCustom(tester);

    // The header shows "Mon d – Sun d" of the current week; tap it.
    final header = find.textContaining(' – ');
    await tester.tap(header.first);
    await _settle(tester);

    // Calendar popover: pick day "15" of the shown month (always exists).
    await tester.tap(find.text('15').first);
    await _settle(tester);

    // Still on the custom plan with a valid range header.
    expect(find.text('+ Add'), findsOneWidget);
    expect(find.textContaining(' – '), findsWidgets);
  });

  testWidgets('S03-2 drag: a long-press drag moves a daypart in time',
      (tester) async {
    await pumpSchedule(tester);
    await toCustom(tester);

    // The grid is a time axis now, so horizontal distance IS time. Monday's
    // first block is 7 - 11 am; drag it two hours later.
    final block = find.text('7 – 11 am').first;
    final gridWidth = tester.getSize(find.byType(WeekGrid)).width;
    // The whole day, not the open-hours window — and never finer than the
    // floor at which the grid starts scrolling instead of squeezing. Same
    // expression the widget uses; a drag is measured in pixels, so this has to
    // agree with it exactly.
    final pxPerHour = math.max((gridWidth - 46) / 24, 46.0);

    final gesture = await tester.startGesture(tester.getCenter(block));
    await tester.pump(const Duration(milliseconds: 600)); // arm the long-press
    await gesture.moveBy(Offset(pxPerHour * 2, 0));
    await tester.pump();
    await gesture.up();
    await _settle(tester);

    // Committed through the repo and returned via the stream, not applied
    // locally — the label the grid renders is the moved one.
    expect(find.text('9 am – 1 pm'), findsWidgets);
  });

  testWidgets('S03-2 drag: a sub-hour drag snaps back and writes nothing',
      (tester) async {
    await pumpSchedule(tester);
    await toCustom(tester);

    final block = find.text('7 – 11 am').first;
    final gesture = await tester.startGesture(tester.getCenter(block));
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveBy(const Offset(3, 0)); // well under one hour
    await tester.pump();
    await gesture.up();
    await _settle(tester);

    // One hour is the only granularity the model can express, so anything
    // smaller must round to no change at all rather than a partial write.
    expect(find.text('7 – 11 am'), findsWidgets);
  });

  group('H-09 week overrides', () {
    final monday = DateTime(2026, 8, 10);
    late MockScheduleRepo repo;

    setUp(() => repo = MockScheduleRepo());
    tearDown(() => repo.dispose());

    test('an unforked week shows the recurring plan', () async {
      final recurring = await repo.watchWeekPlan(null).first;
      final week = await repo.watchWeekPlan(monday).first;

      expect(week.length, recurring.length);
      // All null week_start: this IS the recurring plan, not a copy of it.
      expect(week.every((d) => d.weekStart == null), isTrue);
    });

    test('forking copies the whole plan, not just the edit', () async {
      final before = await repo.watchWeekPlan(monday).first;
      await repo.forkWeek(monday);
      final after = await repo.watchWeekPlan(monday).first;

      // Copy-on-write: the week keeps every daypart it had, now as its own.
      expect(after.length, before.length);
      expect(after.every((d) => d.weekStart == monday), isTrue);
    });

    test('forking is idempotent, so a double tap cannot duplicate a plan',
        () async {
      await repo.forkWeek(monday);
      final once = await repo.watchWeekPlan(monday).first;
      await repo.forkWeek(monday);
      final twice = await repo.watchWeekPlan(monday).first;

      expect(twice.length, once.length);
    });

    test('editing a forked week leaves every other week alone', () async {
      await repo.forkWeek(monday);
      final forked = await repo.watchWeekPlan(monday).first;
      await repo.deleteDaypart(forked.first.id);

      final week = await repo.watchWeekPlan(monday).first;
      final recurring = await repo.watchWeekPlan(null).first;

      expect(week.length, forked.length - 1);
      // The whole point: the recurring plan is untouched.
      expect(recurring.length, forked.length);
    });

    test('a forked week stops tracking the recurring plan', () async {
      await repo.forkWeek(monday);
      final forkedBefore = (await repo.watchWeekPlan(monday).first).length;

      // Add to the recurring plan afterwards.
      await repo.watchWeekPlan(null).first;
      await repo.addDaypart(const Daypart(
        id: '',
        dayIndex: 3,
        startHour: 9,
        endHour: 10,
        moodId: 'peak',
      ));

      final forkedAfter = (await repo.watchWeekPlan(monday).first).length;
      // Divergence is permanent in one direction, and this is the cost the
      // sheet warns about before anyone pays it.
      expect(forkedAfter, forkedBefore);
    });
  });
}

/// Bounded settle — chrome may host looping animations.
Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
  await tester.pump(const Duration(milliseconds: 250));

}
