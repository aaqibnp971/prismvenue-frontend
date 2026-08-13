/// Which venue and zone this session operates on.
///
/// The app has no zone picker: `PlaybackRepo.watchNowPlaying()`,
/// `SettingsRepo.watchGuardrails()` and friends take no arguments, while every
/// backend endpoint is `/v1/zones/{id}/…`. Something has to supply that id.
///
/// The confirmed resolution (INTEGRATION_PLAN.md §4.1) was a client-held
/// current zone, seeded by the server at sign-in. That keeps every repository
/// signature and every widget test unchanged, while giving the app a real
/// notion of "the zone I am looking at" for a future picker to set.
class SessionContext {
  const SessionContext({
    required this.venueId,
    required this.venueName,
    this.zoneId,
    this.zoneName,
  });

  final String venueId;
  final String venueName;

  /// Null only for a venue with no zones — possible after the last zone is
  /// removed (S05-5). Screens that need a zone must handle it.
  final String? zoneId;
  final String? zoneName;

  SessionContext copyWith({String? zoneId, String? zoneName}) => SessionContext(
        venueId: venueId,
        venueName: venueName,
        zoneId: zoneId ?? this.zoneId,
        zoneName: zoneName ?? this.zoneName,
      );

  static SessionContext fromJson(Map<String, dynamic> json) => SessionContext(
        venueId: json['venue_id'] as String? ?? '',
        venueName: json['venue_name'] as String? ?? '',
        zoneId: json['zone_id'] as String?,
        zoneName: json['zone_name'] as String?,
      );

  /// Same keys as [fromJson], so what is persisted locally and what the server
  /// sends at sign-in are one shape rather than two that must be kept in step.
  Map<String, dynamic> toJson() => {
        'venue_id': venueId,
        'venue_name': venueName,
        'zone_id': zoneId,
        'zone_name': zoneName,
      };
}
