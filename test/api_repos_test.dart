import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prism_venues/data/api/api_client.dart';
import 'package:prism_venues/data/api/api_playback_repo.dart';
import 'package:prism_venues/data/api/api_schedule_repo.dart';
import 'package:prism_venues/data/api/api_scope.dart';
import 'package:prism_venues/data/api/api_venue_repo.dart';
import 'package:prism_venues/data/api/token_store.dart';
import 'package:prism_venues/data/models/schedule_entry.dart';
import 'package:prism_venues/data/models/zone.dart';

/// VenueRepo, ScheduleRepo and PlaybackRepo mapping against a fake transport.
void main() {
  late List<http.Request> sent;
  late Map<String, Object> routes;
  late List<int> statuses;

  setUp(() {
    sent = [];
    routes = {};
    statuses = [];
  });

  ApiClient buildClient() => ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokens: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          sent.add(request);
          final match = routes.entries
              .where((e) => request.url.path.endsWith(e.key))
              .firstOrNull;
          final status = statuses.isNotEmpty ? statuses.removeAt(0) : 200;
          return http.Response(
            jsonEncode(match?.value ?? {}),
            status,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

  ApiScope scope() => const ApiScope(
        zoneId: _zone,
        venueId: _venue,
      );

  // --- Venues ---------------------------------------------------------------

  group('ApiVenueRepo', () {
    Map<String, Object?> venue(String id, String name, List zones) =>
        {'id': id, 'name': name, 'hours_label': 'Every day · 7am–11pm', 'zones': zones};

    Map<String, Object?> zone(String id, String name, String status) =>
        {'id': id, 'name': name, 'status': status, 'mood_id': 'peak'};

    test('sorts needs-attention first, matching the mock', () async {
      // S04-2's whole triage treatment depends on this order.
      routes['/venues'] = [
        venue('v-quiet', 'Harbor House', [zone('z1', 'Dining', 'auto')]),
        venue('v-amber', 'Marina Café', [zone('z2', 'Terrace', 'off_schedule')]),
        venue('v-red', 'Dockside', [zone('z3', 'Bar', 'offline')]),
      ];

      final venues = await ApiVenueRepo(buildClient()).watchVenues().first;

      expect(venues.map((v) => v.name), ['Dockside', 'Marina Café', 'Harbor House']);
    });

    test('maps every zone status', () async {
      routes['/venues'] = [
        venue('v1', 'X', [
          zone('z1', 'A', 'auto'),
          zone('z2', 'B', 'off_schedule'),
          zone('z3', 'C', 'offline'),
        ])
      ];

      final zones = (await ApiVenueRepo(buildClient()).watchVenues().first)
          .single
          .zones;

      expect(zones.map((z) => z.status), [
        ZoneStatus.auto,
        ZoneStatus.offSchedule,
        ZoneStatus.offline,
      ]);
    });

    test('an unrecognised status does not invent a problem', () async {
      routes['/venues'] = [
        venue('v1', 'X', [zone('z1', 'A', 'reticulating-splines')])
      ];

      final zones = (await ApiVenueRepo(buildClient()).watchVenues().first)
          .single
          .zones;

      expect(zones.single.status, ZoneStatus.auto);
    });

    test('an unknown venue id resolves to null, not an error', () async {
      // venue_screen renders `Venue?` = null for this case.
      statuses = [404];
      routes['/venues/nope'] = {
        'error': {'code': 'not_found', 'message': 'That venue was not found.'}
      };

      expect(await ApiVenueRepo(buildClient()).watchVenue('nope').first, isNull);
    });

    test('a quick-fix refreshes the portfolio', () async {
      routes['/venues'] = [venue('v1', 'X', [zone('z1', 'A', 'off_schedule')])];
      final repo = ApiVenueRepo(buildClient());
      await repo.watchVenues().first;

      await repo.returnZoneToAuto('v1', 'z1');

      // The UI never applies a change locally — without the refetch the amber
      // row would stay amber forever.
      expect(sent.where((r) => r.url.path.endsWith('/venues')), hasLength(2));
      expect(
        sent.firstWhere((r) => r.method == 'POST').headers['Idempotency-Key'],
        isNotEmpty,
      );
    });

    test('removeZone deletes and refreshes', () async {
      routes['/venues'] = <Object>[];
      final repo = ApiVenueRepo(buildClient());

      await repo.removeZone('z1');

      expect(sent.first.method, 'DELETE');
      expect(sent.first.url.path, endsWith('/zones/z1'));
    });
  });

  // --- Schedule -------------------------------------------------------------

  group('ApiScheduleRepo', () {
    test('takes now_index from the server, never computing it', () async {
      // It depends on the venue's timezone, which the client does not know.
      routes['/today'] = {
        'entries': [
          {'time_label': '7:00 am', 'mood_id': 'morning-calm'},
          {'time_label': '2:00 pm', 'mood_id': 'afternoon-lift'},
        ],
        'now_index': 1,
        'auto': true,
      };

      final today =
          await ApiScheduleRepo(buildClient(), scope()).watchToday().first;

      expect(today.nowIndex, 1);
      expect(today.entries.first.timeLabel, '7:00 am');
      expect(today.auto, isTrue);
    });

    test('maps the mode both ways', () async {
      routes['/mode'] = {'mode': 'custom'};
      final repo = ApiScheduleRepo(buildClient(), scope());

      expect(await repo.watchMode().first, ScheduleMode.custom);

      await repo.setMode(ScheduleMode.selfDrive);
      final post = sent.firstWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body)['mode'], 'self_drive');
    });

    test('prefers the server range label over the derived one', () async {
      routes['/dayparts'] = [
        {
          'id': 'd1',
          'day_index': 0,
          'start_hour': 7,
          'end_hour': 11,
          'range_label': '7 – 11 am',
          'mood_id': 'morning-calm',
        }
      ];

      final plan =
          await ApiScheduleRepo(buildClient(), scope()).watchWeekPlan(null).first;

      expect(plan.single.rangeLabel, '7 – 11 am');
      expect(plan.single.startHour, 7);
      expect(plan.single.endHour, 11);
    });

    test('sends hours and never sends the label', () async {
      // The label is derived server-side; sending it would invite drift.
      routes['/dayparts'] = <Object>[];
      routes['/today'] = {'entries': [], 'now_index': 0, 'auto': true};
      final repo = ApiScheduleRepo(buildClient(), scope());

      await repo.addDaypart(const Daypart(
        id: '',
        dayIndex: 2,
        startHour: 14,
        endHour: 18,
        moodId: 'afternoon-lift',
      ));

      final body = jsonDecode(
        sent.firstWhere((r) => r.method == 'POST').body,
      ) as Map<String, dynamic>;
      expect(body['start_hour'], 14);
      expect(body['end_hour'], 18);
      expect(body['start_minute'], 0);
      expect(body['end_minute'], 0);
      expect(body.containsKey('range_label'), isFalse);
      // The server assigns the real id; the client's empty one is ignored.
      expect(body.containsKey('id'), isFalse);
    });

    test('sends minutes, and reads them back', () async {
      // A daypart boundary is not always on the hour. The column always held
      // minutes; the wire and the write path are what were hour-only, so this
      // asserts on the body rather than on anything the UI renders.
      routes['/dayparts'] = <Object>[];
      routes['/today'] = {'entries': [], 'now_index': 0, 'auto': true};
      final repo = ApiScheduleRepo(buildClient(), scope());

      await repo.addDaypart(const Daypart(
        id: '',
        dayIndex: 2,
        startHour: 6,
        endHour: 11,
        startMinute: 30,
        endMinute: 45,
        moodId: 'afternoon-lift',
      ));

      final body = jsonDecode(
        sent.firstWhere((r) => r.method == 'POST').body,
      ) as Map<String, dynamic>;
      expect(body['start_hour'], 6);
      expect(body['start_minute'], 30);
      expect(body['end_hour'], 11);
      expect(body['end_minute'], 45);
    });

    test('a server that sends no minutes still reads as whole hours', () async {
      // Both fields are defaulted rather than required, so a backend that
      // predates minute precision keeps working instead of throwing on a null.
      routes['/dayparts'] = [
        {
          'id': 'd1',
          'day_index': 0,
          'start_hour': 7,
          'end_hour': 11,
          'range_label': '7 – 11 am',
          'mood_id': 'morning-calm',
        }
      ];

      final plan =
          await ApiScheduleRepo(buildClient(), scope()).watchWeekPlan(null).first;

      expect(plan.single.startMinute, 0);
      expect(plan.single.endMinute, 0);
      expect(plan.single.startMinutesOfDay, 7 * 60);
    });
  });

  // --- Playback -------------------------------------------------------------

  group('ApiPlaybackRepo', () {
    ApiPlaybackRepo buildPlayback() => ApiPlaybackRepo(
          buildClient(),
          scope(),
          InMemoryTokenStore(),
          // SSE unavailable → the repo falls back to polling rather than going
          // silent. Returning 404 exercises that path.
          sseClient: MockClient((_) async => http.Response('', 404)),
        );

    test('maps now-playing including the paused pill name', () async {
      routes['/now'] = {
        'mood_id': 'afternoon-lift',
        'paused': true,
        'paused_by': 'Priya',
        'context_line': 'mid-afternoon · ~60% full · clear',
      };

      final repo = buildPlayback();
      final state = await repo.watchNowPlaying().first;

      expect(state.moodId, 'afternoon-lift');
      expect(state.paused, isTrue);
      expect(state.pausedBy, 'Priya');
      expect(state.contextLine, 'mid-afternoon · ~60% full · clear');
      repo.dispose();
    });

    test('a missing mood resolves to a renderable one', () async {
      // moodById() throws on an unknown id — a crash, not a blank tile.
      routes['/now'] = {'paused': false};

      final repo = buildPlayback();
      final state = await repo.watchNowPlaying().first;

      expect(state.moodId, 'daytime-flow');
      repo.dispose();
    });

    test('maps an active takeover with its remaining time', () async {
      routes['/takeover'] = {
        'active': true,
        'started_at': '2026-07-27T11:02:14Z',
        'remaining_seconds': 108,
        'has_auto_return': true,
        'started_by_name': 'Priya Nair',
      };

      final repo = buildPlayback();
      final state = await repo.watchTakeover().first;

      expect(state.active, isTrue);
      expect(state.remaining, const Duration(seconds: 108));
      // §6-A7 countdown format, rendered from this.
      expect(state.countdownLabel, '1:48');
      expect(state.hasAutoReturn, isTrue);
      // The S02-2 footer's "Started by …".
      expect(state.startedByName, 'Priya Nair');
      repo.dispose();
    });

    test('hour-scale countdowns render h:mm, matching the S02 frames',
        () async {
      // 1h48m — the frame shows "1:48", not "108:00".
      routes['/takeover'] = {
        'active': true,
        'started_at': '2026-07-27T11:02:14Z',
        'remaining_seconds': 6480,
        'has_auto_return': true,
      };

      final repo = buildPlayback();
      final state = await repo.watchTakeover().first;

      expect(state.countdownLabel, '1:48');
      repo.dispose();
    });

    test('maps a takeover whose auto-return was removed', () async {
      routes['/takeover'] = {
        'active': true,
        'started_at': '2026-07-27T11:02:14Z',
        'remaining_seconds': 0,
        'has_auto_return': false,
        'started_by_name': 'Aaqib',
      };

      final repo = buildPlayback();
      final state = await repo.watchTakeover().first;

      expect(state.active, isTrue);
      expect(state.hasAutoReturn, isFalse);
      repo.dispose();
    });

    test('removeAutoReturn posts to the endpoint and refreshes', () async {
      routes['/takeover'] = {
        'active': true,
        'remaining_seconds': 600,
        'has_auto_return': true,
      };
      final repo = buildPlayback();

      await repo.removeAutoReturn();

      final post = sent.firstWhere((r) => r.method == 'POST');
      expect(post.url.path, endsWith('/takeover/remove-auto-return'));
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      repo.dispose();
    });

    test('startTakeover sends whole minutes', () async {
      routes['/takeover'] = {'active': false};
      routes['/now'] = {'mood_id': 'peak', 'paused': false};
      final repo = buildPlayback();

      await repo.startTakeover(handBackAfter: const Duration(minutes: 30));

      final post = sent.firstWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body)['hand_back_after_minutes'], 30);
      repo.dispose();
    });

    test('extendTakeover sends the added minutes, not a new total', () async {
      routes['/takeover'] = {'active': true, 'remaining_seconds': 600};
      final repo = buildPlayback();

      await repo.extendTakeover(const Duration(minutes: 15));

      final post = sent.firstWhere((r) => r.method == 'POST');
      expect(jsonDecode(post.body)['additional_minutes'], 15);
      repo.dispose();
    });

    test('setMood posts the id and refreshes now-playing', () async {
      routes['/now'] = {'mood_id': 'peak', 'paused': false};
      final repo = buildPlayback();

      await repo.setMood('peak');

      expect(jsonDecode(sent.first.body)['mood_id'], 'peak');
      expect(sent.where((r) => r.method == 'GET'), isNotEmpty);
      repo.dispose();
    });
  });
}

String? _zone() => 'z-1';
String? _venue() => 'v-1';
