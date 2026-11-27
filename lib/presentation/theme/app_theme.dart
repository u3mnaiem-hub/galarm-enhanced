import 'package:flutter/material.dart';

enum AppColorTheme {
  royalBlue,
  emeraldGreen,
  royalPurple,
  sunsetOrange,
  crimsonRose,
  oceanTeal,
}

class AppThemePalette {
  final AppColorTheme theme;
  final String nameEn;
  final String nameAr;
  final Color primaryLight;
  final Color secondaryLight;
  final Color appBarLight;
  final Color scaffoldLight;
  final Color primaryDark;
  final Color secondaryDark;
  final Color appBarDark;
  final Color scaffoldDark;
  final Color cardDark;

  const AppThemePalette({
    required this.theme,
    required this.nameEn,
    required this.nameAr,
    required this.primaryLight,
    required this.secondaryLight,
    required this.appBarLight,
    required this.scaffoldLight,
    required this.primaryDark,
    required this.secondaryDark,
    required this.appBarDark,
    required this.scaffoldDark,
    required this.cardDark,
  });
}

class AppTheme {
  // Brand accent palette (kept for compatibility across screens)
  static const Color primaryBlue = Color(0xFF1E40AF);
  static const Color deepNavy = Color(0xFF0B2559);
  static const Color accentCyan = Color(0xFF0EA5E9);
  static const Color groupTeal = Color(0xFF0D9488);
  static const Color buddyPurple = Color(0xFF7C3AED);

  static const Map<AppColorTheme, AppThemePalette> palettes = {
    AppColorTheme.royalBlue: AppThemePalette(
      theme: AppColorTheme.royalBlue,
      nameEn: 'Royal Blue',
      nameAr: 'أزرق ملكي',
      primaryLight: Color(0xFF1D4ED8),
      secondaryLight: Color(0xFF0284C7),
      appBarLight: Color(0xFF0F2B66),
      scaffoldLight: Color(0xFFEFF3F9),
      primaryDark: Color(0xFF60A5FA),
      secondaryDark: Color(0xFF38BDF8),
      appBarDark: Color(0xFF0E1A33),
      scaffoldDark: Color(0xFF0A101F),
      cardDark: Color(0xFF152036),
    ),
    AppColorTheme.emeraldGreen: AppThemePalette(
      theme: AppColorTheme.emeraldGreen,
      nameEn: 'Emerald',
      nameAr: 'أخضر زمردي',
      primaryLight: Color(0xFF059669),
      secondaryLight: Color(0xFF0D9488),
      appBarLight: Color(0xFF064E3B),
      scaffoldLight: Color(0xFFECFDF5),
      primaryDark: Color(0xFF34D399),
      secondaryDark: Color(0xFF2DD4BF),
      appBarDark: Color(0xFF062E24),
      scaffoldDark: Color(0xFF071A15),
      cardDark: Color(0xFF102A23),
    ),
    AppColorTheme.royalPurple: AppThemePalette(
      theme: AppColorTheme.royalPurple,
      nameEn: 'Purple',
      nameAr: 'بنفسجي',
      primaryLight: Color(0xFF7C3AED),
      secondaryLight: Color(0xFF9333EA),
      appBarLight: Color(0xFF3B0764),
      scaffoldLight: Color(0xFFF5F3FF),
      primaryDark: Color(0xFFA78BFA),
      secondaryDark: Color(0xFFC084FC),
      appBarDark: Color(0xFF230E3B),
      scaffoldDark: Color(0xFF120A1E),
      cardDark: Color(0xFF1E1330),
    ),
    AppColorTheme.sunsetOrange: AppThemePalette(
      theme: AppColorTheme.sunsetOrange,
      nameEn: 'Sunset',
      nameAr: 'برتقالي غروب',
      primaryLight: Color(0xFFEA580C),
      secondaryLight: Color(0xFFD97706),
      appBarLight: Color(0xFF7C2D12),
      scaffoldLight: Color(0xFFFFF7ED),
      primaryDark: Color(0xFFFB923C),
      secondaryDark: Color(0xFFFBBF24),
      appBarDark: Color(0xFF3A1609),
      scaffoldDark: Color(0xFF1A0D07),
      cardDark: Color(0xFF2A160D),
    ),
    AppColorTheme.crimsonRose: AppThemePalette(
      theme: AppColorTheme.crimsonRose,
      nameEn: 'Crimson',
      nameAr: 'أحمر ياقوتي',
      primaryLight: Color(0xFFE11D48),
      secondaryLight: Color(0xFFDB2777),
      appBarLight: Color(0xFF881337),
      scaffoldLight: Color(0xFFFFF1F2),
      primaryDark: Color(0xFFFB7185),
      secondaryDark: Color(0xFFF472B6),
      appBarDark: Color(0xFF3B0B1B),
      scaffoldDark: Color(0xFF1A080E),
      cardDark: Color(0xFF2B101A),
    ),
    AppColorTheme.oceanTeal: AppThemePalette(
      theme: AppColorTheme.oceanTeal,
      nameEn: 'Ocean Teal',
      nameAr: 'فيروزي',
      primaryLight: Color(0xFF0D9488),
      secondaryLight: Color(0xFF0284C7),
      appBarLight: Color(0xFF134E4A),
      scaffoldLight: Color(0xFFF0FDFA),
      primaryDark: Color(0xFF2DD4BF),
      secondaryDark: Color(0xFF38BDF8),
      appBarDark: Color(0xFF0B2E2C),
      scaffoldDark: Color(0xFF071A19),
      cardDark: Color(0xFF112A29),
    ),
  };

  static AppColorTheme parseTheme(String? raw) {
    if (raw == null || raw.isEmpty) return AppColorTheme.royalBlue;
    return AppColorTheme.values.firstWhere(
      (e) => e.name == raw,
      orElse: () => AppColorTheme.royalBlue,
    );
  }

  static AppThemePalette paletteOf(AppColorTheme theme) {
    return palettes[theme] ?? palettes[AppColorTheme.royalBlue]!;
  }

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

  static ThemeData light([AppColorTheme colorTheme = AppColorTheme.royalBlue]) {
    final p = paletteOf(colorTheme);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: p.primaryLight,
      brightness: Brightness.light,
      primary: p.primaryLight,
      secondary: p.secondaryLight,
      tertiary: const Color(0xFF7C3AED),
      surface: const Color(0xFFFFFFFF),
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.scaffoldLight,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      textTheme: _compactTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 54,
        backgroundColor: p.appBarLight,
        foregroundColor: Colors.white,
        elevation: 4,
        shadowColor: p.appBarLight.withOpacity(0.45),
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
        indicatorColor: p.primaryLight.withOpacity(0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.primaryLight : const Color(0xFF475569),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? p.primaryLight : const Color(0xFF64748B),
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
          borderSide: BorderSide(color: p.primaryLight, width: 1.8),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primaryLight,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primaryLight,
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

  static ThemeData dark([AppColorTheme colorTheme = AppColorTheme.royalBlue]) {
    final p = paletteOf(colorTheme);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: p.primaryLight,
      brightness: Brightness.dark,
      primary: p.primaryDark,
      secondary: p.secondaryDark,
      tertiary: const Color(0xFFA78BFA),
      surface: p.cardDark,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: p.scaffoldDark,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      textTheme: _compactTextTheme(base.textTheme),
      appBarTheme: AppBarTheme(
        centerTitle: false,
        toolbarHeight: 54,
        backgroundColor: p.appBarDark,
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
        backgroundColor: p.appBarDark,
        elevation: 10,
        indicatorColor: p.primaryDark.withOpacity(0.24),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? p.primaryDark : const Color(0xFF94A3B8),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? p.primaryDark : const Color(0xFF94A3B8),
          );
        }),
      ),
      cardTheme: CardTheme(
        color: p.cardDark,
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
        fillColor: p.cardDark,
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
          borderSide: BorderSide(color: p.primaryDark, width: 1.8),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.primaryLight,
        foregroundColor: Colors.white,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: p.primaryLight,
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
