import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models/session_context.dart';
import '../data/models/user.dart';
import '../data/repositories/auth_repo.dart';

/// Signed-in user; null = signed out. The router redirects on changes.
///
/// Every screen reads this and nothing else, which is why it stayed a plain
/// `User?` when the backend landed — seventeen call sites did not have to
/// change. Token handling lives in the repository, session coordination in
/// [AuthController].
final sessionProvider =
    NotifierProvider<SessionNotifier, User?>(SessionNotifier.new);

class SessionNotifier extends Notifier<User?> {
  @override
  User? build() => null;

  void set(User? user) => state = user;
}

/// Which venue/zone this session operates on. See [SessionContext].
final sessionContextProvider =
    NotifierProvider<SessionContextNotifier, SessionContext?>(
        SessionContextNotifier.new);

class SessionContextNotifier extends Notifier<SessionContext?> {
  @override
  SessionContext? build() => null;

  void set(SessionContext? context) => state = context;

  /// The zone picker's entry point — S04-1 "Open floor".
  ///
  /// Repoints every zone-scoped repository at another room: the providers
  /// watch [currentZoneIdProvider], so switching here refetches Floor,
  /// Schedule and Settings for the new zone. Venue fields travel too, so an
  /// owner opening a floor in a different venue switches whole-venue context
  /// (open hours, the top-bar name) along with the zone.
  ///
  /// In-memory only, like the rest of the session context: a reload lands
  /// back on the server's default zone from /auth/me.
  void operateZone({
    required String venueId,
    required String venueName,
    required String zoneId,
    required String zoneName,
  }) {
    final next = SessionContext(
      venueId: venueId,
      venueName: venueName,
      zoneId: zoneId,
      zoneName: zoneName,
    );
    state = next;
    // Remembered across relaunches. Without this the choice survived exactly as
    // long as the process: an iPad that reboots overnight — or a browser tab
    // reloaded — came back on whichever room /auth/me happens to call first,
    // silently pointing every screen and the speakers at a different venue than
    // the one the manager left it on.
    unawaited(_persist(ref.read(sessionProvider)?.id, next));
  }
}

// --- Remembering which room the app is pointed at ---------------------------

const _operatedZoneKey = 'prism.operated_zone';

/// The stored choice, read once before the first frame and injected by `main()`.
///
/// Seeded rather than loaded inside the notifier for the same reason
/// [initialThemeModeProvider] is: `Notifier.build()` is synchronous, so reading
/// storage there would mean showing the server's default venue and correcting
/// it a frame later — a visible flash of the wrong room's name on every launch.
final storedOperatedZoneProvider = Provider<StoredOperatedZone?>((ref) => null);

/// A remembered zone, plus **whose** it is.
///
/// The user id is not decoration. A venue iPad is a shared device, and staff
/// hand it over between shifts; without it, signing in as someone else would
/// inherit the previous person's room — possibly one this account cannot even
/// see, which fails as a 404 on every zone-scoped screen rather than as
/// anything a human could diagnose.
typedef StoredOperatedZone = ({String userId, SessionContext context});

/// Reads the persisted choice. Returns null on anything unexpected — storage
/// unavailable, a blob written by an older build, a browser with storage
/// blocked. Falling back to the server's default zone is always safe.
Future<StoredOperatedZone?> readStoredOperatedZone() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_operatedZoneKey);
    if (raw == null) return null;
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final userId = json['user_id'] as String?;
    final zoneId = json['zone_id'] as String?;
    // A stored context with no zone would point the app at nothing, which is
    // strictly worse than the server's default.
    if (userId == null || zoneId == null || zoneId.isEmpty) return null;
    return (userId: userId, context: SessionContext.fromJson(json));
  } catch (_) {
    return null;
  }
}

/// Fire-and-forget, like the theme: switching rooms must feel instant, and a
/// storage failure costs only being remembered across a restart.
Future<void> _persist(String? userId, SessionContext context) async {
  if (userId == null) return;
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _operatedZoneKey,
      jsonEncode({...context.toJson(), 'user_id': userId}),
    );
  } catch (_) {
    // In memory is enough for this launch.
  }
}

Future<void> _clearPersisted() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_operatedZoneKey);
  } catch (_) {
    // Nothing to do — the next sign-in overwrites it anyway.
  }
}

/// The zone every zone-scoped repository operates on.
///
/// A future zone picker sets [sessionContextProvider]; everything downstream
/// follows automatically because the repositories read this at call time
/// rather than capturing it at construction.
final currentZoneIdProvider =
    Provider<String?>((ref) => ref.watch(sessionContextProvider)?.zoneId);

final currentVenueIdProvider =
    Provider<String?>((ref) => ref.watch(sessionContextProvider)?.venueId);

/// Sign-in, sign-out and launch-time rehydration in one place.
///
/// User and context are two providers that must never disagree, so nothing
/// else is allowed to set them.
final authControllerProvider = Provider<AuthController>(AuthController.new);

class AuthController {
  AuthController(this._ref);

  final Ref _ref;

  /// Throws [ApiException] on failure — the screen decides what to show.
  Future<void> signIn(String email, String password) async {
    final session = await _ref.read(authRepoProvider).signIn(email, password);
    _apply(session);
  }

  /// Restore from a stored token. Never throws: a failed restore just means
  /// "start signed out", which the sign-in screen already handles.
  Future<void> restore() async {
    try {
      final session = await _ref.read(authRepoProvider).restoreSession();
      if (session != null) _apply(session);
    } catch (_) {
      // Deliberately swallowed. A launch must not fail because a token could
      // not be checked; the worst case is the user signs in again.
    }
  }

  /// Clears local state immediately so the router redirects on this frame,
  /// then discards the stored token. Order matters: awaiting first would leave
  /// the signed-in UI on screen while storage is written.
  Future<void> signOut() async {
    _ref.read(sessionProvider.notifier).set(null);
    _ref.read(sessionContextProvider.notifier).set(null);
    // Cleared on the way out, not kept for "next time": the next person to sign
    // in on this iPad is often a different person, and the user-id check in
    // [readStoredOperatedZone] should be a backstop rather than the only thing
    // standing between them and someone else's room.
    await _clearPersisted();
    await _ref.read(authRepoProvider).signOut();
  }

  void _apply(AuthSession session) {
    _ref.read(sessionContextProvider.notifier).set(_contextFor(session));
    // User last: the router listens to it, so context is already in place by
    // the time a redirect runs and a screen reads the current zone.
    _ref.read(sessionProvider.notifier).set(session.user);
  }

  /// The remembered room if it belongs to this user, otherwise the server's
  /// default.
  ///
  /// Not validated against the venue list here, and deliberately: doing so
  /// would mean a `/venues` fetch inside the capped launch restore, and the
  /// failure it would prevent is both rare and self-correcting. A zone that has
  /// since been removed (or that this account lost access to) 404s on the Floor
  /// screen, which renders its error state — and only managers and owners can
  /// ever have stored a zone, because reaching "Open floor" means reaching
  /// /venues, which the router denies floor staff. So the one person who can
  /// land here always has the tab that fixes it.
  SessionContext _contextFor(AuthSession session) {
    final stored = _ref.read(storedOperatedZoneProvider);
    if (stored == null || stored.userId != session.user.id) {
      return session.context;
    }
    return stored.context;
  }
}
