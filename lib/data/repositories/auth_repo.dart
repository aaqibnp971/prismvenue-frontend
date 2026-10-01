import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../mock/mock_auth_repo.dart';
import '../models/session_context.dart';
import '../models/user.dart';

/// Everything a successful sign-in establishes.
///
/// Tokens are deliberately absent: the repository persists them itself, so
/// they never travel through the widget layer. A screen cannot leak or
/// mishandle a credential it was never handed.
class AuthSession {
  const AuthSession({required this.user, required this.context});

  final User user;
  final SessionContext context;
}

/// Auth boundary — front-end only (§Target): async so the FastAPI backend
/// slots in behind the same interface.
///
/// Two signatures changed when the backend landed, both deliberately:
///
/// * [verifyResetCode] now RETURNS a token, and [saveNewPassword] REQUIRES it.
///   As originally specified, save-password took `{email, password}` with no
///   evidence the emailed code had ever been seen — anyone able to reach the
///   API could set anyone's password. INTEGRATION_PLAN.md §5.1.
/// * [signIn] returns an [AuthSession] rather than a bare `User`, because the
///   session also carries which venue/zone the app operates on (§4.1).
///
/// Two methods are new: [restoreSession] and [signOut], for token persistence
/// across launches — the gap `BACKEND_INTEGRATION.md` §4 flagged.
abstract class AuthRepo {
  /// S00-1: "the backend lands the user in their role".
  Future<AuthSession> signIn(String email, String password);

  /// S00-2: email a 6-digit verification code.
  Future<void> sendResetCode(String email);

  /// S00-3: verify the entered code.
  ///
  /// Returns a short-lived, single-use token proving the code was seen. Pass
  /// it to [saveNewPassword]; without it the reset cannot complete.
  Future<String> verifyResetCode(String email, String code);

  /// S00-4: set the new password, then back to sign-in.
  Future<void> saveNewPassword({
    required String email,
    required String password,
    required String resetToken,
  });

  /// Rehydrate from a stored token on launch. Null when there is no usable
  /// session — no token, expired beyond refresh, or the account lost access.
  Future<AuthSession?> restoreSession();

  /// Discard stored credentials. Safe to call when already signed out.
  Future<void> signOut();

  /// Change the signed-in user's password (finding #17).
  ///
  /// [currentPassword] is required and really is checked — a venue iPad is a
  /// shared device left unlocked on a counter, and a bearer token alone must
  /// not be enough to take an account from its owner.
  ///
  /// Throws `wrong_password` (422) when it does not match.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

final authRepoProvider = Provider<AuthRepo>((ref) => MockAuthRepo());
