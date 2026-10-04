import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prism_venues/data/api/api_client.dart';
import 'package:prism_venues/data/api/api_mood_repo.dart';
import 'package:prism_venues/data/api/api_scope.dart';
import 'package:prism_venues/data/api/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// `GET /moods` and `GET /zones/{id}/moods`, against a fake transport.
void main() {
  late List<http.Request> sent;
  late bool offline;
  late int status;

  const peak = {
    'id': 'peak',
    'name': 'Peak',
    'mood_set_id': '00000000-0000-4000-8000-000000000001',
    'sort_order': 5,
    'is_default': false,
    'arousal': 0.92,
    'valence': 0.7,
    'cognitive_load': 0.35,
    'readiness': 0.58,
    'bpm': 124,
    'energy': 5,
    'dot_dark': '#F0564F',
    'dot_light': '#D83A33',
    'grad_start': '#F4685F',
    'grad_end': '#D22F28',
    'mode_hint': 'venue_peak',
    'scene_manifest': 'mood_peak.json',
    'lowpass_floor_hz': null,
  };

  const forest = {
    'id': 'lnl-forest-floor',
    'name': 'Forest Floor',
    'mood_set_id': '11111111-2222-4333-8444-555555555555',
    'sort_order': 1,
    'is_default': true,
    'arousal': 0.25,
    'valence': 0.65,
    'cognitive_load': 0.5,
    'readiness': 0.5,
    'bpm': null,
    'energy': 1,
    'dot_dark': '#84C44A',
    'dot_light': '#699F35',
    'grad_start': '#92CE58',
    'grad_end': '#5F9427',
    'mode_hint': 'venue_settle',
    'scene_manifest': 'mood_lnl_forest_floor.json',
    'lowpass_floor_hz': 6000,
  };

  setUp(() {
    sent = [];
    offline = false;
    status = 200;
    SharedPreferences.setMockInitialValues({});
  });

  ApiMoodRepo buildRepo({
    String? zoneId = 'z-1',
    String userId = 'u-1',
    List<Object?> catalogue = const [peak, forest],
    List<Object?> zoneMoods = const [forest],
  }) {
    final client = ApiClient(
      baseUrl: 'http://localhost:8000/v1',
      tokens: InMemoryTokenStore(),
      httpClient: MockClient((request) async {
        sent.add(request);
        if (offline) throw const SocketException('Network is unreachable');
        if (status >= 400) {
          return http.Response(
            jsonEncode({
              'error': {'code': 'not_found', 'message': 'Not found.'}
            }),
            status,
            headers: {'content-type': 'application/json'},
          );
        }
        final body = request.url.path.contains('/zones/') ? zoneMoods : catalogue;
        return http.Response(jsonEncode(body), 200,
            headers: {'content-type': 'application/json'});
      }),
    );
    final repo = ApiMoodRepo(
      client,
      ApiScope(zoneId: () => zoneId, venueId: () => 'v-1', userId: () => userId),
    );
    addTearDown(repo.dispose);
    return repo;
  }

  test('the catalogue is every mood the server returns, nulls intact',
      () async {
    final moods = await buildRepo().watchCatalogue().first;

    expect(sent.single.url.path, '/v1/moods');
    expect(moods.map((m) => m.id), ['peak', 'lnl-forest-floor']);
    expect(moods[0].bpm, 124);
    expect(moods[0].lowpassFloorHz, isNull);
    expect(moods[1].bpm, isNull);
    expect(moods[1].lowpassFloorHz, 6000);
  });

  test('a room\'s moods are asked for by zone', () async {
    final moods = await buildRepo(zoneId: 'z-42').watchZoneMoods().first;

    expect(sent.single.url.path, '/v1/zones/z-42/moods');
    expect(moods.map((m) => m.id), ['lnl-forest-floor']);
  });

  test('one unreadable row is skipped, not the whole catalogue', () async {
    final moods = await buildRepo(catalogue: const [
      {'id': 'broken'},
      forest,
    ]).watchCatalogue().first;

    expect(moods.map((m) => m.id), ['lnl-forest-floor']);
  });

  test('offline, the catalogue comes back from the device', () async {
    // A tablet that restarts while the venue's internet is down knows from
    // the offline plan which mood the room should be on. Without the row
    // behind that id there is no scene and no preset, and the room is silent.
    await buildRepo().watchCatalogue().first;

    offline = true;
    final moods = await buildRepo().watchCatalogue().first;

    expect(moods.map((m) => m.id), ['peak', 'lnl-forest-floor']);
    expect(moods[1].lowpassFloorHz, 6000);
  });

  test('the device\'s copy is never handed to a different account', () async {
    await buildRepo(userId: 'u-1').watchCatalogue().first;

    offline = true;
    await expectLater(
      buildRepo(userId: 'u-2').watchCatalogue().first,
      throwsA(anything),
    );
  });

  test('clearing on sign-out removes the copy', () async {
    await buildRepo().watchCatalogue().first;
    await ApiMoodRepo.clearStored();

    offline = true;
    await expectLater(buildRepo().watchCatalogue().first, throwsA(anything));
  });

  test('a backend without the endpoint is an error, not an empty catalogue',
      () async {
    // An empty list would read as "this account has no moods". The caller
    // falls back to what it already knows instead (`zoneMoodsProvider`).
    status = 404;
    await expectLater(buildRepo().watchZoneMoods().first, throwsA(anything));
    await expectLater(buildRepo().watchCatalogue().first, throwsA(anything));
  });
}
