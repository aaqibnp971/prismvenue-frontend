/// What the room is playing right now — Floor hero (§2 S01-1/S01-2).
class PlaybackState {
  const PlaybackState({
    required this.moodId,
    required this.paused,
    this.pausedBy,
    required this.contextLine,
    this.offSchedule = false,
    this.playerInstallationId,
    this.playsHere = true,
    this.closed = false,
    this.opensLabel,
    this.quietCapPct,
  });

  /// References the fixed 6-mood set (theme/moods.dart).
  final String moodId;

  /// S01-2: room paused by staff; hero shows play icon, tile eq freezes.
  final bool paused;

  /// First name shown in the paused pill ("Paused by Priya · …").
  final String? pausedBy;

  /// Hero context line, e.g. "mid-afternoon · ~60% full · clear".
  final String contextLine;

  /// True when a human has overridden the plan — a mood tapped here, or on
  /// another iPad. Server-side this is `zone_state.desired_mode == 'manual'`
  /// (and, while paused, `desired_mode_before_pause == 'manual'`).
  ///
  /// Deliberately a plain bool with no deadline attached. The Venues screens
  /// show "auto in 42 min", but that string is a mock seed with no server
  /// source (INTEGRATION_PLAN.md flags it MISSING), so promising a countdown
  /// here would be inventing one.
  final bool offSchedule;

  /// Which installation is driving this room, or null if none is.
  ///
  /// Finding #2: the engine used to play wherever somebody was signed in, so
  /// an owner opening the app at home started their clinic's music on their
  /// phone, and two iPads in one room played over each other a few hundred
  /// milliseconds apart.
  ///
  /// Null is a real and common state, not a gap — a room nobody has claimed
  /// plays nowhere. The Floor screen has to say so out loud, because a room
  /// that is silent for a reason nobody can see is the failure this whole
  /// product exists to avoid.
  final String? playerInstallationId;

  /// Whether THIS device is the one driving the room.
  ///
  /// Resolved in the API mapper rather than here, because the comparison needs
  /// the installation id out of local storage and the engine needs the answer
  /// synchronously. [playerInstallationId] is kept alongside so the UI can
  /// tell "somebody else is playing it" from "nobody is".
  ///
  /// Defaults to true so the mocks — and every test built on them — behave as
  /// they did before a claim existed. The API mapper always sets it
  /// explicitly, so the default is never what a real venue reads.
  final bool playsHere;

  /// The venue is outside its open hours, or closed all day by an exception.
  ///
  /// Finding #4: a clinic closing at 7pm kept playing Wind-down all night.
  /// Server-computed from the venue's own clock, so a device in another
  /// timezone cannot disagree with it — the same reason `venue_time` is sent
  /// rather than derived here.
  final bool closed;

  /// When it opens again, pre-formatted server-side ("7am"). Null when the
  /// venue is open, or keeps no hours at all.
  final String? opensLabel;

  /// The ceiling quiet hours imposes right now, or null outside them.
  ///
  /// Finding #5. Server-computed against the venue's clock, like [closed], so
  /// a tablet in another timezone cannot disagree about when night is.
  final int? quietCapPct;

  PlaybackState copyWith({
    String? moodId,
    bool? paused,
    String? pausedBy,
    String? contextLine,
    bool? offSchedule,
    String? playerInstallationId,
    bool? playsHere,
    bool? closed,
    String? opensLabel,
    int? quietCapPct,
  }) {
    return PlaybackState(
      moodId: moodId ?? this.moodId,
      paused: paused ?? this.paused,
      pausedBy: paused == false ? null : (pausedBy ?? this.pausedBy),
      contextLine: contextLine ?? this.contextLine,
      offSchedule: offSchedule ?? this.offSchedule,
      playerInstallationId: playerInstallationId ?? this.playerInstallationId,
      playsHere: playsHere ?? this.playsHere,
      closed: closed ?? this.closed,
      opensLabel: opensLabel ?? this.opensLabel,
      quietCapPct: quietCapPct ?? this.quietCapPct,
    );
  }
}
