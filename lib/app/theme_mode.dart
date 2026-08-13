import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App theme mode. Dark is the design default (§1.1).
///
/// §2.0 says "Persist choice". It did not: the notifier was in-memory, so every
/// relaunch reverted to dark — on a device that lives on a bright bar counter,
/// a daily annoyance for anyone who wants light.
///
/// Lives here rather than in `main.dart` because the widgets that read it —
/// the top bar, the settings screen, the gallery — would otherwise have to
/// import the entrypoint, and `main.dart` imports the router, which imports
/// those same widgets. That cycle is legal Dart, but it makes the app's
/// top-level initialisation graph circular, and Flutter web's debug compiler
/// (DDC) links libraries by recursing through exactly that graph.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

/// The stored choice, read once before the first frame and injected by
/// `main()`.
///
/// Seeded rather than loaded inside the notifier because `Notifier.build()` is
/// synchronous: reading storage there would mean returning dark and correcting
/// it a frame later, which is a visible flash of the wrong theme on every
/// launch. Tests and the mock build get the default and never touch a platform
/// channel.
final initialThemeModeProvider = Provider<ThemeMode>((ref) => ThemeMode.dark);

const _themeModeKey = 'prism.theme_mode';

/// Reads the persisted choice. Falls back to dark on anything unexpected —
/// storage unavailable, a value written by an older build, a browser with
/// storage blocked. A theme preference is never worth failing a launch over.
Future<ThemeMode> readStoredThemeMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_themeModeKey);
    return ThemeMode.values.firstWhere(
      (mode) => mode.name == stored,
      orElse: () => ThemeMode.dark,
    );
  } catch (_) {
    return ThemeMode.dark;
  }
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ref.read(initialThemeModeProvider);

  void set(ThemeMode mode) {
    state = mode;
    _persist(mode);
  }

  void toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  /// Fire-and-forget, and deliberately not awaited by the setter: the toggle
  /// must feel instant, and a storage failure costs only being remembered
  /// across a restart. Same trade the token store makes.
  Future<void> _persist(ThemeMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_themeModeKey, mode.name);
    } catch (_) {
      // In memory is enough for this launch.
    }
  }
}
