import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF00897B);

  static TextTheme _compactTextTheme(TextTheme base) {
    return base.copyWith(
      headlineLarge: base.headlineLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      headlineMedium: base.headlineMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      headlineSmall: base.headlineSmall?.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      titleLarge: base.titleLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
      titleMedium: base.titleMedium?.copyWith(fontSize: 13.5, fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w500),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 13.5),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 12.5),
      bodySmall: base.bodySmall?.copyWith(fontSize: 11),
      labelLarge: base.labelLarge?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(fontSize: 11),
      labelSmall: base.labelSmall?.copyWith(fontSize: 10),
    );
  }

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      textTheme: _compactTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 48,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 1,
        shadowColor: colorScheme.shadow.withOpacity(0.08),
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.6)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      textTheme: _compactTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 48,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardTheme(
        elevation: 1,
        margin: const EdgeInsets.only(bottom: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colorScheme.outlineVariant.withOpacity(0.5)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
