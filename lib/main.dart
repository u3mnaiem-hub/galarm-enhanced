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
import 'presentation/screens/phone_auth_screen.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz_data.initializeTimeZones();
  await initializeDateFormatting();

  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Offline / placeholder google-services.json fallback
  }

  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  final seenAuth = prefs.getBool('seen_auth') ?? false;

  runApp(
    ProviderScope(
      child: GAlarmEnhancedApp(
        initialSeenOnboarding: seenOnboarding,
        initialAuthenticated: seenAuth,
      ),
    ),
  );
}

class GAlarmEnhancedApp extends ConsumerStatefulWidget {
  final bool initialSeenOnboarding;
  final bool initialAuthenticated;
  const GAlarmEnhancedApp({
    super.key,
    required this.initialSeenOnboarding,
    this.initialAuthenticated = false,
  });

  @override
  ConsumerState<GAlarmEnhancedApp> createState() => _GAlarmEnhancedAppState();
}

class _GAlarmEnhancedAppState extends ConsumerState<GAlarmEnhancedApp> {
  late bool _seenOnboarding = widget.initialSeenOnboarding;
  late bool _authenticated = widget.initialAuthenticated;

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);

    Widget home;
    if (!_seenOnboarding) {
      home = OnboardingScreen(
        onFinished: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('seen_onboarding', true);
          if (mounted) setState(() => _seenOnboarding = true);
        },
      );
    } else if (!_authenticated) {
      home = PhoneAuthScreen(
        onAuthenticated: () async {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool('seen_auth', true);
          if (mounted) setState(() => _authenticated = true);
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
