import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/env.dart';
import 'app/theme_mode.dart';
import 'app/router.dart';
import 'app/session.dart';
import 'data/api/api_auth_repo.dart';
import 'data/api/api_playback_repo.dart';
import 'data/api/api_schedule_repo.dart';
import 'data/api/api_settings_repo.dart';
import 'data/api/api_venue_repo.dart';
import 'data/api/providers.dart';
import 'data/repositories/auth_repo.dart';
import 'data/repositories/playback_repo.dart';
import 'data/repositories/schedule_repo.dart';
import 'data/repositories/settings_repo.dart';
import 'data/repositories/venue_repo.dart';
import 'engine/engine_controller.dart';
import 'theme/palette.dart';
import 'theme/theme.dart';

/// Swaps the mock repositories for API-backed ones.
///
/// This is the single seam `BACKEND_INTEGRATION.md` §2 describes: one override
/// per interface, nothing else in the app changes. Repositories are migrated
/// one at a time — anything not listed here is still on its mock, which is why
/// the list grows increment by increment rather than all at once.
///
/// `--dart-define=PRISM_USE_MOCKS=true` returns an empty list, running the app
/// exactly as it ran before the backend existed. Useful for design review and
/// for reproducing the widget tests by hand.
ProviderContainer buildPrismContainer({ThemeMode? initialTheme}) {
  // The persisted theme is injected rather than read inside the notifier:
  // Notifier.build() is synchronous, so loading it there would show dark for a
  // frame and then correct itself on every launch.
  final themeOverride = [
    if (initialTheme != null)
      initialThemeModeProvider.overrideWithValue(initialTheme),
  ];

  if (Env.useMocks) return ProviderContainer(overrides: themeOverride);
  return ProviderContainer(overrides: [
    ...themeOverride,
    authRepoProvider.overrideWith(
      (ref) => ApiAuthRepo(
        ref.watch(apiClientProvider),
        ref.watch(tokenStoreProvider),
      ),
    ),
    settingsRepoProvider.overrideWith((ref) {
      final repo = ApiSettingsRepo(
        ref.watch(apiClientProvider),
        ref.watch(apiScopeProvider),
      );
      ref.onDispose(repo.dispose);
      return repo;
    }),
    venueRepoProvider.overrideWith((ref) {
      final repo = ApiVenueRepo(ref.watch(apiClientProvider));
      ref.onDispose(repo.dispose);
      return repo;
    }),
    scheduleRepoProvider.overrideWith((ref) {
      final repo = ApiScheduleRepo(
        ref.watch(apiClientProvider),
        ref.watch(apiScopeProvider),
      );
      ref.onDispose(repo.dispose);
      return repo;
    }),
    playbackRepoProvider.overrideWith((ref) {
      final repo = ApiPlaybackRepo(
        ref.watch(apiClientProvider),
        ref.watch(apiScopeProvider),
        ref.watch(tokenStoreProvider),
      );
      ref.onDispose(repo.dispose);
      return repo;
    }),
  ]);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Read before the first frame so a light-theme venue never sees dark flash
  // past. Cheap and local, unlike the session restore below.
  final container = buildPrismContainer(initialTheme: await readStoredThemeMode());

  // Rehydrate before the first frame so the router sees the final session and
  // a returning user never sees the sign-in screen flash past.
  //
  // Capped, because a slow network must not hold the app hostage: if the check
  // outlives the cap we start signed out and let it finish in the background —
  // the router listens to the session, so a late success still lands the user
  // on their home screen.
  if (!Env.useMocks) {
    await container
        .read(authControllerProvider)
        .restore()
        .timeout(const Duration(seconds: 3), onTimeout: () {});
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const PrismVenuesApp(),
  ));
}

class PrismVenuesApp extends ConsumerWidget {
  const PrismVenuesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Reading this once, above the router, is what connects app state to the
    // speakers. The controller then follows now-playing and takeover for the
    // life of the app; nothing else needs to know the engine exists.
    //
    // On web this resolves to a no-op engine — Flutter web has no dart:ffi, so
    // a native library cannot be loaded there at all.
    ref.watch(engineControllerProvider);

    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Prism Venues',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildPrismTheme(PrismPalette.light),
      darkTheme: buildPrismTheme(PrismPalette.dark),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
