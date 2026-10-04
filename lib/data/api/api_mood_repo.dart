import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/moods.dart';
import '../repositories/mood_repo.dart';
import 'api_client.dart';
import 'api_scope.dart';
import 'watchable.dart';

/// `GET /moods` and `GET /zones/{id}/moods`.
///
/// ## The on-device copy
///
/// The catalogue is kept in shared_preferences, keyed by account, and served
/// when the fetch fails. It is the same argument as the offline plan cache
/// (finding #7): a tablet that restarts while the venue's internet is down
/// still knows from that cache WHICH mood the room should be on, and for a
/// venue with its own moods that id means nothing without the row behind it —
/// no scene file, no PSV, so the engine could only fail closed and the room
/// would be silent until the router came back.
///
/// Existing venues never depend on it: their six moods are compiled in.
///
/// Only the catalogue is stored, not the per-zone list. Offline, the room
/// offers the moods in the same set as the one it is playing
/// (`zoneMoodsProvider`), which the stored catalogue is enough to answer.
class ApiMoodRepo implements MoodRepo {
  ApiMoodRepo(this._client, this._scope);

  final ApiClient _client;
  final ApiScope _scope;

  static const _storageKey = 'prism.mood_catalogue';

  late final _catalogue =
      Watchable<List<Mood>>(_fetchCatalogue, scopeKey: _scope.accountKey);

  late final _zoneMoods =
      Watchable<List<Mood>>(_fetchZoneMoods, scopeKey: _scope.zoneKey);

  @override
  Stream<List<Mood>> watchCatalogue() => _catalogue.watch();

  @override
  Stream<List<Mood>> watchZoneMoods() => _zoneMoods.watch();

  Future<List<Mood>> _fetchCatalogue() async {
    try {
      final json = await _client.get('/moods') as List;
      final moods = _parse(json);
      await _store(json);
      return moods;
    } catch (e) {
      final stored = await _restore();
      if (stored != null) return stored;
      rethrow;
    }
  }

  Future<List<Mood>> _fetchZoneMoods() async {
    final json =
        await _client.get('/zones/${_scope.requireZone()}/moods') as List;
    return _parse(json);
  }

  /// One bad row must not cost the whole catalogue: it is skipped and named in
  /// the log, and every other mood still loads.
  static List<Mood> _parse(List json) {
    final moods = <Mood>[];
    for (final row in json) {
      try {
        moods.add(Mood.fromJson(row as Map<String, dynamic>));
      } catch (e) {
        debugPrint('prism: a mood row could not be read and was skipped: $e');
      }
    }
    return moods;
  }

  Future<void> _store(List json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({'account': _scope.accountKey(), 'moods': json}),
      );
    } catch (e) {
      // A cache. Failing to write it must never fail the read it rides on.
      debugPrint('prism: could not store the mood catalogue: $e');
    }
  }

  /// The stored catalogue, if it was written for THIS account. A shared venue
  /// tablet must not hand one organisation's moods to the next person to sign
  /// in.
  Future<List<Mood>?> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null) return null;
      final stored = jsonDecode(raw) as Map<String, dynamic>;
      if (stored['account'] != _scope.accountKey()) return null;
      return _parse(stored['moods'] as List);
    } catch (e) {
      debugPrint('prism: the stored mood catalogue could not be read: $e');
      return null;
    }
  }

  /// Removes the on-device copy. Called on sign-out.
  static Future<void> clearStored() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
    } catch (_) {
      // Nothing to do: the account check in [_restore] is the real guard.
    }
  }

  void dispose() {
    _catalogue.dispose();
    _zoneMoods.dispose();
  }
}
