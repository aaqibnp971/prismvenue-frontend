// §2 S05 guardrails & settings values, seeded from the Marina Café frames.

/// S05-2 "Floor staff can": View only / [Nudge ±10%] / Full band.
enum FloorLeeway { viewOnly, nudge10, fullBand }

/// S05-3: Seamless (~60s) / [Gentle (~35s)] / Lively (~8s).
enum TransitionSmoothness { seamless, gentle, lively }

/// S05-4 "Who can take over" — gates floor-staff takeover (§4).
enum TakeoverAccess { managers, managersPlusFloor }

class Guardrails {
  const Guardrails({
    this.volumeMin = 26,
    this.volumeMax = 70,
    this.quietHoursOn = true,
    this.quietHoursStartMinutes = 22 * 60,
    this.quietHoursCapPct = 55,
    this.floorLeeway = FloorLeeway.nudge10,
    this.transition = TransitionSmoothness.gentle,
    this.takeoverAccess = TakeoverAccess.managersPlusFloor,
    this.offlineAlertIndex = 1,
    this.takeoverAlertIndex = 1,
  });

  /// S05-2 band: "Quietest it can go" 26% / "Loudest it can go" 70%.
  final int volumeMin;
  final int volumeMax;

  /// S05-2 quiet hours row: "After 10:00 pm · cap at 55%".
  final bool quietHoursOn;

  /// When quiet hours start, minutes past midnight in the VENUE's clock.
  ///
  /// Finding #5: the row rendered "After 10:00 pm · cap at 55%" as a fixed
  /// string — a frame sample value standing in for data the model had no field
  /// for. The columns existed in the database the whole time; nothing carried
  /// them, so the setting could be switched on but never changed, and never
  /// reached the speakers.
  final int quietHoursStartMinutes;

  /// The ceiling quiet hours imposes, 0–100.
  final int quietHoursCapPct;

  /// "10:00 pm", for the settings row. Built here so the row and the value it
  /// describes cannot drift.
  String get quietHoursStartLabel {
    final h24 = quietHoursStartMinutes ~/ 60;
    final m = quietHoursStartMinutes % 60;
    final h = h24 % 12 == 0 ? 12 : h24 % 12;
    return '$h:${m.toString().padLeft(2, '0')} ${h24 < 12 ? 'am' : 'pm'}';
  }

  /// "After 10:00 pm · cap at 55%", or the off state.
  String get quietHoursLabel => quietHoursOn
      ? 'After $quietHoursStartLabel · cap at $quietHoursCapPct%'
      : 'Off';

  final FloorLeeway floorLeeway;
  final TransitionSmoothness transition;
  final TakeoverAccess takeoverAccess;

  /// S05-7 options 2 / 5 / 15 / 30 min (seed default is not pinned).
  final int offlineAlertIndex;
  static const offlineAlertOptions = ['2 min', '5 min', '15 min', '30 min'];

  /// S05-8 options 1h / 2h / 4h / At close (seed default is not pinned).
  final int takeoverAlertIndex;
  static const takeoverAlertOptions = ['1 hour', '2 hours', '4 hours', 'At close'];

  String get bandLabel => '$volumeMin–$volumeMax%';

  /// How long the room takes to move from one vibe to the next — the overlap length the
  /// engine crossfades over. Lives next to [transitionLabel] deliberately: S05-3 publishes
  /// these durations to the manager ("~60s", "~35s", "~8s"), so label and behaviour must
  /// not be able to drift apart.
  Duration get transitionDuration => switch (transition) {
        TransitionSmoothness.seamless => const Duration(seconds: 60),
        TransitionSmoothness.gentle => const Duration(seconds: 35),
        TransitionSmoothness.lively => const Duration(seconds: 8),
      };

  /// Whether the transition waits for the outgoing scene's next loop boundary before it
  /// starts. Musically it is the better answer — the material leaving is never cut
  /// mid-phrase — but the wait is up to one loop period, which is 16 s with the shipped
  /// stems. Inside a 60 s or 35 s blend that is invisible; in front of an 8 s one it reads
  /// as the app ignoring the tap, so Lively trades the alignment for responsiveness.
  bool get transitionAlignsToBar => transition != TransitionSmoothness.lively;

  String get transitionLabel => switch (transition) {
        TransitionSmoothness.seamless => 'Seamless',
        TransitionSmoothness.gentle => 'Gentle',
        TransitionSmoothness.lively => 'Lively',
      };

  String get takeoverAccessLabel => switch (takeoverAccess) {
        TakeoverAccess.managers => 'Manager',
        TakeoverAccess.managersPlusFloor => 'Managers + floor',
      };

  Guardrails copyWith({
    int? volumeMin,
    int? volumeMax,
    bool? quietHoursOn,
    int? quietHoursStartMinutes,
    int? quietHoursCapPct,
    FloorLeeway? floorLeeway,
    TransitionSmoothness? transition,
    TakeoverAccess? takeoverAccess,
    int? offlineAlertIndex,
    int? takeoverAlertIndex,
  }) {
    return Guardrails(
      volumeMin: volumeMin ?? this.volumeMin,
      volumeMax: volumeMax ?? this.volumeMax,
      quietHoursOn: quietHoursOn ?? this.quietHoursOn,
      floorLeeway: floorLeeway ?? this.floorLeeway,
      transition: transition ?? this.transition,
      takeoverAccess: takeoverAccess ?? this.takeoverAccess,
      offlineAlertIndex: offlineAlertIndex ?? this.offlineAlertIndex,
      takeoverAlertIndex: takeoverAlertIndex ?? this.takeoverAlertIndex,
    );
  }
}

/// S05-6/10/11 open hours: one default, only the exceptions stand out.
class HoursException {
  const HoursException({
    this.id,
    required this.days,
    required this.openHour,
    required this.closeHour,
    this.openMinute = 0,
    this.closeMinute = 0,
    this.closedAllDay = false,
    this.everyWeek = true,
  });

  /// Server-assigned; null for one the sheet has just built and not yet saved.
  /// Without this there was no way to address a single exception, which is why
  /// they could only ever be added — never edited or removed
  /// (`open_questions.md` #26).
  final String? id;

  /// 0 = Mon … 6 = Sun.
  final Set<int> days;
  final int openHour;
  final int closeHour;

  /// Minutes past the hour — finding #18. Read with the hour; neither means
  /// anything alone. Defaulted to 0, which is what "7" always meant.
  final int openMinute;
  final int closeMinute;
  final bool closedAllDay;
  final bool everyWeek;

  int get openMinutes => openHour * 60 + openMinute;
  int get closeMinutes => closeHour * 60 + closeMinute;

  static const _dayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String get daysLabel {
    final sorted = days.toList()..sort();
    return sorted.map((d) => _dayNames[d]).join(' & ');
  }
}

class OpenHours {
  const OpenHours({
    this.openHour = 7,
    this.closeHour = 23,
    this.openMinute = 0,
    this.closeMinute = 0,
    this.exceptions = const [],
  });

  final int openHour;
  final int closeHour;

  /// Minutes past the hour — finding #18. A venue opening at 10:30 could not
  /// say so, and rounding either way is wrong: early plays to an empty room,
  /// late leaves the first half hour silent.
  final int openMinute;
  final int closeMinute;
  final List<HoursException> exceptions;

  int get openMinutes => openHour * 60 + openMinute;
  int get closeMinutes => closeHour * 60 + closeMinute;

  /// "7am", "10:30am". Mirrors `hourLabel` in the Deno backend and
  /// `_hour_label` in FastAPI CHARACTER FOR CHARACTER — `hours_label` is
  /// formatted server-side and rendered verbatim, so a difference here shows
  /// up as two spellings of the same venue on two screens.
  ///
  /// ":00" is noise on the hour and the whole point off it, so it appears only
  /// when there is something to say.
  static String timeLabel(int h, [int m = 0]) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    final mm = m == 0 ? '' : ':${m.toString().padLeft(2, '0')}';
    return '$h12$mm${h < 12 ? 'am' : 'pm'}';
  }

  /// Kept for the hour-only callers that have no minute to pass.
  static String hourLabel(int h) => timeLabel(h);

  /// S05-1/S05-6 style "7am–11pm".
  String get rangeLabel =>
      '${timeLabel(openHour, openMinute)}–'
      '${timeLabel(closeHour, closeMinute)}';

  OpenHours copyWith({
    int? openHour,
    int? closeHour,
    int? openMinute,
    int? closeMinute,
    List<HoursException>? exceptions,
  }) {
    return OpenHours(
      openHour: openHour ?? this.openHour,
      closeHour: closeHour ?? this.closeHour,
      openMinute: openMinute ?? this.openMinute,
      closeMinute: closeMinute ?? this.closeMinute,
      exceptions: exceptions ?? this.exceptions,
    );
  }
}
