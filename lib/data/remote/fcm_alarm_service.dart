import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../domain/entities/alarm.dart';
import '../platform/native_alarm_channel.dart';
import '../repositories/alarm_repository.dart';
import 'firestore_service.dart';

/// Top-level FCM background handler: wakes up even when the app is terminated
/// and schedules the incoming buddy/group alarm natively via AlarmManager.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}

  final alarm = FcmAlarmService.parseAlarmFromFcmData(message.data);
  if (alarm != null && alarm.isEnabled) {
    final native = NativeAlarmChannel();
    await native.scheduleExactAlarm(
      alarmRequestCode: alarm.id.hashCode,
      alarmId: alarm.id,
      title: alarm.title,
      notes: alarm.notes,
      triggerAtMillisUtc: alarm.startAtUtc.toUtc().millisecondsSinceEpoch,
      ringtoneUri: 'default',
      volume: alarm.volume,
      gradualVolume: alarm.gradualVolume,
      vibrate: alarm.vibrate,
      ringOnVibrateSilent: alarm.ringOnVibrateSilent,
      ringDurationSeconds: alarm.snoozeConfig.ringDurationSeconds,
      snoozeDurationMinutes: alarm.snoozeConfig.snoozeDurationMinutes,
      maxSnoozeCount: alarm.snoozeConfig.maxSnoozeCount,
      currentSnoozeCount: 0,
      repeatRuleJson: alarm.repeatRule.toJsonString(),
      creatorTimezoneId: alarm.creatorTimezoneId,
      startAtMillis: alarm.startAtUtc.toUtc().millisecondsSinceEpoch,
      occurrenceCount: 0,
    );
  }
}

class FcmAlarmService {
  static bool _initialized = false;

  static Alarm? parseAlarmFromFcmData(Map<String, dynamic> data) {
    final kind = data['kind']?.toString() ?? '';
    if (kind != 'shared_alarm' && kind != 'participant_added') return null;

    final alarmId = data['alarmId']?.toString() ?? '';
    if (alarmId.isEmpty) return null;

    final startAtMillis = int.tryParse(data['startAtMillis']?.toString() ?? '');
    if (startAtMillis == null || startAtMillis <= 0) return null;

    final title = (data['title']?.toString() ?? '').trim();
    final notes = (data['notes']?.toString() ?? '').trim();
    final repeatJson = data['repeatRuleJson']?.toString() ?? '';
    final tz = (data['creatorTimezoneId']?.toString() ?? '').trim();
    final typeStr = data['type']?.toString() ?? 'buddy';

    return Alarm(
      id: alarmId,
      ownerId: data['ownerId']?.toString() ?? 'remote_user',
      title: title.isNotEmpty ? title : 'Shared Alarm',
      notes: notes,
      startAtUtc: DateTime.fromMillisecondsSinceEpoch(startAtMillis, isUtc: true),
      creatorTimezoneId: tz.isNotEmpty ? tz : 'Africa/Cairo',
      repeatRule: RepeatRule.fromJsonString(repeatJson),
      ringtoneUri: 'default',
      volume: double.tryParse(data['volume']?.toString() ?? '') ?? 0.9,
      gradualVolume: data['gradualVolume']?.toString() != 'false',
      vibrate: data['vibrate']?.toString() != 'false',
      ringOnVibrateSilent: data['ringOnVibrateSilent']?.toString() != 'false',
      type: AlarmType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => AlarmType.buddy,
      ),
      state: AlarmState.upcoming,
      isEnabled: data['isEnabled']?.toString() != 'false',
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }

  /// Registers FCM token for the signed-in user in Firestore and listens for foreground shared alarms.
  static Future<void> initializeAndRegisterToken({
    required String uid,
    String? phoneNumber,
    required FirestoreService firestore,
    required AlarmRepository repo,
  }) async {
    if (Firebase.apps.isEmpty || uid.isEmpty || uid == 'local_user') return;

    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final token = await messaging.getToken();
      if (token != null && token.isNotEmpty) {
        await firestore.updateFcmToken(uid, token, phoneNumber: phoneNumber);
      }

      if (!_initialized) {
        _initialized = true;
        messaging.onTokenRefresh.listen((newToken) {
          firestore.updateFcmToken(uid, newToken, phoneNumber: phoneNumber);
        });

        FirebaseMessaging.onMessage.listen((RemoteMessage message) async {
          final alarm = parseAlarmFromFcmData(message.data);
          if (alarm != null) {
            await repo.saveIncomingSharedAlarm(alarm);
          }
        });
      }
    } catch (_) {
      // Ignore FCM registration failures when offline
    }
  }
}
