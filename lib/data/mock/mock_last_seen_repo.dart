import '../repositories/last_seen_repo.dart';

/// Records reports instead of sending them.
///
/// Kept for the same reason as every other mock: the suite depends on them,
/// and they document the shape. Also what `--dart-define=PRISM_USE_MOCKS=true`
/// runs against, where there is no server to report to.
class MockLastSeenRepo implements LastSeenRepo {
  final reports = <({String zoneId, String? mode, String? moodId, int? volumePct})>[];

  @override
  Future<void> report({
    required String zoneId,
    String? mode,
    String? moodId,
    int? volumePct,
  }) async {
    reports.add((
      zoneId: zoneId,
      mode: mode,
      moodId: moodId,
      volumePct: volumePct,
    ));
  }
}
