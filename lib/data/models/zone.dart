/// A zone — one area with its own speakers; Prism drives each on its own
/// (S04-4 helper). Status drives the §2 S04-1/2 row treatment.
enum ZoneStatus {
  /// Quiet row, chevron → zone detail.
  auto,

  /// Amber sub with countdown + "Return to Auto" quick-fix.
  offSchedule,

  /// Red sub, chevron (nothing to fix remotely).
  offline,
}

class Zone {
  const Zone({
    required this.id,
    required this.name,
    required this.status,
    required this.moodId,
    this.statusDetail,
  });

  final String id;
  final String name;
  final ZoneStatus status;

  /// What the zone is playing (or would play on auto).
  final String moodId;

  /// Extra status text, e.g. the off-schedule countdown ("auto in 42 min").
  final String? statusDetail;

  Zone copyWith({String? name, ZoneStatus? status, String? statusDetail}) =>
      Zone(
        id: id,
        name: name ?? this.name,
        status: status ?? this.status,
        moodId: moodId,
        statusDetail:
            status == ZoneStatus.auto ? null : (statusDetail ?? this.statusDetail),
      );
}
