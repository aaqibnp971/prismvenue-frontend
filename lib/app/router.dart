import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../debug/widget_gallery_screen.dart';
import '../features/auth/reset_code_screen.dart';
import '../features/auth/reset_email_screen.dart';
import '../features/auth/reset_password_screen.dart';
import '../features/auth/sign_in_screen.dart';
import '../features/floor/floor_screen.dart';
import '../data/models/guardrails.dart';
import '../data/repositories/settings_repo.dart';
import '../features/schedule/schedule_screen.dart';
import '../features/settings/open_hours_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/settings/transitions_screen.dart';
import '../features/settings/volume_policy_screen.dart';
import '../features/settings/zone_detail_screen.dart';
import '../features/takeover/takeover_screen.dart';
import '../features/venues/add_venue_screen.dart';
import '../features/venues/portfolio_screen.dart';
import '../features/venues/venue_screen.dart';
import 'roles.dart';
import 'session.dart';
import 'shell.dart';

/// go_router per §4. All screens are Phase 2 placeholders; sheets & dialogs
/// ride on their parent as modals (Phase 3).
///
/// Role gating (§4), enforced here as redirects + locked nav in PrismShell:
/// - floor:   /floor, /takeover only; Schedule/Venues/Settings locked.
/// - manager: everything except the /venues portfolio view & /venues/add
///            (their /venues IS their single venue, S04-1 — content-level,
///            Phase 3) — /venues/add redirects back to /venues.
/// - owner:   everything; lands on /venues (portfolio).
/// Landing after auth: floor & manager → /floor; owner → /venues (§2 S00).
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier(0);
  ref.listen(sessionProvider, (_, _) => refresh.value++);
  ref.listen(guardrailsProvider, (_, _) => refresh.value++);
  ref.onDispose(refresh.dispose);

  String? redirect(context, GoRouterState state) {
    final user = ref.read(sessionProvider);
    final loc = state.uri.path;

    if (loc == '/_gallery') return null; // debug route, never gated

    final onAuth = loc == '/signin' || loc.startsWith('/reset');
    if (user == null) return onAuth ? null : '/signin';

    final landing = user.role == Role.owner ? '/venues' : '/floor';
    if (onAuth || loc == '/') return landing;

    if (user.role == Role.floor) {
      if (loc.startsWith('/schedule') ||
          loc.startsWith('/venues') ||
          loc.startsWith('/settings')) {
        return '/floor';
      }
      // §4/S05-4: "who-can-take-over gates the floor role's takeover
      // access". Latest stream value via the provider (seed default until
      // the first emission).
      final takeoverAccess = ref.read(guardrailsProvider).value?.takeoverAccess ??
          TakeoverAccess.managersPlusFloor;
      if (loc.startsWith('/takeover') &&
          takeoverAccess == TakeoverAccess.managers) {
        return '/floor';
      }
    }
    if (user.role == Role.manager && loc == '/venues/add') return '/venues';
    return null;
  }

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: redirect,
    routes: [
      // ---- Auth (S00), outside the chrome shell ----
      GoRoute(
        path: '/',
        redirect: (context, state) => '/signin', // resolved by top redirect
      ),
      GoRoute(
        path: '/signin',
        builder: (context, state) => const SignInScreen(),
      ),
      GoRoute(
        path: '/reset/email',
        builder: (context, state) => const ResetEmailScreen(),
      ),
      GoRoute(
        path: '/reset/code',
        builder: (context, state) => const ResetCodeScreen(),
      ),
      GoRoute(
        path: '/reset/new',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      // ---- Hidden debug gallery ----
      GoRoute(
        path: '/_gallery',
        builder: (context, state) => const WidgetGalleryScreen(),
      ),
      // ---- Post-auth tabs inside the chrome shell (§2.0) ----
      ShellRoute(
        builder: (context, state, child) =>
            PrismShell(location: state.uri.path, child: child),
        routes: [
          GoRoute(
            path: '/floor',
            builder: (context, state) => const FloorScreen(),
          ),
          GoRoute(
            path: '/takeover',
            builder: (context, state) => const TakeoverScreen(),
          ),
          GoRoute(
            path: '/schedule',
            builder: (context, state) => const ScheduleScreen(),
          ),
          GoRoute(
            path: '/venues',
            builder: (context, state) => const _VenuesSwitch(),
            routes: [
              GoRoute(
                path: 'add',
                builder: (context, state) => const AddVenueScreen(),
              ),
              // Before ':id' so 'zones' isn't captured as a venue id.
              GoRoute(
                path: 'zones/:zoneId',
                builder: (context, state) => ZoneDetailScreen(
                    zoneId: state.pathParameters['zoneId']!),
              ),
              GoRoute(
                path: ':id',
                builder: (context, state) => VenueScreen(
                    venueId: state.pathParameters['id']!, drillIn: true),
              ),
            ],
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
            routes: [
              GoRoute(
                path: 'volume',
                builder: (context, state) => const VolumePolicyScreen(),
              ),
              GoRoute(
                path: 'transitions',
                builder: (context, state) => const TransitionsScreen(),
              ),
              GoRoute(
                path: 'hours',
                builder: (context, state) => const OpenHoursScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// /venues resolves by role (§4): owner → portfolio S04-2; manager → their
/// single venue S04-1.
class _VenuesSwitch extends ConsumerWidget {
  const _VenuesSwitch();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(sessionProvider)?.role;
    if (role == Role.owner) return const PortfolioScreen();

    // The manager's venue comes from their session, not from a mock constant.
    // Null only before sign-in, when the router has already redirected away.
    final venueId = ref.watch(currentVenueIdProvider);
    if (venueId == null) return const SizedBox.shrink();
    return VenueScreen(venueId: venueId);
  }
}
