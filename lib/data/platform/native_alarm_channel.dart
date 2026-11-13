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
    });
    return result ?? false;
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
}
