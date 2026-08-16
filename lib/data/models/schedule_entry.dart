/// One row of the Floor schedule rail — §2 S01-1.
class ScheduleEntry {
  const ScheduleEntry({required this.timeLabel, required this.moodId});

  /// Short time label, e.g. "7:00 am". Carries a meridiem because 07:00 and
  /// 19:00 rendered identically without one (the frames' bare "7:00" assumed
  /// a daytime-only schedule).
  final String timeLabel;

  /// References the fixed 6-mood set (theme/moods.dart).
  final String moodId;
}

/// §2 S03-1/2: Prism either self-drives or follows the custom weekly plan.
enum ScheduleMode { selfDrive, custom }

/// One block of the custom weekly plan — §2 S03-2 row: time range 11/700 +
/// mood dot + name.
///
/// The times are the source of truth; [rangeLabel] is derived from them. It
/// used to be the other way round — the sheet's time field was free text and
/// `open_questions.md` #18 flagged that no picker was designed — but a
/// free-text label cannot be scheduled against: the backend could not compute
/// `nowIndex` or decide what actually plays. The sheet now uses the same dial
/// the open-hours flow already had. INTEGRATION_PLAN.md §5.2.
///
/// Minutes are carried alongside the hours rather than replacing them with a
/// single minutes-of-day field. `dayparts.start_local` was always a Postgres
/// `time` and the read path always formatted `h:mm`, so this closes a
/// write-path gap, not a storage one — and the week grid drags in whole hours,
/// which stays a plain integer step with the minutes riding along untouched.
class Daypart {
  const Daypart({
    required this.id,
    required this.dayIndex,
    required this.startHour,
    required this.endHour,
    required this.moodId,
    this.startMinute = 0,
    this.endMinute = 0,
    this.serverRangeLabel,
    this.weekStart,
  });

  final String id;

  /// 0 = Monday … 6 = Sunday.
  final int dayIndex;

  /// 0–23.
  final int startHour;
  final int endHour;

  /// 0–59, past the hour. Defaulted so every existing construction site — the
  /// mocks, the grid's copyWith, a test building a whole-hour block — keeps
  /// meaning exactly what it did.
  final int startMinute;
  final int endMinute;

  final String moodId;

  /// Minutes past midnight. The only comparable form: an hour-only comparison
  /// reads 6:30–7:00 as zero-length and 6:30–6:45 as backwards.
  int get startMinutesOfDay => startHour * 60 + startMinute;
  int get endMinutesOfDay => endHour * 60 + endMinute;

  /// The label as the server rendered it, when it came from the server.
  final String? serverRangeLabel;

  /// Which plan this belongs to: null is the recurring plan every week shows,
  /// a Monday is that week's own fork.
  ///
  /// Never mixed within one week's list — a week is entirely the recurring plan
  /// or entirely a fork, because a fork is a complete copy rather than a diff.
  final DateTime? weekStart;

  /// The display string, e.g. "7 – 11 am". Prefers the server's label so the
  /// app and backend never disagree about how a range reads, and falls back to
  /// the same formatting locally for a row the user just built in the sheet.
  String get rangeLabel =>
      serverRangeLabel ??
      formatRange(startHour, endHour,
          startMinute: startMinute, endMinute: endMinute);

  /// "7 – 11 am" when both ends share a meridiem, "11 am – 2 pm" otherwise;
  /// "7:30 – 11 am" when a side has minutes. Mirrors `range_label()` in the
  /// backend's schedule router character for character — the server's label
  /// wins on every read, so a divergence here shows up as the range changing
  /// the moment a row round-trips.
  static String formatRange(int startHour, int endHour,
      {int startMinute = 0, int endMinute = 0}) {
    String h12(int h, int m) {
      final hour = h % 12 == 0 ? 12 : h % 12;
      return m == 0 ? '$hour' : '$hour:${m.toString().padLeft(2, '0')}';
    }

    String meridiem(int h) => h < 12 ? 'am' : 'pm';
    return meridiem(startHour) == meridiem(endHour)
        ? '${h12(startHour, startMinute)} – '
            '${h12(endHour, endMinute)} ${meridiem(endHour)}'
        : '${h12(startHour, startMinute)} ${meridiem(startHour)} – '
            '${h12(endHour, endMinute)} ${meridiem(endHour)}';
  }

  Daypart copyWith({
    int? dayIndex,
    int? startHour,
    int? endHour,
    int? startMinute,
    int? endMinute,
    String? moodId,
    DateTime? weekStart,
    // Explicit, because null is a meaningful value here: it means "the
    // recurring plan", not "leave it alone". `?? this.weekStart` would make it
    // impossible to move a row back onto the recurring plan.
    bool clearWeekStart = false,
  }) =>
      Daypart(
        id: id,
        dayIndex: dayIndex ?? this.dayIndex,
        startHour: startHour ?? this.startHour,
        endHour: endHour ?? this.endHour,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
        moodId: moodId ?? this.moodId,
        serverRangeLabel: serverRangeLabel,
        weekStart: clearWeekStart ? null : (weekStart ?? this.weekStart),
      );
}

/// Today's schedule as the Floor rail consumes it — S01-1: 5 rows, the
/// current one highlighted, "Auto" chip in the header.
class TodaySchedule {
  const TodaySchedule({
    required this.entries,
    required this.nowIndex,
    required this.auto,
    this.nextIndex = -1,
    this.selfDrive = false,
    this.timezone,
    this.venueTime,
  });

  final List<ScheduleEntry> entries;

  /// Index of the daypart underway right now, or **-1** when the plan has
  /// nothing for this moment — before the first of the day, after the last, or
  /// in a gap between two.
  ///
  /// Server-computed with the same predicate as `app.scheduled_mood_for`, so
  /// the rail cannot claim a mood the executor is not playing. It used to be
  /// "the last daypart that started, else 0", which marked a row NOW hours
  /// before it began and kept marking one hours after it ended.
  final int nowIndex;

  /// True when nothing in the plan covers this moment. Auto can be on and this
  /// still be true: the room simply holds whatever it was playing until the
  /// next daypart begins (migration 010 deliberately does not snap it to
  /// silence or to a default).
  bool get nothingScheduledNow => nowIndex < 0;

  /// First daypart still to come, or -1 when the day is done.
  ///
  /// Cannot be derived from [nowIndex]. With nothing underway the first row of
  /// the day is not necessarily the next one — the earlier ones may simply have
  /// ended, which is what a rail showing "up next" against a finished 8:00
  /// block was getting wrong.
  final int nextIndex;

  /// Rail header chip ("Auto") — Prism driving on schedule.
  final bool auto;

  /// The venue's IANA zone, and its wall clock as "HH:MM" when the server read
  /// it. Both null until the fetch lands, and left null rather than filled with
  /// the device's own clock — showing the wrong one confidently is the whole
  /// bug this exists to prevent.
  ///
  /// Carried on the rail rather than on the venue row because this response
  /// already refreshes every 30s, and a clock is the one value where being
  /// minutes stale defeats the point of showing it.
  final String? timezone;
  final String? venueTime;

  /// True when Prism picks the vibe itself (S03-1) and the saved plan is not
  /// running. [entries] then describes a plan that is not in charge, so the
  /// rail shows the self-drive state instead of a highlighted "NOW" row that
  /// nothing is following.
  final bool selfDrive;
}
