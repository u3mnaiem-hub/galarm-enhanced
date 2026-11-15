import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../data/platform/native_alarm_channel.dart';
import '../../data/platform/native_voice_channel.dart';
import '../../data/remote/firestore_service.dart';
import '../../data/repositories/alarm_repository.dart';
import '../../domain/entities/alarm.dart';

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
  return null;
});

final alarmRepositoryProvider = Provider<AlarmRepository>((ref) {
  return AlarmRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(nativeAlarmChannelProvider),
    null,
  );
});

final alarmsStreamProvider = StreamProvider<List<Alarm>>((ref) {
  return ref.watch(alarmRepositoryProvider).watchAlarms();
});

final notificationsStreamProvider = StreamProvider((ref) {
  return ref.watch(appDatabaseProvider).watchNotifications();
});

final blockedUsersStreamProvider = StreamProvider((ref) {
  return ref.watch(appDatabaseProvider).watchBlockedUsers();
});

final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);
final localeProvider = StateProvider<Locale?>((ref) => null);
final use24HourFormatProvider = StateProvider<bool>((ref) => false);
final defaultRingtoneUriProvider = StateProvider<String>((ref) => 'default');
final defaultRingtoneNameProvider = StateProvider<String>((ref) => '');
final currentUserIdProvider = StateProvider<String>((ref) => 'local_user');
final currentUserNameProvider = StateProvider<String>((ref) => 'Me');
