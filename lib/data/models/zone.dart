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
    this.lastSeenAt,
  });

  final String id;
  final String name;
  final ZoneStatus status;

  /// What the zone is playing (or would play on auto).
  final String moodId;

  /// Extra status text, e.g. the off-schedule countdown ("auto in 42 min").
  final String? statusDetail;

  /// When a device last reported on this zone, or null if none ever has.
  ///
  /// A timestamp, not a phrase: "12 minutes ago" is only true at the moment it
  /// is written, and this row can sit on screen for a whole shift. See
  /// [lastSeenLabel], which is applied at build time against the reader's own
  /// clock.
  final DateTime? lastSeenAt;

  Zone copyWith({String? name, ZoneStatus? status, String? statusDetail}) =>
      Zone(
        id: id,
        name: name ?? this.name,
        status: status ?? this.status,
        moodId: moodId,
        statusDetail:
            status == ZoneStatus.auto ? null : (statusDetail ?? this.statusDetail),
        lastSeenAt: lastSeenAt,
      );
}

/// "4 minutes ago", or null when nothing has ever reported.
///
/// Finding #16: a row that says only "Offline" cannot tell an owner whether it
/// has been five minutes or five days, which is the difference between "the
/// Wi-Fi blipped" and "nobody has switched that tablet on since we installed
/// it". Null is deliberately NOT rendered as a time — "never" is a setup
/// problem, and saying so is more use than saying nothing.
///
/// Coarse on purpose. The exact second is noise to somebody deciding whether
/// to walk to the other end of a building.
String? lastSeenLabel(DateTime? at, {DateTime? now}) {
  if (at == null) return null;
  final elapsed = (now ?? DateTime.now()).difference(at);
  if (elapsed.isNegative || elapsed.inSeconds < 45) return 'just now';
  if (elapsed.inMinutes < 60) {
    final m = elapsed.inMinutes;
    return '$m ${m == 1 ? 'minute' : 'minutes'} ago';
  }
  if (elapsed.inHours < 24) {
    final h = elapsed.inHours;
    return '$h ${h == 1 ? 'hour' : 'hours'} ago';
  }
  final d = elapsed.inDays;
  return '$d ${d == 1 ? 'day' : 'days'} ago';
}
