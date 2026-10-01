/// One line of a zone's recent activity — finding #15.
///
/// An owner finds a room paused and cannot tell who paused it, or when.
/// `zone_state.desired_updated_by` only ever held the LATEST writer, so the
/// answer was overwritten by whoever next changed anything — usually the
/// per-minute scheduler. Migration 020's trigger keeps the history instead.
class ZoneActivityEntry {
  const ZoneActivityEntry({
    required this.id,
    required this.at,
    required this.line,
    this.actorName,
    this.byPrism = false,
    this.moodId,
  });

  final String id;

  /// When it happened. A timestamp, not a phrase — "12 minutes ago" is only
  /// true at the moment it is written, and this panel can sit on screen for a
  /// whole shift. Rendered through [lastSeenLabel] at build time, against the
  /// reader's own clock.
  final DateTime at;

  /// The sentence, composed server-side and rendered verbatim.
  ///
  /// Same rule as `hours_label` and `range_label`: the phrasing depends on the
  /// mood catalogue and the mode vocabulary, both of which live in the backend,
  /// and two spellings of "Priya switched to Peak" is a bug waiting to happen.
  final String line;

  /// Who did it, or null when Prism did.
  final String? actorName;

  /// Whether this was Prism itself rather than a person — migration 010's
  /// scheduler or 012's takeover sweep.
  ///
  /// Not derived from a null [actorName]: a person whose profile has no display
  /// name is still a person, and crediting them to the scheduler would make the
  /// log say the opposite of the truth.
  final bool byPrism;

  /// The mood it changed to, for the dot beside the line. Null when the mood
  /// did not change — a pause has no new mood to show.
  final String? moodId;
}
