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
/// [startHour]/[endHour] are the source of truth; [rangeLabel] is derived from
/// them. It used to be the other way round — the sheet's time field was free
/// text and `open_questions.md` #18 flagged that no picker was designed — but a
/// free-text label cannot be scheduled against: the backend could not compute
/// `nowIndex` or decide what actually plays. The sheet now uses the same hour
/// dial the open-hours flow already had. INTEGRATION_PLAN.md §5.2.
class Daypart {
  const Daypart({
    required this.id,
    required this.dayIndex,
    required this.startHour,
    required this.endHour,
    required this.moodId,
    this.serverRangeLabel,
    this.weekStart,
  });

  final String id;

  /// 0 = Monday … 6 = Sunday.
  final int dayIndex;

  /// 0–23, matching the hour dial's granularity.
  final int startHour;
  final int endHour;

  final String moodId;

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
  String get rangeLabel => serverRangeLabel ?? formatRange(startHour, endHour);

  /// "7 – 11 am" when both ends share a meridiem, "11 am – 2 pm" otherwise.
  /// Mirrors `range_label()` in the backend's schedule router.
  static String formatRange(int startHour, int endHour) {
    String h12(int h) => '${h % 12 == 0 ? 12 : h % 12}';
    String meridiem(int h) => h < 12 ? 'am' : 'pm';
    return meridiem(startHour) == meridiem(endHour)
        ? '${h12(startHour)} – ${h12(endHour)} ${meridiem(endHour)}'
        : '${h12(startHour)} ${meridiem(startHour)} – '
            '${h12(endHour)} ${meridiem(endHour)}';
  }

  Daypart copyWith({
    int? dayIndex,
    int? startHour,
    int? endHour,
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
    this.selfDrive = false,
  });

  final List<ScheduleEntry> entries;
  final int nowIndex;

  /// Rail header chip ("Auto") — Prism driving on schedule.
  final bool auto;

  /// True when Prism picks the vibe itself (S03-1) and the saved plan is not
  /// running. [entries] then describes a plan that is not in charge, so the
  /// rail shows the self-drive state instead of a highlighted "NOW" row that
  /// nothing is following.
  final bool selfDrive;
}
