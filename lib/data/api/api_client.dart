import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'api_exception.dart';
import 'token_store.dart';

/// One HTTP client for the whole app.
///
/// Responsibilities, all of them cross-cutting enough that scattering them
/// through five repositories would guarantee inconsistency:
///
/// * attaches `Authorization: Bearer <token>` from [TokenStore]
/// * attaches `Idempotency-Key` to every state-changing POST, as the contract
///   requires — and reuses the same key when retrying, which is the entire
///   point of having one
/// * refreshes a expired token exactly once, then replays the request
/// * turns the API's error envelope into [ApiException]
///
/// It deliberately does NOT retry on network failure. Every mutation in this
/// app is a deliberate human action ("pause the room", "take over"); silently
/// re-sending those is worse than reporting the failure.
class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.tokens,
    http.Client? httpClient,
    this.onSessionLost,
  }) : _http = httpClient ?? http.Client();

  /// Includes the `/v1` prefix, no trailing slash.
  final String baseUrl;

  /// Called when the session cannot be recovered — expired token, failed
  /// refresh. The app signs out in response; the client itself does not know
  /// what signing out means.
  final void Function()? onSessionLost;

  /// Read on every request to attach the bearer token, and cleared when the
  /// session cannot be recovered.
  final TokenStore tokens;

  final http.Client _http;

  static const _timeout = Duration(seconds: 15);

  Future<dynamic> get(String path) => _send('GET', path);

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body, idempotent: true);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// Unauthenticated request — for `/auth/*`, which runs before a token exists.
  Future<dynamic> postPublic(String path, {Object? body}) =>
      _send('POST', path, body: body, authenticated: false);

  Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    bool idempotent = false,
    bool authenticated = true,
  }) async {
    // Generated once per logical operation, not per attempt: a replayed key is
    // what tells the server "this is the same pause, not a second one".
    final idempotencyKey = idempotent ? _uuidV4() : null;

    var response = await _attempt(
      method,
      path,
      body: body,
      idempotencyKey: idempotencyKey,
      authenticated: authenticated,
    );

    if (response.statusCode == 401 && authenticated) {
      final refreshed = await _refresh();
      if (!refreshed) {
        await tokens.clear();
        onSessionLost?.call();
        throw _decodeError(response);
      }
      response = await _attempt(
        method,
        path,
        body: body,
        idempotencyKey: idempotencyKey,
        authenticated: authenticated,
      );
      if (response.statusCode == 401) {
        await tokens.clear();
        onSessionLost?.call();
      }
    }

    if (response.statusCode >= 400) throw _decodeError(response);
    return _decodeBody(response);
  }

  Future<http.Response> _attempt(
    String method,
    String path, {
    Object? body,
    String? idempotencyKey,
    required bool authenticated,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    final headers = <String, String>{'Accept': 'application/json'};
    if (body != null) headers['Content-Type'] = 'application/json';
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;
    if (authenticated) {
      final token = await tokens.readAccessToken();
      if (token != null) headers['Authorization'] = 'Bearer $token';
    }

    final request = http.Request(method, uri)..headers.addAll(headers);
    if (body != null) request.body = jsonEncode(body);

    try {
      final streamed = await _http.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed);
    } on TimeoutException catch (e) {
      throw ApiException.network(e);
    } catch (e) {
      throw ApiException.network(e);
    }
  }

  /// Non-null while a refresh is already in flight.
  ///
  /// The Floor screen mounts three watchers plus a 5-second poller, so when the
  /// hour-long access token expires several requests 401 in the same instant.
  /// Without this guard each of them posted the SAME refresh token, and
  /// Supabase rotates refresh tokens on use — the first call wins and every
  /// other one comes back 401, which drove `tokens.clear()` and dropped the
  /// iPad to the sign-in screen mid-service. That is the exact failure the
  /// refresh endpoint was added to prevent.
  ///
  /// Supabase's reuse-grace window swallowed this most of the time, which made
  /// it intermittent rather than rare — the worst shape for a bug like this.
  Future<bool>? _refreshing;

  /// Returns true when a fresh access token was stored.
  ///
  /// Concurrent callers share one round trip: whoever arrives while a refresh
  /// is running awaits the same future, then retries with the token it stored.
  Future<bool> _refresh() {
    final inFlight = _refreshing;
    if (inFlight != null) return inFlight;

    final started = _performRefresh();
    _refreshing = started;
    // Cleared only if it is still ours, so a later refresh is never cancelled
    // by an earlier one finishing.
    started.whenComplete(() {
      if (identical(_refreshing, started)) _refreshing = null;
    });
    return started;
  }

  Future<bool> _performRefresh() async {
    final refreshToken = await tokens.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      final response = await _attempt(
        'POST',
        '/auth/refresh',
        body: {'refresh_token': refreshToken},
        authenticated: false,
      );
      if (response.statusCode >= 400) return false;

      final json = _decodeBody(response);
      if (json is! Map || json['token'] is! String) return false;

      await tokens.write(
        accessToken: json['token'] as String,
        refreshToken: (json['refresh_token'] as String?) ?? refreshToken,
      );
      return true;
    } on ApiException {
      // Network failure during refresh: not necessarily an invalid session, but
      // we cannot proceed. Reported as the original 401 by the caller.
      return false;
    }
  }

  dynamic _decodeBody(http.Response response) {
    if (response.statusCode == 204 || response.body.isEmpty) return null;
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      throw ApiException.malformed(response.statusCode);
    }
  }

  ApiException _decodeError(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      final error = (decoded as Map)['error'] as Map;
      return ApiException(
        statusCode: response.statusCode,
        code: error['code'] as String? ?? 'unknown',
        message: error['message'] as String? ?? 'Something went wrong.',
        field: error['field'] as String?,
        correlationId: error['correlation_id'] as String?,
        retryable: error['retryable'] as bool? ?? false,
      );
    } catch (_) {
      // A proxy, a 502 page, anything that is not our API.
      return ApiException.malformed(response.statusCode);
    }
  }

  void dispose() => _http.close();
}

/// RFC 4122 v4, from a cryptographic source.
///
/// Written out rather than adding a `uuid` dependency for one function — the
/// app's only use is idempotency keys, which need uniqueness, not a library.
String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
  final b = [for (var i = 0; i < 16; i++) hex(i)];
  return '${b[0]}${b[1]}${b[2]}${b[3]}-${b[4]}${b[5]}-${b[6]}${b[7]}-'
      '${b[8]}${b[9]}-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
}
