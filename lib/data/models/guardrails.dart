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
  final bool closedAllDay;
  final bool everyWeek;

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
    this.exceptions = const [],
  });

  final int openHour;
  final int closeHour;
  final List<HoursException> exceptions;

  static String hourLabel(int h) {
    final h12 = h % 12 == 0 ? 12 : h % 12;
    return '$h12${h < 12 ? 'am' : 'pm'}';
  }

  /// S05-1/S05-6 style "7am–11pm".
  String get rangeLabel => '${hourLabel(openHour)}–${hourLabel(closeHour)}';

  OpenHours copyWith({
    int? openHour,
    int? closeHour,
    List<HoursException>? exceptions,
  }) {
    return OpenHours(
      openHour: openHour ?? this.openHour,
      closeHour: closeHour ?? this.closeHour,
      exceptions: exceptions ?? this.exceptions,
    );
  }
}
