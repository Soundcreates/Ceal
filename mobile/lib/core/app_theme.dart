/// AfterMath Neo-Brutalist theme configuration.
///
/// Design language: thick BLACK borders, hard offset drop-shadows (no blur),
/// bold type, high contrast, squared-off corners — inspired by
/// github.com/pettiboy/better-wallet hot-app.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  AppTheme._();

  // ---------------------------------------------------------------------------
  // Neobrutalism colour palette — bold & high-contrast
  // ---------------------------------------------------------------------------
  static const Color nbBg      = Color(0xFFFEFCE8); // soft yellow bg
  static const Color nbInk     = Color(0xFF000000); // pure black
  static const Color nbAccent  = Color(0xFF3B82F6); // bright blue (primary)
  static const Color nbAccent2 = Color(0xFF8B5CF6); // purple (secondary)
  static const Color nbWarn    = Color(0xFFF59E0B); // amber
  static const Color nbError   = Color(0xFFEF4444); // red
  static const Color nbOk      = Color(0xFF10B981); // green
  static const Color nbCard    = Color(0xFFFFFFFF); // pure white
  static const Color nbInfo    = Color(0xFF06B6D4); // cyan

  static const Color nbGray50  = Color(0xFFFAFAFA);
  static const Color nbGray100 = Color(0xFFF5F5F5);
  static const Color nbGray200 = Color(0xFFE5E5E5);
  static const Color nbGray300 = Color(0xFFD4D4D4);

  // Legacy aliases (used across feature screens)
  static const Color sosColor  = Color(0xFFEF4444); // red
  static const Color safeColor = Color(0xFF10B981); // green

  // ---------------------------------------------------------------------------
  // Shared constants — "better-wallet" NB tokens
  // ---------------------------------------------------------------------------
  static const double nbRadius     = 0;     // square corners
  static const double nbBorder     = 4.0;   // 4px thick borders
  static const Radius nbRadiusObj  = Radius.circular(0);

  /// Hard offset drop-shadow — signature NB "sticker" effect (6px 6px 0 black).
  static List<BoxShadow> get nbShadow => const [
    BoxShadow(
      color: Color(0xFF000000),
      offset: Offset(6, 6),
      blurRadius: 0,
    ),
  ];

  /// Smaller hard shadow (4px 4px 0 black).
  static List<BoxShadow> get nbShadowSm => const [
    BoxShadow(
      color: Color(0xFF000000),
      offset: Offset(4, 4),
      blurRadius: 0,
    ),
  ];

  /// NB border side for cards / containers.
  static const BorderSide nbBorderSide = BorderSide(
    color: nbInk,
    width: nbBorder,
  );

  // ---------------------------------------------------------------------------
  // Text theme  (Space Grotesk headings · Inter body — weight 500-900)
  // ---------------------------------------------------------------------------
  static TextTheme _buildTextTheme(Brightness brightness) {
    final Color ink = brightness == Brightness.light ? nbInk : nbCard;
    final base = GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    );
    return base.copyWith(
      displayLarge:  GoogleFonts.spaceGrotesk(fontSize: 57, fontWeight: FontWeight.w900, color: ink),
      displayMedium: GoogleFonts.spaceGrotesk(fontSize: 45, fontWeight: FontWeight.w900, color: ink),
      displaySmall:  GoogleFonts.spaceGrotesk(fontSize: 36, fontWeight: FontWeight.w900, color: ink),
      headlineLarge: GoogleFonts.spaceGrotesk(fontSize: 32, fontWeight: FontWeight.w900, color: ink),
      headlineMedium:GoogleFonts.spaceGrotesk(fontSize: 28, fontWeight: FontWeight.w700, color: ink),
      headlineSmall: GoogleFonts.spaceGrotesk(fontSize: 24, fontWeight: FontWeight.w700, color: ink),
      titleLarge:    GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w700, color: ink),
      titleMedium:   GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, color: ink),
      titleSmall:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
      bodyLarge:     GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w500, color: ink),
      bodyMedium:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: ink),
      bodySmall:     GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: ink.withValues(alpha: 0.7)),
      labelLarge:    GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, color: ink),
      labelMedium:   GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w500, color: ink),
      labelSmall:    GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, color: ink),
    );
  }

  // ---------------------------------------------------------------------------
  // Component themes
  // ---------------------------------------------------------------------------
  static const RoundedRectangleBorder _nbCardShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.zero,
    side: nbBorderSide,
  );

  static const InputDecorationTheme _nbInputDecoration = InputDecorationTheme(
    filled: true,
    fillColor: nbCard,
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: nbBorderSide),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: nbBorderSide),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: nbAccent, width: 4),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: nbError, width: 4),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.zero,
      borderSide: BorderSide(color: nbError, width: 4),
    ),
  );

  // ---------------------------------------------------------------------------
  // Light theme
  // ---------------------------------------------------------------------------
  static final ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: nbBg,
    colorScheme: const ColorScheme.light(
      primary: nbAccent,
      secondary: nbAccent2,
      tertiary: nbOk,
      error: nbError,
      surface: nbBg,
      onPrimary: nbCard,
      onSecondary: nbCard,
      onSurface: nbInk,
      onError: nbCard,
      outline: nbInk,
    ),
    textTheme: _buildTextTheme(Brightness.light),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: nbCard,
      foregroundColor: nbInk,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: nbInk,
      ),
      shape: const Border(bottom: nbBorderSide),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: nbCard,
      shape: _nbCardShape,
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: nbAccent,
        foregroundColor: nbCard,
        textStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: nbBorderSide,
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: nbAccent,
        foregroundColor: nbCard,
        textStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: nbBorderSide,
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: nbInk,
        textStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: nbBorderSide,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: nbAccent,
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: nbError,
      foregroundColor: nbCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: nbBorderSide,
      ),
    ),
    inputDecorationTheme: _nbInputDecoration,
    dividerTheme: const DividerThemeData(
      color: nbInk,
      thickness: 2,
      space: 32,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return nbAccent;
        return nbInk;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return nbAccent.withValues(alpha: 0.4);
        return nbGray300;
      }),
      trackOutlineColor: WidgetStateProperty.all(nbInk),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: nbCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: nbBorderSide,
      ),
      titleTextStyle: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w900, color: nbInk),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: nbInk,
      contentTextStyle: GoogleFonts.inter(color: nbCard, fontWeight: FontWeight.w500),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: nbBorderSide),
      behavior: SnackBarBehavior.floating,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: nbCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: nbBorderSide),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    dropdownMenuTheme: const DropdownMenuThemeData(
      inputDecorationTheme: _nbInputDecoration,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: nbCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: nbInk, width: 4),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: nbAccent,
      linearTrackColor: nbGray200,
    ),
  );

  // ---------------------------------------------------------------------------
  // Dark theme — NB on dark surface
  // ---------------------------------------------------------------------------
  static final ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF171717),
    colorScheme: const ColorScheme.dark(
      primary: nbAccent,
      secondary: nbAccent2,
      tertiary: nbOk,
      error: nbError,
      surface: Color(0xFF171717),
      onPrimary: nbCard,
      onSecondary: nbCard,
      onSurface: nbCard,
      onError: nbCard,
      outline: nbCard,
    ),
    textTheme: _buildTextTheme(Brightness.dark),
    appBarTheme: AppBarTheme(
      centerTitle: true,
      elevation: 0,
      backgroundColor: const Color(0xFF262626),
      foregroundColor: nbCard,
      titleTextStyle: GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w900,
        color: nbCard,
      ),
      shape: const Border(bottom: BorderSide(color: nbCard, width: 4)),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: Color(0xFF262626),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: nbCard, width: 4),
      ),
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: nbAccent,
        foregroundColor: nbCard,
        textStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: nbCard, width: 4),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: nbAccent,
        foregroundColor: nbCard,
        textStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: nbCard, width: 4),
        ),
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: nbCard,
        textStyle: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        side: const BorderSide(color: nbCard, width: 4),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: nbAccent,
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: nbError,
      foregroundColor: nbCard,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: nbCard, width: 4),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Color(0xFF262626),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: nbCard, width: 4),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: nbCard, width: 4),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: nbAccent, width: 4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: nbError, width: 4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.zero,
        borderSide: BorderSide(color: nbError, width: 4),
      ),
    ),
    dividerTheme: const DividerThemeData(color: nbCard, thickness: 2, space: 32),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return nbAccent;
        return nbCard;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return nbAccent.withValues(alpha: 0.4);
        return nbCard.withValues(alpha: 0.15);
      }),
      trackOutlineColor: WidgetStateProperty.all(nbCard),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF262626),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: nbCard, width: 4),
      ),
      titleTextStyle: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w900, color: nbCard),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: nbCard,
      contentTextStyle: GoogleFonts.inter(color: nbInk),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero, side: nbBorderSide),
      behavior: SnackBarBehavior.floating,
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: Color(0xFF262626),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: nbCard, width: 4),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF262626),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: nbCard, width: 4),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: nbAccent,
      linearTrackColor: Color(0x33FFFFFF),
    ),
  );
}
