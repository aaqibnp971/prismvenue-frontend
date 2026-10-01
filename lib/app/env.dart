/// Build-time configuration.
///
/// Supplied with `--dart-define`, never from a committed file:
///
/// ```
/// flutter run -d chrome --dart-define=PRISM_API_BASE_URL=http://localhost:8000/v1
/// ```
///
/// Nothing secret belongs here. The app never sees a Supabase key, a service
/// role token, or a database URL — it only ever learns where the API lives.
/// Everything sensitive stays in the backend's `.env`.
class Env {
  const Env._();

  /// Base URL including the `/v1` prefix, no trailing slash.
  static const apiBaseUrl = String.fromEnvironment(
    'PRISM_API_BASE_URL',
    defaultValue: 'http://localhost:8000/v1',
  );

  /// When true the app runs entirely on the in-memory mocks, ignoring
  /// [apiBaseUrl]. Useful for design review and for running the widget tests
  /// the way they ran before the backend existed.
  static const useMocks = bool.fromEnvironment('PRISM_USE_MOCKS');

  /// Shown against this installation in the device list, so a venue reporting
  /// an old build can be spotted. Set by the packaging scripts; empty in a
  /// plain `flutter run`, and simply omitted from the report when it is.
  static const appVersion = String.fromEnvironment('PRISM_APP_VERSION');

  /// Shown on the offline-zone help sheet, e.g. "support@r13labs.com". Empty
  /// by default and then simply not shown: a screen that says "contact
  /// support" and names nobody is worse than one that stays quiet.
  static const supportContact = String.fromEnvironment('PRISM_SUPPORT_CONTACT');
}
