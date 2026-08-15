/// One IANA zone the server offered, for the S05 picker.
class TimezoneOption {
  const TimezoneOption({required this.name, required this.utcOffsetMinutes});

  /// e.g. "Asia/Kolkata".
  final String name;

  /// Minutes east of UTC right now.
  final int utcOffsetMinutes;

  /// "GMT+5:30" / "GMT−4" / "GMT". Rendered beside the name so two similar
  /// cities can be told apart without opening a map.
  String get offsetLabel {
    if (utcOffsetMinutes == 0) return 'GMT';
    final sign = utcOffsetMinutes < 0 ? '−' : '+'; // U+2212, not a hyphen
    final total = utcOffsetMinutes.abs();
    final hours = total ~/ 60;
    final minutes = total % 60;
    return minutes == 0
        ? 'GMT$sign$hours'
        : 'GMT$sign$hours:${minutes.toString().padLeft(2, '0')}';
  }

  /// "Asia/Kolkata" → "Kolkata", for the row's headline.
  String get city => name.split('/').last.replaceAll('_', ' ');

  /// "Asia/Kolkata" → "Asia", for the row's subtitle.
  String get region => name.split('/').first.replaceAll('_', ' ');
}

/// What the device observes, and the only clock reading the app sends.
///
/// Two offsets rather than one because a single one cannot tell a zone that
/// observes DST from one that does not: +0 in January is London and Abidjan
/// both, and they diverge in July. The pair pins the behaviour, which is all
/// scheduling cares about.
///
/// Read from `DateTime`, never from a table the app carries — Dart cannot give
/// an IANA name (`timeZoneName` is an abbreviation, or a Windows zone title),
/// so the server resolves the pair against the tz database instead.
class DeviceOffsets {
  const DeviceOffsets({required this.januaryMinutes, required this.julyMinutes});

  /// Reads this machine's own clock. Mid-month so a DST changeover, which
  /// happens at the edges, cannot land on the sample.
  factory DeviceOffsets.fromDevice([DateTime? now]) {
    final year = (now ?? DateTime.now()).year;
    return DeviceOffsets(
      januaryMinutes: DateTime(year, 1, 15).timeZoneOffset.inMinutes,
      julyMinutes: DateTime(year, 7, 15).timeZoneOffset.inMinutes,
    );
  }

  final int januaryMinutes;
  final int julyMinutes;

  /// What this machine's clock is offset by *right now*, which is what decides
  /// whether a venue's wall clock matches the one the manager is reading.
  static int currentMinutes([DateTime? now]) =>
      (now ?? DateTime.now()).timeZoneOffset.inMinutes;

  /// "HH:MM" on this device, for comparing against the venue's own wall clock.
  /// A string rather than an offset because that is the shape the server sends
  /// back, and comparing the two answers the only question worth asking: does
  /// this venue's clock read the same as mine?
  static String currentClock([DateTime? now]) {
    final t = now ?? DateTime.now();
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
  }

  Map<String, dynamic> toJson() => {
        'january_minutes': januaryMinutes,
        'july_minutes': julyMinutes,
      };
}
