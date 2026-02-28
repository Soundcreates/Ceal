/// AfterMath Material 3 theme configuration.
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // Colours
  // ---------------------------------------------------------------------------

  static const Color _seedColor = Color(0xFFE53935); // emergency red
  static const Color _sosBg = Color(0xFFB71C1C);
  static const Color _safeGreen = Color(0xFF2E7D32);

  /// Accent colour for SOS elements.
  static const Color sosColor = _sosBg;

  /// Accent colour for "safe / resolved" states.
  static const Color safeColor = _safeGreen;

  // ---------------------------------------------------------------------------
  // Light theme
  // ---------------------------------------------------------------------------

  static final ThemeData light = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    ),
    appBarTheme: const AppBarTheme(centerTitle: true),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _sosBg,
      foregroundColor: Colors.white,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );

  // ---------------------------------------------------------------------------
  // Dark theme
  // ---------------------------------------------------------------------------

  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    ),
    appBarTheme: const AppBarTheme(centerTitle: true),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: _sosBg,
      foregroundColor: Colors.white,
      elevation: 8,
    ),
    cardTheme: CardThemeData(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
