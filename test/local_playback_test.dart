import 'package:flutter_test/flutter_test.dart';
import 'package:prism_venues/app/local_playback.dart';
import 'package:prism_venues/data/models/venue.dart';
import 'package:prism_venues/data/models/zone.dart';

/// The app is the player, so it can disprove `offline` for the room it is
/// rendering — see `lib/app/local_playback.dart`.
void main() {
  Venue venue(List<Zone> zones) => Venue(id: 'v', name: 'Dockside', zones: zones);

  const offlineBar = Zone(
    id: 'bar',
    name: 'Bar',
    status: ZoneStatus.offline,
    moodId: 'evening-warmth',
    statusDetail: 'Offline',
  );

  test('a room this app is playing stops reading offline', () {
    // The exact case seen live: the portfolio said "Bar · Offline" in red while
    // this process was audibly playing Evening warmth into it.
    final fixed = withLocalPlayback(
        venue([offlineBar]), (zoneId: 'bar', status: ZoneStatus.auto));

    expect(fixed.zones.single.status, ZoneStatus.auto);
    expect(fixed.worstStatus, ZoneStatus.auto);
  });

  test('the "Offline" detail string does not survive onto the fixed row', () {
    // Zone.copyWith keeps statusDetail for any non-auto status, which would
    // leave the literal word "Offline" as an amber row's countdown text.
    final fixed = withLocalPlayback(
        venue([offlineBar]), (zoneId: 'bar', status: ZoneStatus.offSchedule));

    expect(fixed.zones.single.status, ZoneStatus.offSchedule);
    expect(fixed.zones.single.statusDetail, isNull);
  });

  test('a manually held room stays amber rather than flattening to quiet', () {
    // offSchedule is the server's own answer to "is a human holding this
    // room", and it is what `offline` was masking. Playing it locally proves
    // reachability, not that nobody is overriding it.
    final fixed = withLocalPlayback(
        venue([offlineBar]), (zoneId: 'bar', status: ZoneStatus.offSchedule));

    expect(fixed.worstStatus, ZoneStatus.offSchedule);
  });

  test('other zones are left alone', () {
    // First-hand evidence covers one room. A venue on another iPad may be
    // genuinely unreachable, and turning every red row green would replace one
    // wrong answer with a more confident wrong answer.
    const otherOffline = Zone(
        id: 'terrace',
        name: 'Terrace',
        status: ZoneStatus.offline,
        moodId: 'peak');

    final fixed = withLocalPlayback(venue([offlineBar, otherOffline]),
        (zoneId: 'bar', status: ZoneStatus.auto));

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
            withLocalPlayback(
                original, (zoneId: 'bar', status: ZoneStatus.offSchedule)),
            original),
        isTrue);
  });

  test('statusOf corrects only the matching zone', () {
    expect(statusOf(offlineBar, (zoneId: 'bar', status: ZoneStatus.auto)),
        ZoneStatus.auto);
    expect(statusOf(offlineBar, (zoneId: 'other', status: ZoneStatus.auto)),
        ZoneStatus.offline);
    expect(statusOf(offlineBar, null), ZoneStatus.offline);
  });
}
