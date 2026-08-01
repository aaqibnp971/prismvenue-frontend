import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// App theme mode. Dark is the design default (§1.1).
/// TODO(phase-3): persist the choice (§2.0 "Theme toggle behavior") once the
/// top-bar toggle lands.
///
/// Lives here rather than in `main.dart` because the widgets that read it —
/// the top bar, the settings screen, the gallery — would otherwise have to
/// import the entrypoint, and `main.dart` imports the router, which imports
/// those same widgets. That cycle is legal Dart, but it makes the app's
/// top-level initialisation graph circular, and Flutter web's debug compiler
/// (DDC) links libraries by recursing through exactly that graph.
final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.dark;

  void set(ThemeMode mode) => state = mode;

  void toggle() =>
      state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
}
