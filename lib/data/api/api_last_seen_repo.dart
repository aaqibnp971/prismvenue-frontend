import '../repositories/last_seen_repo.dart';
import 'api_client.dart';
import 'installation_id.dart';

/// [LastSeenRepo] against `POST /zones/{id}/last-seen`.
///
/// Sent **unkeyed**. Every other POST in this app carries an `Idempotency-Key`,
/// but this one arrives every 60 seconds from every tablet and is
/// last-write-wins by nature: replaying it changes nothing, and a key per
/// report would fill `idempotency_keys` with rows nobody ever reads back.
///
/// Swallows every failure. A venue must never see an error because a
/// presence report did not land, and there is nothing for the user to do about
/// it. The server's own three-minute window is what turns a run of missed
/// reports into an honest "Offline".
class ApiLastSeenRepo implements LastSeenRepo {
  ApiLastSeenRepo(this._api, {this.appVersion, this.platform});

  final ApiClient _api;
  final String? appVersion;
  final String? platform;

  @override
  Future<void> report({
    required String zoneId,
    String? mode,
    String? moodId,
    int? volumePct,
  }) async {
    try {
      await _api.post(
        '/zones/$zoneId/last-seen',
        keyed: false,
        body: {
          'installation_id': await InstallationId.get(),
          'platform': ?platform,
          'app_version': ?appVersion,
          'mode': ?mode,
          'mood_id': ?moodId,
          'volume_pct': ?volumePct,
        },
      );
    } catch (_) {
      // Deliberately silent — see the class note.
    }
  }
}
