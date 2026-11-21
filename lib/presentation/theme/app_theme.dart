import 'package:flutter/material.dart';

class AppTheme {
  static const _seedColor = Color(0xFF1D4ED8); // Modern Royal Blue / Indigo

  // Brand accent palette
  static const Color primaryBlue = Color(0xFF1E40AF);
  static const Color deepNavy = Color(0xFF0B2559);
  static const Color accentCyan = Color(0xFF0EA5E9);
  static const Color groupTeal = Color(0xFF0D9488);
  static const Color buddyPurple = Color(0xFF7C3AED);

  static TextTheme _compactTextTheme(TextTheme base) {
    return base.copyWith(
      headlineLarge:
          base.headlineLarge?.copyWith(fontSize: 22, fontWeight: FontWeight.w800),
      headlineMedium:
          base.headlineMedium?.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      headlineSmall:
          base.headlineSmall?.copyWith(fontSize: 17, fontWeight: FontWeight.w700),
      titleLarge:
          base.titleLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
      titleMedium:
          base.titleMedium?.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
      titleSmall:
          base.titleSmall?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 13.5),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 12.5),
      bodySmall: base.bodySmall?.copyWith(fontSize: 11.5),
      labelLarge:
          base.labelLarge?.copyWith(fontSize: 12.5, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(fontSize: 11),
      labelSmall: base.labelSmall?.copyWith(fontSize: 10),
    );
  }

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.light,
      primary: const Color(0xFF1D4ED8),
      secondary: const Color(0xFF0284C7),
      tertiary: const Color(0xFF7C3AED),
      surface: const Color(0xFFFFFFFF),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFFEFF3F9),
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      textTheme: _compactTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 54,
        backgroundColor: const Color(0xFF0F2B66),
        foregroundColor: Colors.white,
        elevation: 4,
        shadowColor: const Color(0xFF0B1F4B).withOpacity(0.4),
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        elevation: 10,
        shadowColor: const Color(0xFF0F172A).withOpacity(0.22),
        indicatorColor: const Color(0xFF1D4ED8).withOpacity(0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? const Color(0xFF1D4ED8)
                : const Color(0xFF475569),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? const Color(0xFF1D4ED8)
                : const Color(0xFF64748B),
          );
        }),
      ),
      cardTheme: CardTheme(
        color: Colors.white,
        elevation: 6,
        shadowColor: const Color(0xFF0F172A).withOpacity(0.28),
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: const Color(0xFFCBD5E1).withOpacity(0.75),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF1D4ED8), width: 1.8),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF1D4ED8),
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF1D4ED8),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  static ThemeData dark() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _seedColor,
      brightness: Brightness.dark,
      primary: const Color(0xFF60A5FA),
      secondary: const Color(0xFF38BDF8),
      tertiary: const Color(0xFFA78BFA),
      surface: const Color(0xFF131D31),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: const Color(0xFF0A101F),
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      textTheme: _compactTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 54,
        backgroundColor: const Color(0xFF0E1A33),
        foregroundColor: Colors.white,
        elevation: 4,
        shadowColor: Colors.black.withOpacity(0.6),
        titleTextStyle: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.2,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: const Color(0xFF0F172A),
        elevation: 10,
        indicatorColor: const Color(0xFF3B82F6).withOpacity(0.24),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? const Color(0xFF93C5FD)
                : const Color(0xFF94A3B8),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected
                ? const Color(0xFF93C5FD)
                : const Color(0xFF94A3B8),
          );
        }),
      ),
      cardTheme: CardTheme(
        color: const Color(0xFF152036),
        elevation: 8,
        shadowColor: Colors.black.withOpacity(0.75),
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: const Color(0xFF334155).withOpacity(0.75),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        dense: true,
        visualDensity: VisualDensity.compact,
        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      ),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF152036),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF334155)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 1.8),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: const Color(0xFF2563EB),
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
