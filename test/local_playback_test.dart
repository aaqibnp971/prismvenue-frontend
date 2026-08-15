import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/local_playback.dart';
import 'package:prism_venues/data/models/venue.dart';
import 'package:prism_venues/data/models/zone.dart';

/// The app is the player, so it can disprove `offline` for rooms it has driven
/// audio into — see `lib/app/local_playback.dart`.
void main() {
  Venue venue(List<Zone> zones) => Venue(id: 'v', name: 'Dockside', zones: zones);

  const offlineBar = Zone(
    id: 'bar',
    name: 'Bar',
    status: ZoneStatus.offline,
    moodId: 'evening-warmth',
    statusDetail: 'Offline',
  );

  /// Playing `bar` right now, having played nothing else.
  LocalPlayback playing(ZoneStatus status) => LocalPlayback(
        reachable: const {'bar'},
        currentZoneId: 'bar',
        currentStatus: status,
      );

  group('a room this app is playing', () {
    test('stops reading offline', () {
      // The exact case seen live: the portfolio said "Bar · Offline" in red
      // while this process was audibly playing Evening warmth into it.
      final fixed = withLocalPlayback(venue([offlineBar]), playing(ZoneStatus.auto));

      expect(fixed.zones.single.status, ZoneStatus.auto);
      expect(fixed.worstStatus, ZoneStatus.auto);
    });

    test('does not carry the "Offline" detail onto the fixed row', () {
      // Zone.copyWith keeps statusDetail for any non-auto status, which would
      // leave the literal word "Offline" as an amber row's countdown text.
      final fixed =
          withLocalPlayback(venue([offlineBar]), playing(ZoneStatus.offSchedule));

      expect(fixed.zones.single.status, ZoneStatus.offSchedule);
      expect(fixed.zones.single.statusDetail, isNull);
    });

    test('stays amber when held manually, rather than flattening to quiet', () {
      // offSchedule is the server's own answer to "is a human holding this
      // room", and it is what `offline` was masking. Playing it locally proves
      // reachability, not that nobody is overriding it.
      final fixed =
          withLocalPlayback(venue([offlineBar]), playing(ZoneStatus.offSchedule));

      expect(fixed.worstStatus, ZoneStatus.offSchedule);
    });
  });

  group('rooms this app cannot vouch for', () {
    test('are left alone', () {
      // First-hand evidence covers rooms this app has played. A venue on
      // another iPad may be genuinely unreachable, and turning every red row
      // green would replace one wrong answer with a more confident one.
      const otherOffline = Zone(
          id: 'terrace',
          name: 'Terrace',
          status: ZoneStatus.offline,
          moodId: 'peak');

      final fixed = withLocalPlayback(
          venue([offlineBar, otherOffline]), playing(ZoneStatus.auto));

      expect(fixed.zones[0].status, ZoneStatus.auto);
      expect(fixed.zones[1].status, ZoneStatus.offline);
      expect(fixed.worstStatus, ZoneStatus.offline);
    });

    test('nothing playing changes nothing, and returns the same instance', () {
      // Called on every build, so the no-op path must be free.
      final original = venue([offlineBar]);
      expect(identical(withLocalPlayback(original, null), original), isTrue);
    });

    test('a zone that was never offline is untouched', () {
      const healthy =
          Zone(id: 'bar', name: 'Bar', status: ZoneStatus.auto, moodId: 'peak');
      final original = venue([healthy]);

      expect(
          identical(
              withLocalPlayback(original, playing(ZoneStatus.offSchedule)),
              original),
          isTrue);
    });
  });

  group('the latch — a played room stays vouched for after you leave it', () {
    // The reported behaviour: play sample101/Dubai, switch to another zone, and
    // Dubai flipped straight back to a red "Offline". Navigating away does not
    // un-prove that a room exists.
    const dubai = Zone(
        id: 'dubai',
        name: 'Dubai',
        status: ZoneStatus.offline,
        moodId: 'morning-calm',
        statusDetail: 'Offline');

    // Now operating 'bar'; 'dubai' was played earlier this run.
    const movedOn = LocalPlayback(
      reachable: {'dubai', 'bar'},
      currentZoneId: 'bar',
      currentStatus: ZoneStatus.offSchedule,
    );

    test('a previously played room is still corrected once you move on', () {
      final fixed =
          withLocalPlayback(Venue(id: 'v', name: 'sample101', zones: const [dubai]), movedOn);

      expect(fixed.zones.single.status, ZoneStatus.auto);
      expect(fixed.zones.single.statusDetail, isNull);
    });

    test('a played room reads quiet, not the current room\'s status', () {
      // Reachability is all that was proven for it. Whether a human has since
      // overridden it is a question only the server can answer, and `offline`
      // masked that.
      expect(movedOn.statusFor('dubai'), ZoneStatus.auto);
      expect(movedOn.statusFor('bar'), ZoneStatus.offSchedule);
    });

    test('a room never played is left alone', () {
      expect(movedOn.statusFor('never-touched'), isNull);

      final untouched = withLocalPlayback(
          Venue(id: 'v', name: 'x', zones: const [dubai]),
          const LocalPlayback(
              reachable: {'bar'},
              currentZoneId: 'bar',
              currentStatus: ZoneStatus.auto));
      expect(untouched.zones.single.status, ZoneStatus.offline);
    });

    test('the latch expires when Prism stops', () {
      // localPlaybackProvider returns null whenever the engine is not playing:
      // paused, taken over, failed, or web. Every row falls back to the server.
      final original = Venue(id: 'v', name: 'x', zones: const [dubai]);
      expect(identical(withLocalPlayback(original, null), original), isTrue);
      expect(statusOf(dubai, null), ZoneStatus.offline);
    });
  });

  group('PlayedZones', () {
    test('accumulates rooms and clears them all at once', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final zones = container.read(playedZonesProvider.notifier);

      expect(container.read(playedZonesProvider), isEmpty);

      zones.remember('dubai');
      zones.remember('bar');
      zones.remember('dubai'); // idempotent
      expect(container.read(playedZonesProvider), {'dubai', 'bar'});

      // Pause or takeover: Prism is no longer the player, so the evidence goes.
      zones.clear();
      expect(container.read(playedZonesProvider), isEmpty);
    });
  });

  group('statusOf', () {
    test('corrects only rooms the app can vouch for', () {
      expect(statusOf(offlineBar, playing(ZoneStatus.auto)), ZoneStatus.auto);
      expect(
          statusOf(
              offlineBar,
              const LocalPlayback(
                  reachable: {'other'},
                  currentZoneId: 'other',
                  currentStatus: ZoneStatus.auto)),
          ZoneStatus.offline);
      expect(statusOf(offlineBar, null), ZoneStatus.offline);
    });
  });
}
