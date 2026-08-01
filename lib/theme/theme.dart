import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'palette.dart';

/// Fully custom theme (Material 3 off, §Target) built from the palette.
/// Components style themselves from `PrismPalette`/`PrismType` directly;
/// ThemeData carries only the global scaffold + base text defaults.
///
/// Moved out of `main.dart` alongside [themeModeProvider]: the widget gallery
/// needs it, and a widget importing the entrypoint is what made the app's
/// library graph circular.
ThemeData buildPrismTheme(PrismPalette palette) {
  final base = ThemeData(
    useMaterial3: false,
    brightness: palette.brightness,
    scaffoldBackgroundColor: palette.screen,
    canvasColor: palette.surface,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    // §4: screen transitions are undesigned — instant (§6-B6). Sheets keep
    // their own ≤200ms slide.
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      for (final platform in TargetPlatform.values)
        platform: const _InstantTransitionsBuilder(),
    }),
  );
  return base.copyWith(
    textTheme: GoogleFonts.hankenGroteskTextTheme(base.textTheme).apply(
      bodyColor: palette.textPrimary,
      displayColor: palette.textPrimary,
    ),
    extensions: [palette],
  );
}

class _InstantTransitionsBuilder extends PageTransitionsBuilder {
  const _InstantTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}
