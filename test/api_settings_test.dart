import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prism_venues/data/api/api_client.dart';
import 'package:prism_venues/data/api/api_exception.dart';
import 'package:prism_venues/data/api/api_scope.dart';
import 'package:prism_venues/data/api/api_settings_repo.dart';
import 'package:prism_venues/data/api/token_store.dart';
import 'package:prism_venues/data/models/guardrails.dart';

/// SettingsRepo mapping and stream behaviour, against a fake transport.
void main() {
  late List<http.Request> sent;
  late Map<String, Object> responses;

  const guardrailsJson = {
    'volume_min_pct': 30,
    'volume_max_pct': 65,
    'quiet_hours_on': true,
    'quiet_hours_start_local': '22:00',
    'quiet_hours_cap_pct': 55,
    'floor_leeway': 'full_band',
    'transition': 'lively',
    'takeover_access': 'managers',
    'offline_alert_minutes': 15,
    'takeover_alert_minutes': 240,
    'takeover_alert_at_close': false,
  };

  const openHoursJson = {
    'open_hour': 7,
    'close_hour': 23,
    'exceptions': [
      {
        'id': 'e-1',
        'days': [4, 5],
        'open_hour': 7,
        'close_hour': 1,
        'closed_all_day': false,
        'every_week': true,
        'label': 'Weekend late close',
      }
    ],
  };

  setUp(() {
    sent = [];
    responses = {
      'guardrails': guardrailsJson,
      'open-hours': openHoursJson,
    };
  });

  ApiSettingsRepo buildRepo({
    String? zoneId = 'z-1',
    String? venueId = 'v-1',
    // Zero here so `await updateGuardrails(...)` in shape-mapping tests means
    // "written"; the debounce-behaviour tests pass a real duration and drive
    // the clock with fakeAsync.
    Duration writeDebounce = Duration.zero,
    int putStatus = 200,
  }) {
    final client = ApiClient(
      baseUrl: 'http://localhost:8000/v1',
      tokens: InMemoryTokenStore(),
      httpClient: MockClient((request) async {
        sent.add(request);
        if (request.method == 'PUT' && putStatus >= 400) {
          return http.Response(
            jsonEncode({
              'error': {
                'code': 'forbidden',
                'message': 'Only managers and owners can change guardrails.',
              }
            }),
            putStatus,
            headers: {'content-type': 'application/json'},
          );
        }
        final match = responses.entries
            .where((e) => request.url.path.contains(e.key))
            .firstOrNull;
        return http.Response(
          jsonEncode(match?.value ?? {}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return ApiSettingsRepo(
      client,
      ApiScope(zoneId: () => zoneId, venueId: () => venueId, userId: _testUser),
      writeDebounce: writeDebounce,
    );
  }

  group('guardrails mapping', () {
    test('decodes every field the app renders', () async {
      final g = await buildRepo().watchGuardrails().first;

      expect(g.volumeMin, 30);
      expect(g.volumeMax, 65);
      expect(g.floorLeeway, FloorLeeway.fullBand);
      expect(g.transition, TransitionSmoothness.lively);
      expect(g.takeoverAccess, TakeoverAccess.managers);
      // 15 minutes is index 2 of ['2 min','5 min','15 min','30 min'].
      expect(g.offlineAlertIndex, 2);
      // 240 minutes is index 2 of ['1 hour','2 hours','4 hours', …].
      expect(g.takeoverAlertIndex, 2);
    });

    test('"At close" decodes to the fourth option, not a duration', () async {
      responses['guardrails'] = {
        ...guardrailsJson,
        'takeover_alert_at_close': true,
      };

      final g = await buildRepo().watchGuardrails().first;

      expect(g.takeoverAlertIndex, 3);
      expect(Guardrails.takeoverAlertOptions[g.takeoverAlertIndex], 'At close');
    });

    test('"At close" encodes as the boolean, never as minutes', () async {
      final repo = buildRepo();
      await repo.updateGuardrails(const Guardrails(takeoverAlertIndex: 3));

      final put = sent.firstWhere((r) => r.method == 'PUT');
      final body = jsonDecode(put.body) as Map<String, dynamic>;
      expect(body['takeover_alert_at_close'], isTrue);
      // A real duration is retained so toggling back restores the choice.
      expect(body['takeover_alert_minutes'], isA<int>());
    });

    test('alert indices encode to real minutes', () async {
      final repo = buildRepo();
      await repo.updateGuardrails(
        const Guardrails(offlineAlertIndex: 3, takeoverAlertIndex: 0),
      );

      final body = jsonDecode(
        sent.firstWhere((r) => r.method == 'PUT').body,
      ) as Map<String, dynamic>;
      expect(body['offline_alert_minutes'], 30);
      expect(body['takeover_alert_minutes'], 60);
    });

    test('an unexpected minute value maps to the closest option', () async {
      // Set by an admin tool, or by a future fifth option. It must not silently
      // become "2 min" just because it is not an exact match.
      responses['guardrails'] = {
        ...guardrailsJson,
        'offline_alert_minutes': 12,
      };

      final g = await buildRepo().watchGuardrails().first;

      expect(Guardrails.offlineAlertOptions[g.offlineAlertIndex], '15 min');
    });

    test('quiet-hours start and cap are never sent', () async {
      // The model has no field for them; sending null would wipe the stored
      // values on every toggle. INTEGRATION_PLAN.md §5.7.
      final repo = buildRepo();
      await repo.updateGuardrails(const Guardrails());

      final body = jsonDecode(
        sent.firstWhere((r) => r.method == 'PUT').body,
      ) as Map<String, dynamic>;
      expect(body.containsKey('quiet_hours_start_local'), isFalse);
      expect(body.containsKey('quiet_hours_cap_pct'), isFalse);
    });
  });

  group('open hours mapping', () {
    test('decodes hours and exceptions', () async {
      final hours = await buildRepo().watchOpenHours().first;

      expect(hours.openHour, 7);
      expect(hours.closeHour, 23);
      expect(hours.exceptions.single.days, {4, 5});
      // Closing after midnight: close < open is legal.
      expect(hours.exceptions.single.closeHour, 1);
      expect(hours.exceptions.single.daysLabel, 'Fri & Sat');
    });

    test('exceptions carry their id, so they can be addressed', () async {
      // Without an id an exception could only ever be added — there was
      // nothing to name in an edit or delete.
      final hours = await buildRepo().watchOpenHours().first;

      expect(hours.exceptions.single.id, 'e-1');
    });

    test('updateException patches by id and refreshes', () async {
      final repo = buildRepo();

      await repo.updateException(const HoursException(
        id: 'e-1',
        days: {3, 4, 5},
        openHour: 7,
        closeHour: 17,
      ));

      final patch = sent.firstWhere((r) => r.method == 'PATCH');
      expect(patch.url.path, endsWith('/open-hours/exceptions/e-1'));
      final body = jsonDecode(patch.body) as Map<String, dynamic>;
      expect(body['days'], [3, 4, 5]);
      expect(body['close_hour'], 17);
      // Refreshed, or the edited row would not change on screen.
      expect(sent.where((r) => r.method == 'GET'), isNotEmpty);
    });

    test('deleteException deletes by id and refreshes', () async {
      final repo = buildRepo();

      await repo.deleteException('e-1');

      final del = sent.firstWhere((r) => r.method == 'DELETE');
      expect(del.url.path, endsWith('/open-hours/exceptions/e-1'));
      expect(sent.where((r) => r.method == 'GET'), isNotEmpty);
    });

    test('addException posts the day set and refreshes', () async {
      final repo = buildRepo();
      await repo.addException(
        const HoursException(days: {0, 6}, openHour: 9, closeHour: 17),
      );

      final post = sent.firstWhere((r) => r.method == 'POST');
      final body = jsonDecode(post.body) as Map<String, dynamic>;
      expect(body['days'], [0, 6]);
      expect(body['open_hour'], 9);
      // A state-changing POST must carry one, per the contract.
      expect(post.headers['Idempotency-Key'], isNotEmpty);
      // And the stream must be refreshed, or the new row never appears.
      expect(sent.where((r) => r.method == 'GET'), isNotEmpty);
    });
  });

  group('stream contract', () {
    test('emits immediately on subscribe', () async {
      // everyday_hours_sheet.dart calls watchOpenHours().first — a stream that
      // only pushes future deltas hangs that sheet forever.
      final hours = await buildRepo().watchOpenHours().first.timeout(
            const Duration(seconds: 2),
          );
      expect(hours.openHour, 7);
    });

    test('tolerates repeated subscription and fetches once', () async {
      // Providers are autoDispose: navigating away and back resubscribes.
      final repo = buildRepo();
      await repo.watchGuardrails().first;
      await repo.watchGuardrails().first;
      await repo.watchGuardrails().first;

      expect(sent.where((r) => r.method == 'GET'), hasLength(1));
    });

    test('supports concurrent subscribers without duplicate fetches', () async {
      final repo = buildRepo();
      await Future.wait([
        repo.watchGuardrails().first,
        repo.watchGuardrails().first,
      ]);

      expect(sent.where((r) => r.method == 'GET'), hasLength(1));
    });

    test('a mutation pushes the new value to existing listeners', () async {
      final repo = buildRepo();
      final seen = <Guardrails>[];
      final sub = repo.watchGuardrails().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      responses['guardrails'] = {...guardrailsJson, 'volume_min_pct': 40};
      await repo.updateGuardrails(const Guardrails(volumeMin: 40));
      await Future<void>.delayed(Duration.zero);

      // The UI never applies a change locally — it must arrive on the stream.
      expect(seen.last.volumeMin, 40);
      await sub.cancel();
    });

    test('a zone with no id fails as a readable API error', () async {
      final repo = buildRepo(zoneId: null);

      await expectLater(repo.watchGuardrails().first, throwsA(anything));
    });

    test('a failed first fetch does not kill the subscription', () async {
      // The router subscribes to guardrails at startup, before sign-in, when
      // there is no zone yet. An `async*` stream ended permanently on that
      // throw, so settings rendered fallback defaults for the whole session
      // and the volume slider could never move.
      String? zoneId; // not signed in yet
      final client = ApiClient(
        baseUrl: 'http://localhost:8000/v1',
        tokens: InMemoryTokenStore(),
        httpClient: MockClient((request) async {
          sent.add(request);
          return http.Response(jsonEncode(guardrailsJson), 200,
              headers: {'content-type': 'application/json'});
        }),
      );
      final repo = ApiSettingsRepo(
        client,
        ApiScope(zoneId: () => zoneId, venueId: () => 'v-1', userId: _testUser),
        writeDebounce: Duration.zero,
      );

      final seen = <Object>[];
      final sub = repo.watchGuardrails().listen(
            seen.add,
            onError: seen.add,
          );
      await Future<void>.delayed(Duration.zero);

      expect(seen.single, isA<ApiException>(),
          reason: 'the missing zone should surface as an error');

      // Sign-in happens: the zone appears and a refresh is issued.
      zoneId = 'z-1';
      await repo.refreshGuardrailsForTest();
      await Future<void>.delayed(Duration.zero);

      expect(seen.last, isA<Guardrails>(),
          reason: 'the same listener must still receive later values');
      await sub.cancel();
      repo.dispose();
    });
  });

  group('write debounce', () {
    test('a drag storm coalesces into one PUT carrying the last value', () {
      // The volume slider calls updateGuardrails on every pixel — 403 writes
      // were observed from a single drag against the real backend.
      fakeAsync((async) {
        final repo =
            buildRepo(writeDebounce: const Duration(milliseconds: 400));

        for (var v = 30; v <= 60; v++) {
          repo.updateGuardrails(Guardrails(volumeMin: v));
        }

        // Still inside the settle window: nothing on the wire.
        async.elapse(const Duration(milliseconds: 399));
        async.flushMicrotasks();
        expect(sent.where((r) => r.method == 'PUT'), isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        final puts = sent.where((r) => r.method == 'PUT').toList();
        expect(puts, hasLength(1));
        // The whole object is the wire contract, so the newest value IS the
        // complete intended state — nothing is lost by dropping the rest.
        expect(jsonDecode(puts.single.body)['volume_min_pct'], 60);
        repo.dispose();
      });
    });

    test('a second adjustment after settling writes again', () {
      fakeAsync((async) {
        final repo =
            buildRepo(writeDebounce: const Duration(milliseconds: 400));

        repo.updateGuardrails(const Guardrails(volumeMin: 30));
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();

        repo.updateGuardrails(const Guardrails(volumeMin: 45));
        async.elapse(const Duration(milliseconds: 400));
        async.flushMicrotasks();

        final puts = sent.where((r) => r.method == 'PUT').toList();
        expect(puts, hasLength(2));
        expect(jsonDecode(puts.last.body)['volume_min_pct'], 45);
        repo.dispose();
      });
    });

    test('the slider tracks immediately even though the write waits', () {
      fakeAsync((async) {
        final repo =
            buildRepo(writeDebounce: const Duration(milliseconds: 400));
        Guardrails? seen;
        final sub = repo.watchGuardrails().listen((g) => seen = g);
        async.flushMicrotasks();

        repo.updateGuardrails(const Guardrails(volumeMin: 42));
        async.flushMicrotasks();

        // Optimistic emit reached the stream; the network has seen nothing.
        expect(seen!.volumeMin, 42);
        expect(sent.where((r) => r.method == 'PUT'), isEmpty);
        sub.cancel();
        repo.dispose();
      });
    });

    test('a refused write snaps back to server truth instead of lying',
        () async {
      final repo = buildRepo(putStatus: 403);
      final seen = <Guardrails>[];
      final sub = repo.watchGuardrails().listen(seen.add);
      await Future<void>.delayed(Duration.zero);

      // Never throws — no screen awaits this call, so a throw would be an
      // unhandled async exception, not feedback. The revert IS the feedback.
      await repo.updateGuardrails(const Guardrails(volumeMin: 90));
      await Future<void>.delayed(Duration.zero);

      expect(seen.map((g) => g.volumeMin), containsAllInOrder([90, 30]));
      expect(seen.last.volumeMin, 30,
          reason: 'the optimistic value must not survive a failed write');
      await sub.cancel();
      repo.dispose();
    });
  });
}

String? _testUser() => 'u-1';
