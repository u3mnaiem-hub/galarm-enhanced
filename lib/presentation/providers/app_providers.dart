import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../data/platform/native_alarm_channel.dart';
import '../../data/platform/native_voice_channel.dart';
import '../../data/remote/firestore_service.dart';
import '../../data/repositories/alarm_repository.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/entities/buddy_group.dart';
import '../theme/app_theme.dart';

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final nativeAlarmChannelProvider = Provider<NativeAlarmChannel>((ref) {
  return NativeAlarmChannel();
});

final nativeVoiceChannelProvider = Provider<NativeVoiceChannel>((ref) {
  return NativeVoiceChannel();
});

final firestoreServiceProvider = Provider<FirestoreService?>((ref) {
  if (Firebase.apps.isEmpty) return null;
  return FirestoreService();
});

final alarmRepositoryProvider = Provider<AlarmRepository>((ref) {
  return AlarmRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(nativeAlarmChannelProvider),
    ref.watch(firestoreServiceProvider),
    () => ref.read(currentUserIdProvider),
    () => ref.read(currentUserNameProvider),
  );
});

final alarmsStreamProvider = StreamProvider<List<Alarm>>((ref) {
  return ref.watch(alarmRepositoryProvider).watchAlarms();
});

final buddiesStreamProvider = StreamProvider<List<SavedBuddy>>((ref) {
  return ref.watch(alarmRepositoryProvider).watchBuddies();
});

final groupsStreamProvider = StreamProvider<List<SavedGroup>>((ref) {
  return ref.watch(alarmRepositoryProvider).watchGroups();
});

final notificationsStreamProvider = StreamProvider((ref) {
  return ref.watch(appDatabaseProvider).watchNotifications();
});

final blockedUsersStreamProvider = StreamProvider((ref) {
  return ref.watch(appDatabaseProvider).watchBlockedUsers();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final colorThemeProvider =
    StateProvider<AppColorTheme>((ref) => AppColorTheme.royalBlue);
final localeProvider = StateProvider<Locale?>((ref) => null);
final use24HourFormatProvider = StateProvider<bool>((ref) => false);
final defaultRingtoneUriProvider = StateProvider<String>((ref) => 'default');
final defaultRingtoneNameProvider = StateProvider<String>((ref) => '');
final currentUserIdProvider = StateProvider<String>((ref) => 'local_user');
final currentUserNameProvider = StateProvider<String>((ref) => 'Me');
final currentUserPhoneProvider = StateProvider<String>((ref) => '');
final skipVoiceConfirmationProvider = StateProvider<bool>((ref) => false);
final offlineVoiceModeProvider = StateProvider<bool>((ref) => false);
