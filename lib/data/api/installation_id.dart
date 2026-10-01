import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// This installation's id: generated once, then kept.
///
/// It identifies the INSTALL, not the person. Two tablets in one room are two
/// ids; signing a different member of staff into the same tablet does not
/// change it. The server keys one `devices` row per (zone, installation), so a
/// room with two tablets shows as two devices rather than one row flip-flopping
/// between them.
///
/// Stored rather than generated per launch on purpose: a fresh id every launch
/// would leave a trail of dead device rows, and the one question the row exists
/// to answer — "has this tablet checked in lately?" — would always say no for
/// the id that mattered a minute ago.
class InstallationId {
  static const _key = 'prism.installation_id';

  static String? _cached;

  /// The stored id, creating one on first call.
  ///
  /// Falls back to a per-process id if storage is unavailable, because failing
  /// to read a preference must not stop a venue reporting that it is alive.
  static Future<String> get() async {
    if (_cached != null) return _cached!;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_key);
      if (stored != null && stored.isNotEmpty) return _cached = stored;
      final fresh = uuidV4();
      await prefs.setString(_key, fresh);
      return _cached = fresh;
    } catch (_) {
      return _cached ??= uuidV4();
    }
  }

  /// The id if it has already been read, without waiting for storage.
  ///
  /// For the one caller that cannot await — the SSE line handler, which is
  /// synchronous. Null only before the first [get], and the now-playing fetch
  /// primes it long before any event line arrives.
  static String? get cached => _cached;

  /// Test seam. Never called in production.
  static void resetForTest([String? value]) => _cached = value;
}

/// A v4 UUID from a cryptographic source.
///
/// Duplicated from `api_client.dart`'s private one rather than shared: that one
/// exists to key a single request and could reasonably change; this one is
/// written to a device's storage and must keep its format.
String uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int i) => bytes[i].toRadixString(16).padLeft(2, '0');
  final b = [for (var i = 0; i < 16; i++) hex(i)];
  return '${b[0]}${b[1]}${b[2]}${b[3]}-${b[4]}${b[5]}-${b[6]}${b[7]}-'
      '${b[8]}${b[9]}-${b[10]}${b[11]}${b[12]}${b[13]}${b[14]}${b[15]}';
}
