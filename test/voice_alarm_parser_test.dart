import 'package:flutter_test/flutter_test.dart';
import 'package:galarm_enhanced/domain/entities/alarm.dart';
import 'package:galarm_enhanced/domain/services/voice_alarm_parser.dart';

void main() {
  final fixedNow = DateTime(2026, 11, 13, 10, 0);

  test('Parses Egyptian Arabic tomorrow half-past morning alarm', () {
    final intent = VoiceAlarmParser.parse(
      'صحيني بكرة الساعة 7 ونص الصبح تمرين الجيم',
      nowLocal: fixedNow,
    );
    expect(intent.action, VoiceIntentAction.createAlarm);
    expect(intent.localDateTime, DateTime(2026, 11, 14, 7, 30));
    expect(intent.title, contains('تمرين الجيم'));
  });

  test('Parses daily evening personal alarm in Arabic', () {
    final intent = VoiceAlarmParser.parse(
      'اعمل منبه كل يوم الساعة 8 مساءً الاجتماع',
      nowLocal: fixedNow,
    );
    expect(intent.action, VoiceIntentAction.createAlarm);
    expect(intent.alarmType, AlarmType.personal);
    expect(intent.repeatFrequency, RepeatFrequency.daily);
    expect(intent.localDateTime?.hour, 20);
  });

  test('Parses English wake-up command', () {
    final intent = VoiceAlarmParser.parse(
      'Wake me up tomorrow at 6:45 AM',
      nowLocal: fixedNow,
    );
    expect(intent.action, VoiceIntentAction.createAlarm);
    expect(intent.localDateTime, DateTime(2026, 11, 14, 6, 45));
  });

  test('Parses snooze command with minutes', () {
    final intent = VoiceAlarmParser.parse('أجل المنبه 10 دقائق', nowLocal: fixedNow);
    expect(intent.action, VoiceIntentAction.snoozeAlarm);
    expect(intent.snoozeMinutes, 10);
  });
}
