import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the session token lives between launches.
///
/// `BACKEND_INTEGRATION.md` §4 called this out as the one gap that forces a
/// change outside the repositories: the app had no token storage at all, so a
/// restart signed the user out. Venue staff keep this open on an iPad for a
/// whole shift — that had to be fixed before anything else could rely on auth.
///
/// Abstract on purpose. Secure storage needs a platform channel, which widget
/// tests do not have; [InMemoryTokenStore] lets the suite exercise the same
/// code paths without one.
abstract class TokenStore {
  Future<String?> readAccessToken();
  Future<String?> readRefreshToken();
  Future<void> write({required String accessToken, required String refreshToken});
  Future<void> clear();
}

/// Backed by the platform keystore — Keychain on iOS/macOS, EncryptedSharedPreferences
/// on Android, WebCrypto-wrapped localStorage on web.
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _accessKey = 'prism.access_token';
  static const _refreshKey = 'prism.refresh_token';

  final FlutterSecureStorage _storage;

  /// Last-written tokens, held for this launch only.
  ///
  /// The keystore is the durable copy; this is the fallback for when it refuses
  /// us. On macOS it always does: `flutter_secure_storage` uses the
  /// data-protection Keychain, which returns -34018 `errSecMissingEntitlement`
  /// unless the app is signed with a development certificate AND carries a
  /// `keychain-access-groups` entitlement — and the stock project is ad-hoc
  /// signed, so it is not.
  ///
  /// Without this cache the failure is worse than it looks: sign-in appears to
  /// succeed, but [readAccessToken] then returns null, so `ApiClient` attaches
  /// no `Authorization` header and every subsequent request 401s.
  String? _memAccess;
  String? _memRefresh;

  @override
  Future<String?> readAccessToken() => _read(_accessKey);

  @override
  Future<String?> readRefreshToken() => _read(_refreshKey);

  /// A keystore read can throw — a wiped Android keystore after a restore, or
  /// a browser with storage blocked. Treating that as "no token" signs the
  /// user in again, which is recoverable. Letting it throw would break launch.
  Future<String?> _read(String key) async {
    try {
      final stored = await _storage.read(key: key);
      if (stored != null) return stored;
    } catch (_) {
      // Fall through to the in-memory copy.
    }
    return key == _accessKey ? _memAccess : _memRefresh;
  }

  /// Caches in memory FIRST, then tries to persist.
  ///
  /// The order matters. A keystore write can throw for the same reasons a read
  /// can, plus the macOS entitlement case described on [_memAccess]. Letting it
  /// throw turned a perfectly good sign-in into "Something went wrong. Try
  /// again." with no way past it; swallowing it without the cache was worse
  /// still — sign-in looked fine and then every authenticated request 401'd.
  ///
  /// Caching first means the session is always live for this launch. All that
  /// a keystore failure costs is being remembered across a restart, which is
  /// exactly the "sign in again, recoverable" case [_read] already accepts.
  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    _memAccess = accessToken;
    _memRefresh = refreshToken;
    try {
      await _storage.write(key: _accessKey, value: accessToken);
      await _storage.write(key: _refreshKey, value: refreshToken);
    } catch (_) {
      // In memory is enough to finish this session.
    }
  }

  @override
  Future<void> clear() async {
    // Drop the cache first: sign-out must hold even if the keystore delete fails.
    _memAccess = null;
    _memRefresh = null;
    try {
      await _storage.delete(key: _accessKey);
      await _storage.delete(key: _refreshKey);
    } catch (_) {
      // Nothing useful to do; the token is unusable either way.
    }
  }
}

/// For tests and for `--dart-define=PRISM_USE_MOCKS=true`.
class InMemoryTokenStore implements TokenStore {
  String? _access;
  String? _refresh;

  @override
  Future<String?> readAccessToken() async => _access;

  @override
  Future<String?> readRefreshToken() async => _refresh;

  @override
  Future<void> write({
    required String accessToken,
    required String refreshToken,
  }) async {
    _access = accessToken;
    _refresh = refreshToken;
  }

  @override
  Future<void> clear() async {
    _access = null;
    _refresh = null;
  }
}
