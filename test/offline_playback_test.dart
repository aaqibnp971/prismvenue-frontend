/// Finding #7, the repository half: an unreachable server must not stop the
/// room, and an unreachable server must not be confused with a server that
/// answered.
///
/// The predicate itself is covered in `offline_schedule_test.dart`. What is
/// here is the decision about *when* to use it, which is the part that can go
/// quietly wrong: fall back too eagerly and a 403 or a 500 is hidden behind
/// music that sounds correct, which is worse than an error state because
/// nobody goes looking.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prism_venues/data/api/api_client.dart';
import 'package:prism_venues/data/api/api_exception.dart';
import 'package:prism_venues/data/api/api_playback_repo.dart';
import 'package:prism_venues/data/api/api_scope.dart';
import 'package:prism_venues/data/api/installation_id.dart';
import 'package:prism_venues/data/api/offline_plan_cache.dart';
import 'package:prism_venues/data/api/token_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _zone = 'z-1';
const _installation = 'this-tablet';

void main() {
  late OfflinePlanCache cache;
  late bool offline;
  late int status;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    cache = OfflinePlanCache();
    offline = false;
    status = 200;
    InstallationId.resetForTest(_installation);
  });

  tearDown(() => InstallationId.resetForTest());

  ApiPlaybackRepo buildRepo() => ApiPlaybackRepo(
        ApiClient(
          baseUrl: 'http://localhost:8000/v1',
          tokens: InMemoryTokenStore(),
          httpClient: MockClient((request) async {
            if (offline) throw const SocketException('Network is unreachable');
            return http.Response(
              jsonEncode(status == 200
                  ? {
                      'mood_id': 'peak',
                      'paused': false,
                      'player_installation_id': _installation,
                    }
                  : {
                      'error': {'code': 'forbidden', 'message': 'Not for you.'}
                    }),
              status,
              headers: {'content-type': 'application/json'},
            );
          }),
        ),
        ApiScope(
          userId: () => 'u-1',
          zoneId: () => _zone,
          venueId: () => 'v-1',
        ),
        InMemoryTokenStore(),
        // 404 here: SSE is gone on the deployment target, so the repo polls.
        sseClient: MockClient((_) async => http.Response('', 404)),
        offlineCache: cache,
      );

  test('a successful read is remembered for the next outage', () async {
    // The freshest the device will ever be. What a room has to come back to
    // after a power cut is whatever was playing when the lights went out.
    final repo = buildRepo();
    await repo.watchNowPlaying().first;
    repo.dispose();

    // The write is deliberately not awaited by the fetch — a 5-second poll
    // must not block on the disk — so the test waits where production does
    // not.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final held = await cache.read(_zone);
    expect(held?.lastMoodId, 'peak');
    expect(held?.lastPlayerInstallationId, _installation);
  });

  test('an unreachable server falls back to the cached plan', () async {
    await cache.write(
      _zone,
      OfflinePlan(
        blocks: const [
          OfflineBlock(
            dayIndex: 0,
            startMinutes: 0,
            endMinutes: 24 * 60 - 1,
            moodId: 'morning-calm',
          ),
        ],
        // Every day of the week, so the test does not depend on which day it
        // runs — the predicate's day handling is covered properly elsewhere.
        lastMoodId: 'wind-down',
        lastPlayerInstallationId: _installation,
      ),
    );
    offline = true;

    final repo = buildRepo();
    final state = await repo.watchNowPlaying().first;
    repo.dispose();

    // Either the block (if today is Monday) or the last known mood. Both are
    // the room continuing to play, which is the whole finding.
    expect(state.moodId, anyOf('morning-calm', 'wind-down'));
    expect(state.playsHere, isTrue);
  });

  test('with no cache at all, offline is still an error', () async {
    // Nothing to fall back to, and inventing a mood for a room the app knows
    // nothing about would be worse than saying so.
    offline = true;

    final repo = buildRepo();
    await expectLater(
      repo.watchNowPlaying().first,
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', 'network_unreachable')),
    );
    repo.dispose();
  });

  test('a server that answered is never hidden behind the cache', () async {
    // A 403 is an answer. Serving cached music over it would leave a real
    // fault — a revoked role, a removed zone — sounding exactly like a healthy
    // room, and nobody would go looking.
    await cache.write(
      _zone,
      const OfflinePlan(
        lastMoodId: 'wind-down',
        lastPlayerInstallationId: _installation,
      ),
    );
    status = 403;

    final repo = buildRepo();
    await expectLater(
      repo.watchNowPlaying().first,
      throwsA(isA<ApiException>().having((e) => e.statusCode, 'status', 403)),
    );
    repo.dispose();
  });
}
