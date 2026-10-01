/// Finding #15 — who changed this room, and when.
///
/// The history itself is migration 020's trigger and the sentence is composed
/// in the backend, so what is left to prove here is the seam: that the app asks
/// about the zone ON SCREEN rather than the one the session happens to be
/// operating, that a Prism entry is not mistaken for a person, and that a
/// failed read leaves a working screen working.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:prism_venues/data/api/api_client.dart';
import 'package:prism_venues/data/api/api_playback_repo.dart';
import 'package:prism_venues/data/api/api_scope.dart';
import 'package:prism_venues/data/api/token_store.dart';
import 'package:prism_venues/data/models/zone_activity.dart';
import 'package:prism_venues/data/repositories/playback_repo.dart';
import 'package:prism_venues/features/settings/widgets/recent_activity.dart';
import 'package:prism_venues/theme/palette.dart';
import 'package:prism_venues/theme/theme.dart';

void main() {
  group('the wire', () {
    late List<http.Request> sent;
    late Object body;
    late bool offline;

    setUp(() {
      sent = [];
      offline = false;
      body = {
        'entries': [
          {
            'id': 'a-1',
            'at': '2026-09-29T10:00:00Z',
            'actor_name': 'Priya',
            'by_prism': false,
            'line': 'Priya paused the room',
            'mood_id': null,
          },
          {
            'id': 'a-2',
            'at': '2026-09-29T08:00:00Z',
            'actor_name': null,
            'by_prism': true,
            'line': 'Prism switched to Evening warmth',
            'mood_id': 'evening-warmth',
          },
        ],
      };
    });

    ApiPlaybackRepo buildRepo() => ApiPlaybackRepo(
          ApiClient(
            baseUrl: 'http://localhost:8000/v1',
            tokens: InMemoryTokenStore(),
            httpClient: MockClient((request) async {
              sent.add(request);
              if (offline) {
                throw const SocketException('Network is unreachable');
              }
              return http.Response(jsonEncode(body), 200,
                  headers: {'content-type': 'application/json'});
            }),
          ),
          ApiScope(
            userId: () => 'u-1',
            // The session is operating a DIFFERENT room from the one the
            // screen is showing, which is the whole reason activityFor takes
            // an id instead of resolving one from the scope.
            zoneId: () => 'z-operated',
            venueId: () => 'v-1',
          ),
          InMemoryTokenStore(),
          sseClient: MockClient((_) async => http.Response('', 404)),
        );

    test('asks about the zone on screen, not the one being operated', () async {
      final repo = buildRepo();
      await repo.activityFor('z-on-screen');
      repo.dispose();

      expect(sent.single.url.path, endsWith('/zones/z-on-screen/activity'));
    });

    test('maps a person and Prism differently', () async {
      final repo = buildRepo();
      final entries = await repo.activityFor('z-1');
      repo.dispose();

      expect(entries.first.actorName, 'Priya');
      expect(entries.first.byPrism, isFalse);
      // A pause has no new mood, so no dot is drawn.
      expect(entries.first.moodId, isNull);

      expect(entries.last.byPrism, isTrue);
      expect(entries.last.actorName, isNull);
      expect(entries.last.moodId, 'evening-warmth');
    });

    test('renders the line the server composed, verbatim', () async {
      // Same rule as hours_label: the phrasing depends on the mood catalogue
      // and the mode vocabulary, both of which live in the backend.
      final repo = buildRepo();
      final entries = await repo.activityFor('z-1');
      repo.dispose();

      expect(entries.first.line, 'Priya paused the room');
    });

    test('an entry with an unreadable timestamp does not take the panel down',
        () async {
      body = {
        'entries': [
          {'id': 'a-1', 'at': 'not a date', 'line': 'Something happened'},
        ],
      };

      final repo = buildRepo();
      final entries = await repo.activityFor('z-1');
      repo.dispose();

      expect(entries.single.line, 'Something happened');
    });

    test('an unreachable server throws rather than inventing a history',
        () async {
      offline = true;
      final repo = buildRepo();

      await expectLater(repo.activityFor('z-1'), throwsA(isA<Exception>()));
      repo.dispose();
    });
  });

  group('the panel', () {
    Future<void> pump(
      WidgetTester tester,
      Future<List<ZoneActivityEntry>> Function() activity,
    ) async {
      await tester.binding.setSurfaceSize(const Size(900, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          zoneActivityProvider('z-1').overrideWith((ref) => activity()),
        ],
        child: MaterialApp(
          theme: buildPrismTheme(PrismPalette.dark),
          home: const Scaffold(body: RecentActivity(zoneId: 'z-1')),
        ),
      ));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('shows what happened and how long ago', (tester) async {
      await pump(tester, () async {
        final now = DateTime.now();
        return [
          ZoneActivityEntry(
            id: 'a-1',
            at: now.subtract(const Duration(minutes: 8)),
            line: 'Priya paused the room',
            actorName: 'Priya',
          ),
        ];
      });

      expect(find.text('Recent activity'), findsOneWidget);
      expect(find.text('Priya paused the room'), findsOneWidget);
      expect(find.text('8 minutes ago'), findsOneWidget);
    });

    testWidgets('says a room has no history, rather than showing nothing',
        (tester) async {
      // "Nothing has happened here" and "we could not load it" are different
      // answers, and the owner deserves to know which.
      await pump(tester, () async => []);

      expect(find.text('Nothing has changed in this room yet.'),
          findsOneWidget);
    });

    testWidgets('a failed read leaves the rest of the screen alone',
        (tester) async {
      // Every other thing on the zone screen still works without this, and a
      // red block over a history panel would make a working screen look broken.
      await pump(tester, () async => throw Exception('boom'));

      expect(find.text('Recent activity'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
