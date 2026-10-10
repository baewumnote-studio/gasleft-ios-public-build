import 'package:flutter/material.dart';

import 'design_tokens.dart';

abstract final class AppTheme {
  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: DesignTokens.pine,
      brightness: Brightness.light,
      surface: DesignTokens.surfaceLight,
    );
    final scheme = base.copyWith(
      primary: DesignTokens.pine,
      onPrimary: Colors.white,
      primaryContainer: DesignTokens.pineSoft,
      onPrimaryContainer: const Color(0xFF153A2A),
      surface: DesignTokens.surfaceLight,
      surfaceContainerLowest: DesignTokens.surfaceLight,
      surfaceContainerLow: const Color(0xFFFBF9F3),
      surfaceContainer: DesignTokens.surfaceMutedLight,
      onSurface: DesignTokens.ink,
      onSurfaceVariant: DesignTokens.inkMuted,
      outlineVariant: const Color(0xFFD9D7CF),
    );

    return _build(
      scheme: scheme,
      scaffold: DesignTokens.canvasLight,
      dark: false,
    );
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: const Color(0xFF70C99C),
      brightness: Brightness.dark,
      surface: DesignTokens.surfaceDark,
    );
    final scheme = base.copyWith(
      primary: const Color(0xFF84D8AE),
      onPrimary: const Color(0xFF073522),
      primaryContainer: const Color(0xFF193D2D),
      onPrimaryContainer: const Color(0xFFC8F5DC),
      surface: DesignTokens.surfaceDark,
      surfaceContainerLowest: DesignTokens.surfaceDark,
      surfaceContainerLow: const Color(0xFF151B17),
      surfaceContainer: DesignTokens.surfaceMutedDark,
      onSurface: const Color(0xFFF0F4F1),
      onSurfaceVariant: const Color(0xFFB8C2BC),
      outlineVariant: const Color(0xFF39433D),
    );

    return _build(
      scheme: scheme,
      scaffold: DesignTokens.canvasDark,
      dark: true,
    );
  }

  static ThemeData _build({
    required ColorScheme scheme,
    required Color scaffold,
    required bool dark,
  }) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: dark ? Brightness.dark : Brightness.light,
      colorScheme: scheme,
    );
    final textTheme = base.textTheme.copyWith(
      displayLarge: base.textTheme.displayLarge?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -2.2,
        height: 0.98,
      ),
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: -1.2,
        height: 1,
      ),
      headlineSmall: base.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.45,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w700,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      colorScheme: scheme,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w900,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusCard),
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: dark ? 0.62 : 0.72),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.72),
        space: 28,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
          borderSide: BorderSide(color: scheme.primary, width: 1.8),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(DesignTokens.controlHeight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusControl),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.1,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 2,
        focusElevation: 2,
        hoverElevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainer,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark
            ? const Color(0xFF27312B)
            : const Color(0xFF26312B),
        contentTextStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
