import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'presentation/providers/app_providers.dart';
import 'presentation/screens/home_shell.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Runs seamlessly in offline mode if Firebase is not configured
  }
  tz_data.initializeTimeZones();
  await initializeDateFormatting();

  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  final savedDefaultRingtoneUri = prefs.getString('default_ringtone_uri') ?? 'default';
  final savedDefaultRingtoneName = prefs.getString('default_ringtone_name') ?? '';
  final savedUse24h = prefs.getBool('use_24h_format') ?? false;
  final savedSkipVoiceConfirm = prefs.getBool('skip_voice_confirmation') ?? false;
  final savedOfflineVoiceMode = prefs.getBool('offline_voice_mode') ?? false;
  final savedLocaleCode = prefs.getString('locale_code');
  final savedThemeStr = prefs.getString('theme_mode');

  ThemeMode initialThemeMode = ThemeMode.system;
  if (savedThemeStr == 'light') initialThemeMode = ThemeMode.light;
  if (savedThemeStr == 'dark') initialThemeMode = ThemeMode.dark;

  runApp(
    ProviderScope(
      overrides: [
        defaultRingtoneUriProvider.overrideWith((ref) => savedDefaultRingtoneUri),
        defaultRingtoneNameProvider.overrideWith((ref) => savedDefaultRingtoneName),
        use24HourFormatProvider.overrideWith((ref) => savedUse24h),
        skipVoiceConfirmationProvider.overrideWith((ref) => savedSkipVoiceConfirm),
        offlineVoiceModeProvider.overrideWith((ref) => savedOfflineVoiceMode),
        localeProvider.overrideWith(
          (ref) => (savedLocaleCode != null && savedLocaleCode.isNotEmpty)
              ? Locale(savedLocaleCode)
              : null,
        ),
        themeModeProvider.overrideWith((ref) => initialThemeMode),
      ],
      child: GAlarmEnhancedApp(
        initialSeenOnboarding: seenOnboarding,
      ),
    ),
  );
}

class GAlarmEnhancedApp extends ConsumerStatefulWidget {
  final bool initialSeenOnboarding;
  const GAlarmEnhancedApp({
    super.key,
    required this.initialSeenOnboarding,
  });

  @override
  ConsumerState<GAlarmEnhancedApp> createState() => _GAlarmEnhancedAppState();
}

class _GAlarmEnhancedAppState extends ConsumerState<GAlarmEnhancedApp> {
  late bool _seenOnboarding = widget.initialSeenOnboarding;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    final Widget home;
    if (!_seenOnboarding) {
      home = OnboardingScreen(
        onFinished: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('seen_onboarding', true);
          if (mounted) setState(() => _seenOnboarding = true);
        },
      );
    } else {
      home = const HomeShell();
    }

    return MaterialApp(
      title: 'U3m Alarm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeMode,
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: home,
    );
  }
}
