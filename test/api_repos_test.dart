import 'dart:convert';

import 'package:fake_async/fake_async.dart';
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
import 'package:prism_venues/data/models/timezone.dart';
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
        userId: _testUser,
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

      final venues = await ApiVenueRepo(buildClient(), scope()).watchVenues().first;

      expect(venues.map((v) => v.name), ['Dockside', 'Marina Café', 'Harbor House']);
    });

    test('signing in as another account does not serve the first account venues',
        () async {
      // The portfolio is the one stream scoped to the ACCOUNT rather than to a
      // room, so it was the one with no cache key — it survived a sign-out and
      // kept serving the previous user's venues until some mutation happened to
      // call refresh(). Two orgs' venue names on screen is the worst shape that
      // can take.
      var user = 'u-owner-a';
      final repo = ApiVenueRepo(
        buildClient(),
        ApiScope(zoneId: _zone, venueId: _venue, userId: () => user),
      );

      routes['/venues'] = [venue('v-a', "A's venue", const [])];
      expect((await repo.watchVenues().first).map((v) => v.name), ["A's venue"]);

      // Sign out, sign in as somebody else. Same repo instance: it lives in the
      // root container and is not rebuilt.
      user = 'u-owner-b';
      routes['/venues'] = [venue('v-b', "B's venue", const [])];

      expect((await repo.watchVenues().first).map((v) => v.name), ["B's venue"]);
    });

    test('the drill-in view is account-scoped too', () async {
      // Same defect one level down: _byId outlives the session, and its entries
      // are keyed by venue id alone.
      var user = 'u-owner-a';
      final repo = ApiVenueRepo(
        buildClient(),
        ApiScope(zoneId: _zone, venueId: _venue, userId: () => user),
      );

      routes['/venues/v-1'] = venue('v-1', "A's venue", const []);
      expect((await repo.watchVenue('v-1').first)?.name, "A's venue");

      user = 'u-owner-b';
      routes['/venues/v-1'] = venue('v-1', "B's venue", const []);
      expect((await repo.watchVenue('v-1').first)?.name, "B's venue");
    });

    test('sends the device clock when adding a venue', () async {
      // `venues.timezone` is the only thing that decides which daypart is
      // current, and nothing was ever setting it — so every venue took the
      // column default and every schedule fired on somebody else's clock. Two
      // offsets, not one: a single reading cannot separate a DST zone from a
      // fixed one at the same current offset.
      routes['/venues'] = <Object>[];
      final repo = ApiVenueRepo(buildClient(), scope());

      await repo.addVenue(
        name: 'Harbor House',
        address: '3 Quayside Lane',
        zoneNames: const ['Dining room'],
        deviceOffsets:
            const DeviceOffsets(januaryMinutes: 330, julyMinutes: 330),
      );

      final body = jsonDecode(
        sent.firstWhere((r) => r.method == 'POST').body,
      ) as Map<String, dynamic>;
      expect(body['device_offsets'],
          {'january_minutes': 330, 'july_minutes': 330});
    });

    test('omits the clock entirely when there is no reading', () async {
      // Absent, not null: the server branches on "no reading, leave the column
      // default", and a null would have to be special-cased there instead.
      routes['/venues'] = <Object>[];
      await ApiVenueRepo(buildClient(), scope())
          .addVenue(name: 'X', address: '', zoneNames: const []);

      final body = jsonDecode(
        sent.firstWhere((r) => r.method == 'POST').body,
      ) as Map<String, dynamic>;
      expect(body.containsKey('device_offsets'), isFalse);
    });

    test('reads back the venue clock, and does not invent one', () async {
      routes['/venues'] = [
        {
          'id': 'v1',
          'name': 'Harbor House',
          'address': null,
          'hours_label': 'Every day · 7am–11pm',
          'timezone': 'Asia/Kolkata',
          'local_time': '22:28',
          'zones': <Object>[],
        },
        {
          'id': 'v2',
          'name': 'Older server',
          'address': null,
          'hours_label': 'Every day · 7am–11pm',
          'zones': <Object>[],
        },
      ];

      final venues =
          await ApiVenueRepo(buildClient(), scope()).watchVenues().first;
      final byName = {for (final v in venues) v.name: v};

      expect(byName['Harbor House']!.timezone, 'Asia/Kolkata');
      expect(byName['Harbor House']!.localTime, '22:28');
      // A server that does not send it leaves null — rendering a confident
      // zone nobody sent is how this stayed invisible.
      expect(byName['Older server']!.timezone, isNull);
    });

    test('setTimezone patches the venue', () async {
      routes['/venues'] = <Object>[];
      await ApiVenueRepo(buildClient(), scope())
          .setTimezone('v-1', 'Asia/Kolkata');

      final patch = sent.firstWhere((r) => r.method == 'PATCH');
      expect(patch.url.path, endsWith('/venues/v-1'));
      expect(jsonDecode(patch.body), {'timezone': 'Asia/Kolkata'});
    });

    test('maps every zone status', () async {
      routes['/venues'] = [
        venue('v1', 'X', [
          zone('z1', 'A', 'auto'),
          zone('z2', 'B', 'off_schedule'),
          zone('z3', 'C', 'offline'),
        ])
      ];

      final zones = (await ApiVenueRepo(buildClient(), scope()).watchVenues().first)
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

      final zones = (await ApiVenueRepo(buildClient(), scope()).watchVenues().first)
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

      expect(await ApiVenueRepo(buildClient(), scope()).watchVenue('nope').first, isNull);
    });

    test('a quick-fix refreshes the portfolio', () async {
      routes['/venues'] = [venue('v1', 'X', [zone('z1', 'A', 'off_schedule')])];
      final repo = ApiVenueRepo(buildClient(), scope());
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
      final repo = ApiVenueRepo(buildClient(), scope());

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

    test('the rail refetches on its own as the clock moves', () {
      // now_index is derived from the VENUE's clock, so this response goes
      // stale with nothing on this side changing. The Floor hero polls
      // now-playing every 5s and moved on to the next daypart while the rail
      // beside it kept whatever it fetched when the screen opened — the room
      // played Peak under a rail insisting Morning calm was current.
      //
      // fakeAsync because the real interval is 30s: shortening it for the test
      // would leave the shipped number untested, which is the number that
      // matters.
      fakeAsync((async) {
        routes['/today'] = {
          'entries': [
            {'time_label': '12:00', 'mood_id': 'morning-calm'},
            {'time_label': '1:15', 'mood_id': 'peak'},
          ],
          'now_index': 0,
          'next_index': 1,
          'auto': true,
        };
        final repo = ApiScheduleRepo(buildClient(), scope());

        final seen = <int>[];
        final sub = repo.watchToday().listen((t) => seen.add(t.nowIndex));
        async.elapse(const Duration(milliseconds: 10));
        expect(seen, [0]);

        // The clock crosses 1:15 and the server's answer changes. Nothing here
        // wrote anything, so only a timer can notice.
        routes['/today'] = {
          'entries': [
            {'time_label': '12:00', 'mood_id': 'morning-calm'},
            {'time_label': '1:15', 'mood_id': 'peak'},
          ],
          'now_index': 1,
          'next_index': -1,
          'auto': true,
        };

        async.elapse(const Duration(seconds: 31));
        expect(seen.last, 1,
            reason: 'the rail must move to the daypart that is current');
        sub.cancel();
      });
    });

    test('the ticker stops when nothing is watching', () {
      // autoDispose providers drop the last listener on navigating away, and a
      // timer that outlived it would poll a zone nobody is looking at.
      fakeAsync((async) {
        routes['/today'] = {'entries': [], 'now_index': -1, 'auto': true};
        final repo = ApiScheduleRepo(buildClient(), scope());

        final sub = repo.watchToday().listen((_) {});
        async.elapse(const Duration(milliseconds: 10));
        sub.cancel();
        async.elapse(const Duration(milliseconds: 10));

        final after = sent.length;
        async.elapse(const Duration(minutes: 3));
        expect(sent.length, after,
            reason: 'no requests once nobody is listening');
      });
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
String? _testUser() => 'u-1';
