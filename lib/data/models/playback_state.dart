/// What the room is playing right now — Floor hero (§2 S01-1/S01-2).
class PlaybackState {
  const PlaybackState({
    required this.moodId,
    required this.paused,
    this.pausedBy,
    required this.contextLine,
    this.offSchedule = false,
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

  PlaybackState copyWith({
    String? moodId,
    bool? paused,
    String? pausedBy,
    String? contextLine,
    bool? offSchedule,
  }) {
    return PlaybackState(
      moodId: moodId ?? this.moodId,
      paused: paused ?? this.paused,
      pausedBy: paused == false ? null : (pausedBy ?? this.pausedBy),
      contextLine: contextLine ?? this.contextLine,
      offSchedule: offSchedule ?? this.offSchedule,
    );
  }
}
