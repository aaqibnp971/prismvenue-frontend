import '../models/session_context.dart';
import '../api/api_exception.dart';
import '../repositories/auth_repo.dart';
import 'seed.dart';

/// In-memory auth. Any credentials succeed (failed sign-in is undesigned,
/// §6-B1). The role the "backend" lands the user in is mocked off the email
/// so all three journeys are reachable from the real sign-in screen:
/// *floor*@… → floor staff, *owner*/*arjun*@… → owner, anything else →
/// manager (Priya — "you're a manager", S05-1).
///
/// Kept in the tree deliberately: the widget suite runs against it, and it
/// doubles as executable documentation of the shapes the API must produce.
class MockAuthRepo implements AuthRepo {
  /// Zero: loading states are undesigned (§6-B1), so the mock resolves
  /// instantly; the real backend replaces this behind the same interface.
  static const _latency = Duration.zero;

  /// The mock's venue/zone context. Ids match MockVenueRepo's seed so the
  /// zone-scoped repositories resolve against the same fixtures.
  static const _context = SessionContext(
    venueId: Seed.managerVenueId,
    venueName: Seed.venueName,
    zoneId: Seed.managerZoneId,
    zoneName: Seed.zoneName,
  );

  bool _signedOut = false;

  @override
  Future<AuthSession> signIn(String email, String password) async {
    await Future<void>.delayed(_latency);
    _signedOut = false;
    final e = email.toLowerCase();
    final user = e.contains('floor')
        ? Seed.floorUser
        : (e.contains('owner') || e.contains('arjun'))
            ? Seed.ownerUser
            : Seed.managerUser;
    return AuthSession(user: user, context: _context);
  }

  @override
  Future<void> sendResetCode(String email) => Future.delayed(_latency);

  @override
  Future<String> verifyResetCode(String email, String code) async {
    await Future<void>.delayed(_latency);
    // A stand-in for the real proof-of-verification token; the mock accepts
    // any code, so it always succeeds.
    return 'mock-reset-token';
  }

  @override
  Future<void> saveNewPassword({
    required String email,
    required String password,
    required String resetToken,
  }) =>
      Future.delayed(_latency);

  /// The mock has no persistence, so a "restart" is always signed out. Tests
  /// that want a signed-in start call [signIn] through the real S00-1 screen.
  @override
  Future<AuthSession?> restoreSession() async => null;

  @override
  /// Any non-empty current password is accepted, except the literal "wrong",
  /// which exists so the screen can be walked through its failure state
  /// without a server.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (currentPassword == 'wrong') {
      throw const ApiException(
        statusCode: 422,
        code: 'wrong_password',
        message: 'That is not your current password.',
        field: 'current_password',
      );
    }
  }

  @override
  Future<void> signOut() async => _signedOut = true;

  /// Exposed for tests that assert sign-out reached the repository.
  bool get signedOut => _signedOut;
}
