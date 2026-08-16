import '../models/timezone.dart';
import '../models/venue.dart';
import '../models/zone.dart';
import '../repositories/venue_repo.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'api_scope.dart';
import 'watchable.dart';

/// `VenueRepo` against the real API.
///
/// Two behaviours worth naming:
///
/// **Sorting stays here, not on the server.** The mock sorts the portfolio
/// "needs attention first" (offline → off-schedule → quiet) inside the
/// repository, and S04-2's whole triage treatment depends on that order. Doing
/// it client-side keeps the API and the mock rendering identically. The
/// contract recommends moving it server-side once a portfolio outgrows a
/// handful of venues — at which point this sort becomes a no-op rather than a
/// conflict, because it is order-preserving for already-sorted input.
///
/// **The list and the single-venue view refresh together.** `venue_screen` and
/// `portfolio_screen` can be showing the same zone; a quick-fix on one must
/// move the other. Every mutation refreshes both.
///
/// **Everything here is keyed to the account.** This is the one repository
/// whose data is scoped to the signed-in user rather than to a room, so it is
/// also the one where a bare cache outlives its session: sign out, sign in as
/// somebody else, and the portfolio kept serving the previous account's venues
/// until a mutation happened to call `refresh()`. `ApiScope.accountKey` is what
/// makes the cache drop on a sign-in instead.
class ApiVenueRepo implements VenueRepo {
  ApiVenueRepo(this._client, this._scope);

  final ApiClient _client;
  final ApiScope _scope;

  late final _venues =
      Watchable<List<Venue>>(_fetchVenues, scopeKey: _scope.accountKey);

  /// One per venue id the app has actually looked at. Kept so a mutation can
  /// push to every live drill-in view, not just the portfolio.
  ///
  /// Entries survive a sign-out, and may: each carries the same account key, so
  /// a venue id that somehow recurs across accounts refetches rather than
  /// serving the wrong tenant's row.
  final _byId = <String, Watchable<Venue?>>{};

  @override
  Stream<List<Venue>> watchVenues() => _venues.watch();

  @override
  Stream<Venue?> watchVenue(String id) => _watchableFor(id).watch();

  Watchable<Venue?> _watchableFor(String id) => _byId.putIfAbsent(
        id,
        () => Watchable<Venue?>(() => _fetchVenue(id),
            scopeKey: _scope.accountKey),
      );

  @override
  Future<void> returnZoneToAuto(String venueId, String zoneId) async {
    // The endpoint is zone-scoped; venueId is part of the Dart signature only.
    await _client.post('/zones/$zoneId/return-to-auto');
    await _refreshAll();
  }

  @override
  Future<void> addVenue({
    required String name,
    required String address,
    required List<String> zoneNames,
    String? timezone,
    DeviceOffsets? deviceOffsets,
  }) async {
    await _client.post('/venues', body: {
      'name': name,
      'address': address,
      'zone_names': zoneNames,
      // Omitted rather than null when unset, so the server's "resolve the
      // device's offsets instead" branch is the one that runs.
      'timezone': ?timezone,
      // Omitted rather than null-filled when absent, so the server's "no
      // reading, leave the column default" branch is the one that runs.
      if (deviceOffsets != null) 'device_offsets': deviceOffsets.toJson(),
    });
    await _refreshAll();
  }

  @override
  Future<List<TimezoneOption>> listTimezones() async {
    final json = await _client.get('/timezones') as Map<String, dynamic>;
    return [
      for (final t in (json['timezones'] as List? ?? const []))
        TimezoneOption(
          name: (t as Map<String, dynamic>)['name'] as String,
          utcOffsetMinutes: t['utc_offset_minutes'] as int? ?? 0,
        ),
    ];
  }

  @override
  Future<void> setTimezone(String venueId, String timezone) async {
    await _client.patch('/venues/$venueId', body: {'timezone': timezone});
    // Every daypart's "is it now" answer moves with this, so the schedule
    // streams are as stale as the venue rows are.
    await _refreshAll();
  }

  @override
  Future<void> addZone(String venueId, String name) async {
    await _client.post('/venues/$venueId/zones', body: {'name': name});
    await _refreshAll();
  }

  @override
  Future<void> renameZone(String zoneId, String name) async {
    await _client.patch('/zones/$zoneId', body: {'name': name});
    await _refreshAll();
  }

  @override
  Future<void> removeZone(String zoneId) async {
    await _client.delete('/zones/$zoneId');
    await _refreshAll();
  }

  /// Refreshes the portfolio and every drill-in view that has been opened.
  ///
  /// A 404 on a single venue is expected here, not exceptional: the venue may
  /// have been archived by the very mutation that triggered this. Failing the
  /// whole refresh for it would leave the portfolio stale too.
  Future<void> _refreshAll() async {
    await _venues.refresh();
    await Future.wait([
      for (final watchable in _byId.values)
        watchable.refresh().catchError((_) {}),
    ]);
  }

  Future<List<Venue>> _fetchVenues() async {
    final json = await _client.get('/venues') as List;
    final venues = [
      for (final raw in json) _venueFrom((raw as Map).cast<String, dynamic>()),
    ];
    return _needsAttentionFirst(venues);
  }

  Future<Venue?> _fetchVenue(String id) async {
    try {
      final json = await _client.get('/venues/$id') as Map<String, dynamic>;
      return _venueFrom(json);
    } on ApiException catch (e) {
      // The screen renders `Venue?` = null for an unknown id. 404 also covers
      // "exists but not yours" — the server deliberately does not distinguish.
      if (e.isNotFound) return null;
      rethrow;
    }
  }

  /// S04-2 "Needs attention": offline first, then off-schedule, then quiet.
  static List<Venue> _needsAttentionFirst(List<Venue> venues) {
    int rank(Venue v) => switch (v.worstStatus) {
          ZoneStatus.offline => 0,
          ZoneStatus.offSchedule => 1,
          ZoneStatus.auto => 2,
        };
    final sorted = List.of(venues)
      ..sort((a, b) => rank(a).compareTo(rank(b)));
    return List.unmodifiable(sorted);
  }

  static Venue _venueFrom(Map<String, dynamic> json) => Venue(
        id: json['id'] as String,
        name: json['name'] as String,
        address: json['address'] as String?,
        hoursLabel: json['hours_label'] as String? ?? 'Every day · 7am–11pm',
        // Null rather than a stand-in when absent. Rendering a confident zone
        // the server did not send is exactly how this went unnoticed.
        timezone: json['timezone'] as String?,
        localTime: json['local_time'] as String?,
        zones: [
          for (final raw in (json['zones'] as List? ?? const []))
            _zoneFrom((raw as Map).cast<String, dynamic>()),
        ],
      );

  static Zone _zoneFrom(Map<String, dynamic> json) => Zone(
        id: json['id'] as String,
        name: json['name'] as String,
        status: switch (json['status'] as String?) {
          'offline' => ZoneStatus.offline,
          'off_schedule' => ZoneStatus.offSchedule,
          // An unrecognised status must not read as a problem that isn't there.
          _ => ZoneStatus.auto,
        },
        moodId: json['mood_id'] as String? ?? 'daytime-flow',
        statusDetail: json['status_detail'] as String?,
      );

  void dispose() {
    _venues.dispose();
    for (final watchable in _byId.values) {
      watchable.dispose();
    }
  }
}
