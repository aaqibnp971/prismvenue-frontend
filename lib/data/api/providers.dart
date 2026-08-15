import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/env.dart';
import '../../app/session.dart';
import 'api_client.dart';
import 'api_scope.dart';
import 'token_store.dart';

/// Where the session token is persisted. Overridden with
/// [InMemoryTokenStore] in tests, which have no platform channel.
final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// The single HTTP client every API repository shares.
///
/// `onSessionLost` closes the loop between the transport and the app: when a
/// token expires and refresh fails, the client cannot know what to do about
/// it, and the session layer cannot know it happened. `ref.read` inside the
/// callback runs later, when the container exists, so there is no
/// initialisation cycle here.
final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient(
    baseUrl: Env.apiBaseUrl,
    tokens: ref.watch(tokenStoreProvider),
    onSessionLost: () {
      ref.read(sessionProvider.notifier).set(null);
      ref.read(sessionContextProvider.notifier).set(null);
    },
  );
  ref.onDispose(client.dispose);
  return client;
});

/// Which zone/venue the zone-scoped repositories act on.
///
/// `ref.read` inside the closures rather than `ref.watch` at build time: the
/// scope is resolved per call, so changing the session's zone takes effect
/// without rebuilding every repository.
final apiScopeProvider = Provider<ApiScope>((ref) => ApiScope(
      zoneId: () => ref.read(currentZoneIdProvider),
      venueId: () => ref.read(currentVenueIdProvider),
      userId: () => ref.read(sessionProvider)?.id,
    ));
