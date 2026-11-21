import 'package:flutter_test/flutter_test.dart';
import 'package:galarm_enhanced/domain/entities/alarm.dart';
import 'package:galarm_enhanced/domain/services/voice_alarm_parser.dart';

void main() {
  // Fixed reference: Friday, 2026-11-13 10:00 AM
  final fixedNow = DateTime(2026, 11, 13, 10, 0);

  group('Required 7 Egyptian Arabic examples', () {
    test('1. "فكرني بكره الساعه ٧ الصبح اخد الدوا"', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني بكره الساعه ٧ الصبح اخد الدوا',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.needsClarification, isFalse);
      expect(intent.localDateTime, DateTime(2026, 11, 14, 7, 0));
      expect(intent.title, 'اخد الدوا');
    });

    test('2. "صحيني بعد بكره الساعة ستة ونص"', () {
      final intent = VoiceAlarmParser.parse(
        'صحيني بعد بكره الساعة ستة ونص',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.needsClarification, isFalse);
      expect(intent.localDateTime, DateTime(2026, 11, 15, 6, 30));
    });

    test('3. "نبهني كمان ساعة ونص أطلع الغسيل"', () {
      final intent = VoiceAlarmParser.parse(
        'نبهني كمان ساعة ونص أطلع الغسيل',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.needsClarification, isFalse);
      expect(intent.localDateTime, fixedNow.add(const Duration(minutes: 90)));
      expect(intent.title, 'أطلع الغسيل');
    });

    test('4. "فكرني كل يوم الساعة ١٠ بالليل أقفل الغاز"', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني كل يوم الساعة ١٠ بالليل أقفل الغاز',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.needsClarification, isFalse);
      expect(intent.repeatFrequency, RepeatFrequency.daily);
      expect(intent.localDateTime?.hour, 22);
      expect(intent.localDateTime?.minute, 0);
      expect(intent.title, 'أقفل الغاز');
    });

    test('5. "حطلي منبه يوم الخميس الساعة تسعة إلا ربع أروح الشغل"', () {
      final intent = VoiceAlarmParser.parse(
        'حطلي منبه يوم الخميس الساعة تسعة إلا ربع أروح الشغل',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.needsClarification, isFalse);
      // 2026-11-13 is Friday -> next Thursday is 2026-11-19
      expect(intent.localDateTime, DateTime(2026, 11, 19, 8, 45));
      expect(intent.title, 'أروح الشغل');
    });

    test('6a. "فكرني النهارده الساعة ٥ العصر أكلم ماما" (before 17:00)', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني النهارده الساعة ٥ العصر أكلم ماما',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.needsClarification, isFalse);
      expect(intent.localDateTime, DateTime(2026, 11, 13, 17, 0));
      expect(intent.title, 'أكلم ماما');
    });

    test('6b. "فكرني النهارده الساعة ٥ العصر أكلم ماما" (already passed -> asks)', () {
      final eveningNow = DateTime(2026, 11, 13, 19, 30);
      final intent = VoiceAlarmParser.parse(
        'فكرني النهارده الساعة ٥ العصر أكلم ماما',
        nowLocal: eveningNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.needsClarification, isTrue);
      expect(intent.clarificationQuestion, isNotEmpty);
      expect(intent.title, 'أكلم ماما');
    });

    test('7. "فكرني اشتري عيش" (no time -> needs_clarification)', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني اشتري عيش',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.needsClarification, isTrue);
      expect(intent.clarificationQuestion, 'تحب أفكرك امتى؟');
      expect(intent.title, 'اشتري عيش');
      expect(intent.structured?.datetime, isNull);
    });
  });

  group('10+ Egyptian Arabic dialect variations', () {
    test('8. Relative minutes with Arabic-Indic digits: كمان ١٠ دقايق', () {
      final intent = VoiceAlarmParser.parse(
        'نبهني كمان ١٠ دقايق أراجع الفرن',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, fixedNow.add(const Duration(minutes: 10)));
      expect(intent.title, 'أراجع الفرن');
    });

    test('9. Relative half hour: بعد نص ساعة', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني بعد نص ساعة أشرب مية',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, fixedNow.add(const Duration(minutes: 30)));
      expect(intent.title, 'أشرب مية');
    });

    test('10. Relative two hours: كمان ساعتين', () {
      final intent = VoiceAlarmParser.parse(
        'ظبطلي منبه كمان ساعتين معاد الدكتور',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, fixedNow.add(const Duration(hours: 2)));
      expect(intent.title, 'معاد الدكتور');
    });

    test('11. Custom weekdays repeat: كل اتنين وخميس', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني كل اتنين وخميس الساعة ٨ الصبح تمرين الجيم',
        nowLocal: fixedNow,
      );
      expect(intent.repeatFrequency, RepeatFrequency.weekly);
      expect(intent.repeatWeekdays, [DateTime.monday, DateTime.thursday]);
      expect(intent.localDateTime?.hour, 8);
      expect(intent.localDateTime?.minute, 0);
      expect(intent.title, 'تمرين الجيم');
    });

    test('12. Fraction وتلت (20 minutes past)', () {
      final intent = VoiceAlarmParser.parse(
        'صحيني بكره الساعة سبعة وتلت',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, DateTime(2026, 11, 14, 7, 20));
    });

    test('13. Fraction إلا تلت (20 minutes to)', () {
      final intent = VoiceAlarmParser.parse(
        'عايز منبه بكره الساعة تمانية إلا تلت أجهز الشنطة',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, DateTime(2026, 11, 14, 7, 40));
      expect(intent.title, 'أجهز الشنطة');
    });

    test('14. Fraction وخمسة (5 minutes past)', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني بكره الساعة ٩ وخمسة الصبح الاجتماع',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, DateTime(2026, 11, 14, 9, 5));
      expect(intent.title, 'الاجتماع');
    });

    test('15. Period الضهر resolves afternoon hour', () {
      final intent = VoiceAlarmParser.parse(
        'نبهني بكره الساعة ٢ الضهر أصلي',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, DateTime(2026, 11, 14, 14, 0));
      expect(intent.title, 'أصلي');
    });

    test('16. Period المغرب resolves PM', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني النهارده الساعة ٦ المغرب أروح النادي',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, DateTime(2026, 11, 13, 18, 0));
      expect(intent.title, 'أروح النادي');
    });

    test('17. Period العشا resolves PM', () {
      final intent = VoiceAlarmParser.parse(
        'فكرني الليلة الساعة ٨ العشا أكلم أحمد',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, DateTime(2026, 11, 13, 20, 0));
      expect(intent.title, 'أكلم أحمد');
    });

    test('18. Period بعد نص الليل resolves AM after midnight', () {
      final intent = VoiceAlarmParser.parse(
        'صحيني الساعة ١ بعد نص الليل أتابع الماتش',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, DateTime(2026, 11, 14, 1, 0));
      expect(intent.title, 'أتابع الماتش');
    });

    test('19. No period given picks next upcoming occurrence', () {
      // At 10:00 AM, "الساعة ٥" should resolve to today 17:00
      final intent = VoiceAlarmParser.parse(
        'فكرني الساعة ٥ أروح الجيم',
        nowLocal: fixedNow,
      );
      expect(intent.localDateTime, DateTime(2026, 11, 13, 17, 0));
      expect(intent.title, 'أروح الجيم');
    });

    test('20. Next week + English mixed alarm', () {
      final intent = VoiceAlarmParser.parse(
        'Wake me up tomorrow at 6:45 AM',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.createAlarm);
      expect(intent.localDateTime, DateTime(2026, 11, 14, 6, 45));
    });

    test('21. Snooze command with minutes', () {
      final intent = VoiceAlarmParser.parse(
        'أجل المنبه ١٠ دقائق',
        nowLocal: fixedNow,
      );
      expect(intent.action, VoiceIntentAction.snoozeAlarm);
      expect(intent.snoozeMinutes, 10);
    });
  });

  group('Confirmation & voice correction replies', () {
    test('Confirm reply: أيوه / تمام / احفظ', () {
      expect(
        VoiceAlarmParser.parseConfirmationReply('أيوه احفظ').type,
        VoiceReplyType.confirm,
      );
      expect(
        VoiceAlarmParser.parseConfirmationReply('تمام').type,
        VoiceReplyType.confirm,
      );
    });

    test('Edit reply: لا / غيّر', () {
      expect(
        VoiceAlarmParser.parseConfirmationReply('لا غيّر').type,
        VoiceReplyType.edit,
      );
    });

    test('Modify time reply: خليها ٨', () {
      final reply = VoiceAlarmParser.parseConfirmationReply(
        'خليها ٨',
        nowLocal: fixedNow,
      );
      expect(reply.type, VoiceReplyType.modifyTime);
      expect(reply.newTime, (8, 0));
    });

    test('Modify time reply: خليها ٨ ونص بالليل', () {
      final reply = VoiceAlarmParser.parseConfirmationReply(
        'خليها ٨ ونص بالليل',
        nowLocal: fixedNow,
      );
      expect(reply.type, VoiceReplyType.modifyTime);
      expect(reply.newTime, (20, 30));
    });

    test('Egyptian TTS confirmation prompt formatting', () {
      final prompt = VoiceAlarmParser.buildEgyptianConfirmationPrompt(
        title: 'اخد الدوا',
        localDt: DateTime(2026, 11, 14, 7, 0),
        repeatRule: const RepeatRule(),
        nowLocal: fixedNow,
      );
      expect(prompt, 'تمام، هفكرك بكره الساعة 7 الصبح: اخد الدوا. أحفظ؟');
    });
  });
}
