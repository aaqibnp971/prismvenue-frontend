import 'dart:async';

import '../api/api_exception.dart';
import '../models/venue.dart';
import '../models/zone.dart';
import '../repositories/venue_repo.dart';

/// Estate seed. Marina Café (the signed-in venue, 2 zones per S05-1
/// "Zones & open hours: 2") plus portfolio companions so S04-2 shows the
/// full triage range: red (offline), amber (off-schedule + countdown +
/// quick-fix) and quiet healthy rows. Names/statuses beyond Marina Café are
/// invented seed data (open_questions).
class MockVenueRepo implements VenueRepo {
  final List<Venue> _venues = [
    const Venue(
      id: 'dockside',
      name: 'Dockside',
      address: 'Pier 4, Harbour Walk',
      zones: [
        Zone(
          id: 'bar',
          name: 'Bar',
          status: ZoneStatus.offline,
          moodId: 'peak',
          statusDetail: 'Offline',
        ),
      ],
    ),
    const Venue(
      id: 'marina-cafe',
      name: 'Marina Café',
      address: '12 Marina Promenade',
      zones: [
        Zone(
          id: 'main-floor',
          name: 'Main floor',
          status: ZoneStatus.auto,
          moodId: 'afternoon-lift',
        ),
        Zone(
          id: 'terrace',
          name: 'Terrace',
          status: ZoneStatus.offSchedule,
          moodId: 'evening-warmth',
          statusDetail: 'Off schedule · auto in 42 min',
        ),
      ],
    ),
    const Venue(
      id: 'harbor-house',
      name: 'Harbor House',
      address: '3 Quayside Lane',
      zones: [
        Zone(
          id: 'dining',
          name: 'Dining room',
          status: ZoneStatus.auto,
          moodId: 'peak',
        ),
      ],
    ),
  ];
  var _nextId = 0;

  final _controller = StreamController<List<Venue>>.broadcast();

  /// S04-2 sort "Needs attention": offline first, then off-schedule, then
  /// quiet.
  List<Venue> get _sorted {
    int rank(Venue v) => switch (v.worstStatus) {
          ZoneStatus.offline => 0,
          ZoneStatus.offSchedule => 1,
          ZoneStatus.auto => 2,
        };
    final list = List.of(_venues)..sort((a, b) => rank(a).compareTo(rank(b)));
    return List.unmodifiable(list);
  }

  @override
  Stream<List<Venue>> watchVenues() async* {
    yield _sorted;
    yield* _controller.stream;
  }

  @override
  Stream<Venue?> watchVenue(String id) async* {
    Venue? find(List<Venue> vs) =>
        vs.where((v) => v.id == id).firstOrNull;
    yield find(_venues);
    yield* _controller.stream.map(find);
  }

  void _emit() => _controller.add(_sorted);

  @override
  Future<void> returnZoneToAuto(String venueId, String zoneId) async {
    final vi = _venues.indexWhere((v) => v.id == venueId);
    if (vi == -1) return;
    _venues[vi] = _venues[vi].copyWith(zones: [
      for (final z in _venues[vi].zones)
        if (z.id == zoneId && z.status == ZoneStatus.offSchedule)
          z.copyWith(status: ZoneStatus.auto)
        else
          z,
    ]);
    _emit();
  }

  @override
  Future<void> addVenue({
    required String name,
    required String address,
    required List<String> zoneNames,
  }) async {
    final id = 'venue-${_nextId++}';
    _venues.add(Venue(
      id: id,
      name: name,
      address: address,
      zones: [
        for (final (i, zoneName) in zoneNames.indexed)
          Zone(
            id: '$id-z$i',
            name: zoneName,
            status: ZoneStatus.auto,
            moodId: 'daytime-flow',
          ),
      ],
    ));
    _emit();
  }

  @override
  Future<void> addZone(String venueId, String name) async {
    final i = _venues.indexWhere((v) => v.id == venueId);
    if (i == -1) return;
    // Mirrors the server's unique (venue_id, name), like renameZone — the mock
    // has to fail the way the API fails or the screen's error path is never
    // really exercised.
    if (_venues[i].zones.any((z) => z.name == name)) {
      throw const ApiException(
        statusCode: 409,
        code: 'zone_name_taken',
        message: 'Another zone in this venue already uses that name.',
      );
    }
    _venues[i] = _venues[i].copyWith(zones: [
      ..._venues[i].zones,
      Zone(
        id: '$venueId-z${_nextId++}',
        name: name,
        // A fresh zone is on auto playing the same default the server writes
        // into zone_state, so the mock and the API agree on what a new room
        // looks like before anything reports.
        status: ZoneStatus.auto,
        moodId: 'daytime-flow',
      ),
    ]);
    _emit();
  }

  @override
  Future<void> renameZone(String zoneId, String name) async {
    for (var i = 0; i < _venues.length; i++) {
      final venue = _venues[i];
      if (!venue.zones.any((z) => z.id == zoneId)) continue;
      // Mirrors the server's unique (venue_id, name): the mock must reject what
      // the API rejects, or the screen's error path is never exercised.
      if (venue.zones.any((z) => z.id != zoneId && z.name == name)) {
        // An ApiException, not a StateError: messageFor() only surfaces
        // ApiException.message and turns anything else into "Something went
        // wrong" — correct for an internal bug, wrong for a constraint the
        // manager can act on. The mock has to fail the way the API fails or the
        // screen's error path is never really exercised.
        throw const ApiException(
          statusCode: 409,
          code: 'zone_name_taken',
          message: 'Another zone in this venue already uses that name.',
        );
      }
      _venues[i] = venue.copyWith(
        zones: [
          for (final z in venue.zones)
            if (z.id == zoneId) z.copyWith(name: name) else z,
        ],
      );
    }
    _emit();
  }

  @override
  Future<void> removeZone(String zoneId) async {
    for (var i = 0; i < _venues.length; i++) {
      if (_venues[i].zones.any((z) => z.id == zoneId)) {
        _venues[i] = _venues[i].copyWith(
            zones: _venues[i].zones.where((z) => z.id != zoneId).toList());
      }
    }
    _emit();
  }

  void dispose() {
    _controller.close();
  }
}
