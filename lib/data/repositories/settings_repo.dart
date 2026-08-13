import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/session.dart';
import '../mock/mock_settings_repo.dart';
import '../models/guardrails.dart';

/// Guardrails & settings boundary — §2 S05. Async/stream-shaped (§C).
abstract class SettingsRepo {
  Stream<Guardrails> watchGuardrails();
  Future<void> updateGuardrails(Guardrails next);

  /// Emits when a guardrail write failed and the optimistic value was reverted.
  ///
  /// A stream rather than a thrown future. [updateGuardrails] is called from
  /// nine places — sliders, toggles, segmented pickers — and is deliberately
  /// fire-and-forget, so making it throw would put nine unhandled async
  /// exceptions where there is currently one silent revert.
  ///
  /// The revert alone was the only signal, which is defensible for a volume
  /// slider and not for "Who can take over": that decides whether floor staff
  /// can seize the speakers, and a manager who sets it, watches it flip back
  /// and is told nothing has every reason to assume it stuck.
  Stream<Object> get guardrailFailures;

  Stream<OpenHours> watchOpenHours();
  Future<void> setEverydayHours({required int openHour, required int closeHour});
  Future<void> addException(HoursException exception);

  /// S05-10 in edit mode. Sends the whole exception — the model has no
  /// partial form — so [HoursException.id] must be set.
  Future<void> updateException(HoursException exception);

  Future<void> deleteException(String id);
}

/// Guardrails follow the zone, open hours follow the venue — the same split
/// `ApiScope` gives the API repo, and the same split the schema has.
final settingsRepoProvider = Provider<SettingsRepo>((ref) {
  final repo = MockSettingsRepo(
    zoneId: () => ref.read(currentZoneIdProvider),
    venueId: () => ref.read(currentVenueIdProvider),
  );
  ref.onDispose(repo.dispose);
  return repo;
});

/// Watching the current zone/venue is what makes these resubscribe once
/// sign-in establishes them. Without it, a provider subscribed before sign-in
/// (the router listens to guardrails at startup for the S05-4 takeover gate)
/// fetches with no zone, fails, and has nothing to tell it to try again — so
/// every settings screen renders fallback defaults for the whole session.
final guardrailsProvider = StreamProvider.autoDispose<Guardrails>((ref) {
  ref.watch(currentZoneIdProvider);
  return ref.watch(settingsRepoProvider).watchGuardrails();
});

final openHoursProvider = StreamProvider.autoDispose<OpenHours>((ref) {
  ref.watch(currentVenueIdProvider);
  return ref.watch(settingsRepoProvider).watchOpenHours();
});

/// Guardrail write failures, for the screens that write them to surface.
///
/// Not autoDispose: a failure can land after the debounce, by which point the
/// manager may already have moved to another settings screen, and the error
/// still belongs to them.
final guardrailFailureProvider = StreamProvider<Object>(
    (ref) => ref.watch(settingsRepoProvider).guardrailFailures);
