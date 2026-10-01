import 'dart:ui';

import '../../app/roles.dart';
import '../models/session_context.dart';
import '../models/user.dart';
import '../repositories/auth_repo.dart';
import 'api_client.dart';
import 'api_exception.dart';
import 'token_store.dart';

/// `AuthRepo` against the real API.
///
/// The token this receives from `POST /auth/sign-in` is the Supabase access
/// token — FastAPI proxies Supabase Auth rather than minting its own
/// (INTEGRATION_PLAN.md §5.4). That is what makes `auth.uid()` resolve
/// server-side, which is what makes every row-level security policy work. The
/// app does not need to know any of that; it just stores and sends it.
class ApiAuthRepo implements AuthRepo {
  ApiAuthRepo(this._client, this._tokens);

  final ApiClient _client;
  final TokenStore _tokens;

  @override
  Future<AuthSession> signIn(String email, String password) async {
    final json = await _client.postPublic(
      '/auth/sign-in',
      body: {'email': email, 'password': password},
    ) as Map<String, dynamic>;

    await _tokens.write(
      accessToken: json['token'] as String,
      refreshToken: json['refresh_token'] as String? ?? '',
    );

    return _sessionFrom(json);
  }

  @override
  Future<void> sendResetCode(String email) async {
    await _client.postPublic('/auth/reset/send-code', body: {'email': email});
  }

  @override
  Future<String> verifyResetCode(String email, String code) async {
    final json = await _client.postPublic(
      '/auth/reset/verify',
      body: {'email': email, 'code': code},
    ) as Map<String, dynamic>;
    return json['reset_token'] as String;
  }

  @override
  Future<void> saveNewPassword({
    required String email,
    required String password,
    required String resetToken,
  }) async {
    await _client.postPublic(
      '/auth/reset/save-password',
      body: {
        'email': email,
        'password': password,
        // Proof the emailed code was verified. Without it the server refuses —
        // that is the whole point of the §5.1 change.
        'reset_token': resetToken,
      },
    );
  }

  @override
  Future<AuthSession?> restoreSession() async {
    final token = await _tokens.readAccessToken();
    if (token == null || token.isEmpty) return null;

    try {
      final json = await _client.get('/auth/me') as Map<String, dynamic>;
      return _sessionFrom(json);
    } on ApiException catch (e) {
      // 401 means the token is dead and refresh already failed inside the
      // client — start signed out. Anything else (offline, server down) is
      // also not a session we can trust, and the app has no offline mode.
      if (e.isUnauthorized) await _tokens.clear();
      return null;
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.post('/auth/change-password', body: {
      'current_password': currentPassword,
      'new_password': newPassword,
    });
  }

  @override
  Future<void> signOut() => _tokens.clear();

  AuthSession _sessionFrom(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>;
    return AuthSession(
      user: User(
        id: user['id'] as String,
        name: user['name'] as String,
        role: _roleFrom(user['role'] as String),
        initials: user['initials'] as String,
        email: json['email'] as String?,
      avatarColor: _colorFrom(user['avatar_color'] as String?),
      ),
      context: SessionContext.fromJson(
        (json['context'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }

  /// The contract guarantees exactly `floor | manager | owner`, so there is no
  /// mapping layer — but an unrecognised value must not crash the app on the
  /// sign-in screen. Falling back to the least-privileged role fails safe: a
  /// user briefly seeing too little is recoverable, seeing too much is not.
  static Role _roleFrom(String raw) => switch (raw) {
        'owner' => Role.owner,
        'manager' => Role.manager,
        _ => Role.floor,
      };

  static Color _colorFrom(String? hex) {
    if (hex == null) return const Color(0xFF84C44A);
    final value = int.tryParse(hex.replaceFirst('#', ''), radix: 16);
    if (value == null) return const Color(0xFF84C44A);
    return Color(0xFF000000 | value);
  }
}
