import 'api_exception.dart';

/// Resolves "which zone / venue is this repository acting on?".
///
/// The Flutter repository interfaces are not zone-scoped —
/// `watchNowPlaying()`, `watchGuardrails()` and friends take no arguments —
/// while every endpoint is `/v1/zones/{id}/…`. Rather than change thirty
/// signatures and every screen that calls them, the API repositories resolve
/// the id here, at call time, from the session.
///
/// Read at call time rather than captured at construction on purpose: a future
/// zone picker only has to update the session, and every repository follows.
///
/// It also answers "whose data is this?", which is what the [Watchable] cache
/// keys below are for.
class ApiScope {
  const ApiScope({
    required this.zoneId,
    required this.venueId,
    required this.userId,
  });

  final String? Function() zoneId;
  final String? Function() venueId;

  /// The signed-in account. Not used to build a URL — every endpoint infers the
  /// caller from the bearer token — only to key caches.
  final String? Function() userId;

  /// Cache keys for [Watchable]. Every one of them carries the account, so a
  /// cached value can never outlive the session it was fetched for.
  ///
  /// The venue list is the case that made this necessary: it is scoped to the
  /// account rather than to a room, so it had no key at all and survived a
  /// sign-out. Signing in as somebody else showed the previous account's
  /// venues until some mutation happened to call `refresh()`.
  ///
  /// The account also has to be part of the zone and venue keys, not just its
  /// own. Two accounts can each be sitting on a venue with no zones — S05-5
  /// makes that reachable — and a bare zone key would then be null on both
  /// sides of the switch, match, and serve one account the other's room.
  String zoneKey() => _key(zoneId());
  String venueKey() => _key(venueId());

  /// For data that belongs to the whole account rather than to one room.
  String accountKey() => _key(null);

  String _key(String? id) => '${userId() ?? '-'}/${id ?? '-'}';

  String requireZone() {
    final id = zoneId();
    if (id == null || id.isEmpty) throw _missing('zone');
    return id;
  }

  String requireVenue() {
    final id = venueId();
    if (id == null || id.isEmpty) throw _missing('venue');
    return id;
  }

  /// Reachable in one real case: a venue whose last zone was removed via S05-5.
  /// Surfacing it as a normal API error means the existing error handling shows
  /// it, rather than a null-check crashing the screen.
  ApiException _missing(String what) => ApiException(
        statusCode: 0,
        code: 'no_${what}_selected',
        message: what == 'zone'
            ? 'This venue has no zones yet.'
            : 'No venue is selected.',
      );
}
