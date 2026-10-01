/// The device's own copy of the plan, so a room keeps playing when the
/// internet does not.
///
/// ## Why this exists
///
/// Finding #7. The schedule ran **only** on the server: migration 010's
/// `pg_cron` job writes `zone_state.desired_mood_id` every minute, and the app
/// learns what to play by reading `/zones/{id}/now`. Nothing was kept on the
/// tablet. So when a venue's internet dropped, the room held whatever mood it
/// was on for the rest of the day, and if the tablet restarted before the
/// router came back — a power cut, the commonest case — it came up with no
/// mood at all and the room stayed silent until the connection returned.
///
/// A venue cannot tell the difference between "the music stopped because the
/// Wi-Fi went" and "the music stopped". It is the same failure either way.
///
/// ## What is cached, and what deliberately is not
///
/// The recurring weekly plan, the venue's everyday open hours, the venue's
/// current UTC offset, and the last state the server described. That is enough
/// to answer the only two questions the room needs while offline: *is the
/// venue open* and *what should be playing*.
///
/// Not cached:
///
///   * **Open-hours exceptions.** A one-off closure is a fact the venue knows
///     and the tablet does not need to guess at; getting it wrong in the
///     conservative direction (playing on a day the venue is shut) is a room
///     with nobody in it, and in the other direction it is a room with people
///     in it and no music, which is worse. Everyday hours cover the shape of
///     almost every week.
///   * **Week forks.** A "just this week" plan is by definition temporary and
///     recent; falling back to the recurring plan during an outage is the
///     behaviour a manager would expect if asked.
///   * **Takeover and pause.** Both are things a person did, and the last
///     known state carries them. Neither is something to infer.
///
/// ## The offset, and why it is a number rather than a zone name
///
/// Dart has no IANA timezone database, so `Asia/Kolkata` is a string the
/// device cannot turn into a wall clock — the same reason `POST /venues` sends
/// two UTC offsets rather than a zone name. What is cached instead is the
/// venue's offset **as it stood when the cache was written**, computed from
/// `/today`'s `venue_time` against the device's own clock.
///
/// That is exact until the venue crosses a DST boundary while offline, when it
/// is an hour out. Accepted deliberately: the alternative is bundling a zone
/// database that goes stale every year (the same argument that keeps the
/// timezone picker reading `pg_timezone_names`), and an hour of drift during a
/// multi-day outage that happens to span the last Sunday in March is a smaller
/// failure than a silent room.
library;

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/guardrails.dart';
import '../models/playback_state.dart';
import '../models/schedule_entry.dart';

/// One block of the plan, flattened to what scheduling actually needs.
class OfflineBlock {
  const OfflineBlock({
    required this.dayIndex,
    required this.startMinutes,
    required this.endMinutes,
    required this.moodId,
  });

  /// 0 = Monday … 6 = Sunday, matching [Daypart.dayIndex] and `dayparts.day`.
  final int dayIndex;

  /// Minutes past midnight, venue-local. The only comparable form — an
  /// hour-only comparison reads 6:30–7:00 as zero-length.
  final int startMinutes;
  final int endMinutes;

  final String moodId;

  Map<String, dynamic> toJson() => {
        'd': dayIndex,
        's': startMinutes,
        'e': endMinutes,
        'm': moodId,
      };

  static OfflineBlock fromJson(Map<String, dynamic> json) => OfflineBlock(
        dayIndex: json['d'] as int,
        startMinutes: json['s'] as int,
        endMinutes: json['e'] as int,
        moodId: json['m'] as String,
      );

  static OfflineBlock fromDaypart(Daypart d) => OfflineBlock(
        dayIndex: d.dayIndex,
        startMinutes: d.startMinutesOfDay,
        endMinutes: d.endMinutesOfDay,
        moodId: d.moodId,
      );
}

/// Everything the device needs to run one zone by itself.
class OfflinePlan {
  const OfflinePlan({
    this.blocks = const [],
    this.venueOffsetMinutes = 0,
    this.openMinutes,
    this.closeMinutes,
    this.selfDrive = false,
    this.lastMoodId,
    this.lastPaused = false,
    this.lastPlayerInstallationId,
    this.capturedAt,
  });

  final List<OfflineBlock> blocks;

  /// The venue's offset from UTC, in minutes, as it stood at [capturedAt].
  final int venueOffsetMinutes;

  /// Everyday open hours as minutes past midnight, or null when the venue
  /// keeps none. Absent hours mean open, never closed — the same reading the
  /// server takes, and for the same reason: inferring silence from missing
  /// data takes rooms off the air for a setup step nobody knew about.
  final int? openMinutes;
  final int? closeMinutes;

  /// When true the saved plan is deliberately not running (S03-1), so the
  /// offline scheduler must not run it either. Getting this backwards would
  /// have an offline tablet start following a plan the venue switched off.
  final bool selfDrive;

  final String? lastMoodId;
  final bool lastPaused;
  final String? lastPlayerInstallationId;
  final DateTime? capturedAt;

  bool get isUsable => lastMoodId != null || blocks.isNotEmpty;

  /// The venue's wall clock for a given instant.
  DateTime venueLocal(DateTime utcNow) =>
      utcNow.toUtc().add(Duration(minutes: venueOffsetMinutes));

  /// Whether the venue is shut right now.
  ///
  /// Mirrors `app.venue_open_window`: a window whose close is before its open
  /// wraps past midnight, and open == close means open around the clock.
  bool closedAt(DateTime utcNow) {
    final open = openMinutes;
    final close = closeMinutes;
    if (open == null || close == null) return false;
    final local = venueLocal(utcNow);
    final now = local.hour * 60 + local.minute;
    if (open == close) return false;
    final isOpen =
        close < open ? (now >= open || now < close) : (now >= open && now < close);
    return !isOpen;
  }

  /// What the plan says should be playing, or null when nothing covers this
  /// moment.
  ///
  /// Mirrors `app.scheduled_mood_for`: `start <= now < end`, a block whose end
  /// is at or before its start wraps past midnight, and where two blocks
  /// overlap the later start wins. Null is a real answer — migration 010
  /// deliberately holds the last mood through a gap rather than snapping the
  /// room to silence, and so does the caller.
  String? moodAt(DateTime utcNow) {
    if (selfDrive) return null;
    final local = venueLocal(utcNow);
    // Dart's DateTime.weekday is 1 = Monday … 7 = Sunday.
    final today = local.weekday - 1;
    final yesterday = (today + 6) % 7;
    final now = local.hour * 60 + local.minute;

    OfflineBlock? best;
    for (final b in blocks) {
      final wraps = b.endMinutes <= b.startMinutes;
      final bool covers;
      if (b.dayIndex == today) {
        covers = wraps
            ? now >= b.startMinutes
            : now >= b.startMinutes && now < b.endMinutes;
      } else if (wraps && b.dayIndex == yesterday) {
        // A block that began yesterday and runs past midnight is still the one
        // in charge at 01:00 today.
        covers = now < b.endMinutes;
      } else {
        covers = false;
      }
      if (!covers) continue;
      if (best == null || b.startMinutes > best.startMinutes) best = b;
    }
    return best?.moodId;
  }

  Map<String, dynamic> toJson() => {
        'blocks': [for (final b in blocks) b.toJson()],
        'offset': venueOffsetMinutes,
        'open': openMinutes,
        'close': closeMinutes,
        'self_drive': selfDrive,
        'mood': lastMoodId,
        'paused': lastPaused,
        'player': lastPlayerInstallationId,
        'at': capturedAt?.toUtc().toIso8601String(),
      };

  static OfflinePlan fromJson(Map<String, dynamic> json) => OfflinePlan(
        blocks: [
          for (final raw in (json['blocks'] as List? ?? const []))
            OfflineBlock.fromJson((raw as Map).cast<String, dynamic>()),
        ],
        venueOffsetMinutes: json['offset'] as int? ?? 0,
        openMinutes: json['open'] as int?,
        closeMinutes: json['close'] as int?,
        selfDrive: json['self_drive'] as bool? ?? false,
        lastMoodId: json['mood'] as String?,
        lastPaused: json['paused'] as bool? ?? false,
        lastPlayerInstallationId: json['player'] as String?,
        capturedAt: DateTime.tryParse(json['at'] as String? ?? ''),
      );

  OfflinePlan copyWith({
    List<OfflineBlock>? blocks,
    int? venueOffsetMinutes,
    int? openMinutes,
    int? closeMinutes,
    bool? selfDrive,
    String? lastMoodId,
    bool? lastPaused,
    String? lastPlayerInstallationId,
    DateTime? capturedAt,
    bool clearHours = false,
  }) =>
      OfflinePlan(
        blocks: blocks ?? this.blocks,
        venueOffsetMinutes: venueOffsetMinutes ?? this.venueOffsetMinutes,
        openMinutes: clearHours ? null : (openMinutes ?? this.openMinutes),
        closeMinutes: clearHours ? null : (closeMinutes ?? this.closeMinutes),
        selfDrive: selfDrive ?? this.selfDrive,
        lastMoodId: lastMoodId ?? this.lastMoodId,
        lastPaused: lastPaused ?? this.lastPaused,
        lastPlayerInstallationId:
            lastPlayerInstallationId ?? this.lastPlayerInstallationId,
        capturedAt: capturedAt ?? this.capturedAt,
      );

  /// What to play right now, with no server to ask.
  ///
  /// [thisInstallation] decides `playsHere` the same way the API mapper does,
  /// from the claim recorded when the connection was last up: a tablet that
  /// was driving the room keeps driving it, and one that was not stays quiet.
  /// Finding #2's rule does not lapse because the Wi-Fi did.
  PlaybackState? stateAt(DateTime utcNow, String? thisInstallation) {
    final mood = moodAt(utcNow) ?? lastMoodId;
    if (mood == null) return null;
    return PlaybackState(
      moodId: mood,
      paused: lastPaused,
      // Named after the state, not after a person: nobody paused it since.
      pausedBy: null,
      // Left empty rather than carried forward. The context line describes the
      // room as the server saw it, and while offline nobody is seeing it.
      contextLine: '',
      offSchedule: false,
      playerInstallationId: lastPlayerInstallationId,
      playsHere: lastPlayerInstallationId != null &&
          lastPlayerInstallationId == thisInstallation,
      closed: closedAt(utcNow),
      // Deliberately null. "Opens 7am" is the server's formatting of the
      // venue's own hours; re-deriving it here is a second spelling of the
      // same fact waiting to disagree with the first.
      opensLabel: null,
      quietCapPct: null,
    );
  }
}

/// Reads and writes [OfflinePlan]s, one per zone, in shared_preferences.
///
/// Keyed by zone because a venue iPad can be repointed at another room
/// (`operateZone`), and two rooms have two plans — the same split the schema
/// has and the same one `ApiScope` enforces everywhere else.
class OfflinePlanCache {
  OfflinePlanCache({SharedPreferences? prefs}) : _prefs = prefs;

  static const _prefix = 'prism.offline_plan.';

  SharedPreferences? _prefs;
  final _memory = <String, OfflinePlan>{};

  Future<SharedPreferences> _store() async =>
      _prefs ??= await SharedPreferences.getInstance();

  /// The cached plan, or null. Served from memory once read, because the
  /// now-playing fallback runs on a 5-second poll and must not touch the disk
  /// on every tick.
  Future<OfflinePlan?> read(String zoneId) async {
    final held = _memory[zoneId];
    if (held != null) return held;
    try {
      final raw = (await _store()).getString('$_prefix$zoneId');
      if (raw == null) return null;
      final plan =
          OfflinePlan.fromJson((jsonDecode(raw) as Map).cast<String, dynamic>());
      return _memory[zoneId] = plan;
    } catch (_) {
      // A cache that cannot be read is a cache that is not there. Never a
      // reason to fail a room — the caller's fallback for "no cache" is
      // exactly the right behaviour here too.
      return null;
    }
  }

  /// The last plan read or written for [zoneId], without touching storage.
  OfflinePlan? peek(String zoneId) => _memory[zoneId];

  Future<void> write(String zoneId, OfflinePlan plan) async {
    _memory[zoneId] = plan;
    try {
      await (await _store())
          .setString('$_prefix$zoneId', jsonEncode(plan.toJson()));
    } catch (_) {
      // Held in memory regardless, which covers the outage that has already
      // started. Only a restart loses it.
    }
  }

  /// Records what the server just said, leaving the plan half alone.
  Future<void> rememberState(String zoneId, PlaybackState state) async {
    final held = await read(zoneId) ?? const OfflinePlan();
    await write(
      zoneId,
      held.copyWith(
        lastMoodId: state.moodId,
        lastPaused: state.paused,
        lastPlayerInstallationId: state.playerInstallationId,
        capturedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Records the plan half, leaving the last-known state alone.
  Future<void> rememberPlan(
    String zoneId, {
    required List<Daypart> plan,
    required bool selfDrive,
    OpenHours? hours,
    int? venueOffsetMinutes,
  }) async {
    final held = await read(zoneId) ?? const OfflinePlan();
    await write(
      zoneId,
      held.copyWith(
        blocks: [for (final d in plan) OfflineBlock.fromDaypart(d)],
        selfDrive: selfDrive,
        openMinutes: hours?.openMinutes,
        closeMinutes: hours?.closeMinutes,
        venueOffsetMinutes: venueOffsetMinutes,
        capturedAt: DateTime.now().toUtc(),
      ),
    );
  }

  /// Signing out on a shared venue iPad clears it, like the operated zone —
  /// what a room plays is not the next person's business.
  Future<void> clear() async {
    _memory.clear();
    try {
      final store = await _store();
      for (final key in store.getKeys().where((k) => k.startsWith(_prefix))) {
        await store.remove(key);
      }
    } catch (_) {
      // Memory is already clear, which is what this process will read.
    }
  }
}

/// The venue's UTC offset in minutes, from `/today`'s "HH:MM" wall clock.
///
/// Returns null when the server did not send one — never the device's own
/// offset, which is the exact confusion `venue_time` exists to name.
int? venueOffsetFrom(String? venueTime, {DateTime? now}) {
  if (venueTime == null) return null;
  final parts = venueTime.split(':');
  if (parts.length < 2) return null;
  final hour = int.tryParse(parts[0]);
  final minute = int.tryParse(parts[1]);
  if (hour == null || minute == null) return null;

  final utc = (now ?? DateTime.now()).toUtc();
  final utcMinutes = utc.hour * 60 + utc.minute;
  var delta = (hour * 60 + minute) - utcMinutes;
  // Wrap to (-12h, +14h], the range real offsets live in. The venue's clock
  // and UTC can be on different calendar days, so a raw subtraction is out by
  // a whole day half the time.
  if (delta > 14 * 60) delta -= 24 * 60;
  if (delta <= -12 * 60) delta += 24 * 60;
  // To the nearest minute: `venue_time` has no seconds, so the reading is
  // already truncated and the residue is noise.
  return delta;
}
