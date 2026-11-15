import 'dart:convert';
import 'package:flutter/services.dart';

class NativeAlarmChannel {
  static const _channel = MethodChannel('com.galarmenhanced/alarm');

  Future<bool> scheduleExactAlarm({
    required int alarmRequestCode,
    required String alarmId,
    required String title,
    required String notes,
    required int triggerAtMillisUtc,
    required String ringtoneUri,
    required double volume,
    required bool gradualVolume,
    required bool vibrate,
    required bool ringOnVibrateSilent,
    required int ringDurationSeconds,
    required int snoozeDurationMinutes,
    required int maxSnoozeCount,
    required int currentSnoozeCount,
    required String repeatRuleJson,
    required String creatorTimezoneId,
    required int startAtMillis,
    required int occurrenceCount,
  }) async {
    final result = await _channel.invokeMethod<bool>('scheduleExactAlarm', {
      'requestCode': alarmRequestCode,
      'alarmId': alarmId,
      'title': title,
      'notes': notes,
      'triggerAtMillis': triggerAtMillisUtc,
      'ringtoneUri': ringtoneUri,
      'volume': volume,
      'gradualVolume': gradualVolume,
      'vibrate': vibrate,
      'ringOnVibrateSilent': ringOnVibrateSilent,
      'ringDurationSeconds': ringDurationSeconds,
      'snoozeDurationMinutes': snoozeDurationMinutes,
      'maxSnoozeCount': maxSnoozeCount,
      'currentSnoozeCount': currentSnoozeCount,
      'repeatRuleJson': repeatRuleJson,
      'creatorTimezoneId': creatorTimezoneId,
      'startAtMillis': startAtMillis,
      'occurrenceCount': occurrenceCount,
    });
    return result ?? false;
  }

  Future<List<Map<String, dynamic>>> consumeHistoryEvents() async {
    try {
      final raw = await _channel.invokeMethod<String>('consumeHistoryEvents');
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.whereType<Map<String, dynamic>>().toList();
      }
      return const [];
    } catch (_) {
      return const [];
    }
  }

  Future<void> cancelAlarm(int alarmRequestCode, String alarmId) async {
    await _channel.invokeMethod('cancelAlarm', {
      'requestCode': alarmRequestCode,
      'alarmId': alarmId,
    });
  }

  Future<void> stopRinging() async {
    await _channel.invokeMethod('stopRinging');
  }

  Future<bool> canScheduleExactAlarms() async {
    return await _channel.invokeMethod<bool>('canScheduleExactAlarms') ?? false;
  }

  Future<void> openExactAlarmSettings() async {
    await _channel.invokeMethod('openExactAlarmSettings');
  }

  Future<bool> canUseFullScreenIntent() async {
    return await _channel.invokeMethod<bool>('canUseFullScreenIntent') ?? true;
  }

  Future<void> openFullScreenIntentSettings() async {
    await _channel.invokeMethod('openFullScreenIntentSettings');
  }

  Future<bool> isIgnoringBatteryOptimizations() async {
    return await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations') ?? false;
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
  }

  Future<void> openAppNotificationSettings() async {
    await _channel.invokeMethod('openAppNotificationSettings');
  }

  Future<bool> isNotificationPolicyAccessGranted() async {
    return await _channel.invokeMethod<bool>('isNotificationPolicyAccessGranted') ?? false;
  }

  Future<void> openNotificationPolicySettings() async {
    await _channel.invokeMethod('openNotificationPolicySettings');
  }

  Future<String?> saveBackupToDownloads({
    required String fileName,
    required String content,
  }) async {
    return await _channel.invokeMethod<String>('saveBackupToDownloads', {
      'fileName': fileName,
      'content': content,
    });
  }

  Future<bool> saveBackupWithPicker({
    required String fileName,
    required String content,
  }) async {
    return await _channel.invokeMethod<bool>('saveBackupWithPicker', {
          'fileName': fileName,
          'content': content,
        }) ??
        false;
  }

  Future<bool> shareBackupFile({
    required String fileName,
    required String content,
  }) async {
    return await _channel.invokeMethod<bool>('shareBackupFile', {
          'fileName': fileName,
          'content': content,
        }) ??
        false;
  }
}
