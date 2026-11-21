import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'data/remote/fcm_alarm_service.dart';
import 'presentation/providers/app_providers.dart';
import 'presentation/screens/home_shell.dart';
import 'presentation/screens/onboarding_screen.dart';
import 'presentation/screens/phone_auth_screen.dart';
import 'presentation/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (_) {
    // Runs seamlessly in offline mode if Firebase is unavailable
  }
  tz_data.initializeTimeZones();
  await initializeDateFormatting();

  final prefs = await SharedPreferences.getInstance();
  final seenOnboarding = prefs.getBool('seen_onboarding') ?? false;
  final seenPhoneAuth = prefs.getBool('seen_phone_auth') ?? false;
  final savedDefaultRingtoneUri =
      prefs.getString('default_ringtone_uri') ?? 'default';
  final savedDefaultRingtoneName =
      prefs.getString('default_ringtone_name') ?? '';
  final savedUse24h = prefs.getBool('use_24h_format') ?? false;
  final savedSkipVoiceConfirm =
      prefs.getBool('skip_voice_confirmation') ?? false;
  final savedOfflineVoiceMode = prefs.getBool('offline_voice_mode') ?? false;
  final savedLocaleCode = prefs.getString('locale_code');
  final savedThemeStr = prefs.getString('theme_mode');

  String initialUid = 'local_user';
  String initialName = prefs.getString('user_name') ?? 'Me';
  String initialPhone = prefs.getString('user_phone') ?? '';

  if (Firebase.apps.isNotEmpty) {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      initialUid = user.uid;
      if (user.phoneNumber != null && user.phoneNumber!.isNotEmpty) {
        initialPhone = user.phoneNumber!;
      }
      if (user.displayName != null && user.displayName!.isNotEmpty) {
        initialName = user.displayName!;
      }
    }
  }

  ThemeMode initialThemeMode = ThemeMode.system;
  if (savedThemeStr == 'light') initialThemeMode = ThemeMode.light;
  if (savedThemeStr == 'dark') initialThemeMode = ThemeMode.dark;

  runApp(
    ProviderScope(
      overrides: [
        defaultRingtoneUriProvider
            .overrideWith((ref) => savedDefaultRingtoneUri),
        defaultRingtoneNameProvider
            .overrideWith((ref) => savedDefaultRingtoneName),
        use24HourFormatProvider.overrideWith((ref) => savedUse24h),
        skipVoiceConfirmationProvider
            .overrideWith((ref) => savedSkipVoiceConfirm),
        offlineVoiceModeProvider.overrideWith((ref) => savedOfflineVoiceMode),
        currentUserIdProvider.overrideWith((ref) => initialUid),
        currentUserNameProvider.overrideWith((ref) => initialName),
        currentUserPhoneProvider.overrideWith((ref) => initialPhone),
        localeProvider.overrideWith(
          (ref) => (savedLocaleCode != null && savedLocaleCode.isNotEmpty)
              ? Locale(savedLocaleCode)
              : null,
        ),
        themeModeProvider.overrideWith((ref) => initialThemeMode),
      ],
      child: GAlarmEnhancedApp(
        initialSeenOnboarding: seenOnboarding,
        initialIsSignedIn: initialUid != 'local_user',
      ),
    ),
  );
}

class GAlarmEnhancedApp extends ConsumerStatefulWidget {
  final bool initialSeenOnboarding;
  final bool initialIsSignedIn;
  const GAlarmEnhancedApp({
    super.key,
    required this.initialSeenOnboarding,
    required this.initialIsSignedIn,
  });

  @override
  ConsumerState<GAlarmEnhancedApp> createState() => _GAlarmEnhancedAppState();
}

class _GAlarmEnhancedAppState extends ConsumerState<GAlarmEnhancedApp> {
  late bool _seenOnboarding = widget.initialSeenOnboarding;
  late bool _passedPhoneAuth = widget.initialIsSignedIn;

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
    } else if (!_passedPhoneAuth) {
      home = PhoneAuthScreen(
        onAuthenticated: () {
          if (mounted) setState(() => _passedPhoneAuth = true);
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
