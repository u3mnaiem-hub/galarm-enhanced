import '../entities/alarm.dart';

enum VoiceIntentAction {
  createAlarm,
  disableAlarm,
  enableAlarm,
  deleteAlarm,
  snoozeAlarm,
  markDone,
  unknown,
}

class VoiceAlarmIntent {
  final VoiceIntentAction action;
  final String? title;
  final DateTime? localDateTime;
  final RepeatFrequency repeatFrequency;
  final AlarmType alarmType;
  final int? snoozeMinutes;
  final String rawText;

  const VoiceAlarmIntent({
    required this.action,
    this.title,
    this.localDateTime,
    this.repeatFrequency = RepeatFrequency.none,
    this.alarmType = AlarmType.personal,
    this.snoozeMinutes,
    required this.rawText,
  });
}

class VoiceAlarmParser {
  /// Parses Egyptian Arabic, Standard Arabic, or English voice commands into a [VoiceAlarmIntent].
  static VoiceAlarmIntent parse(String rawText, {DateTime? nowLocal}) {
    final now = nowLocal ?? DateTime.now();
    final text = rawText.trim();
    final lower = text.toLowerCase();

    if (text.isEmpty) {
      return VoiceAlarmIntent(action: VoiceIntentAction.unknown, rawText: rawText);
    }

    // 1. Snooze intent
    if (_containsAny(lower, ['غفوة', 'أجل', 'اجل', 'snooze'])) {
      final mins = _extractFirstInt(lower) ?? 5;
      return VoiceAlarmIntent(
        action: VoiceIntentAction.snoozeAlarm,
        snoozeMinutes: mins,
        rawText: rawText,
      );
    }

    // 2. Mark done intent
    if (_containsAny(lower, ['تم', 'خلصت', 'اكتمل', 'mark done', 'done'])) {
      return VoiceAlarmIntent(
        action: VoiceIntentAction.markDone,
        rawText: rawText,
      );
    }

    // 3. Disable / Delete intent
    if (_containsAny(lower, ['اقفل', 'أقفل', 'عطل', 'ايقاف', 'إيقاف', 'disable', 'turn off'])) {
      return VoiceAlarmIntent(
        action: VoiceIntentAction.disableAlarm,
        title: _extractTargetQuery(text),
        rawText: rawText,
      );
    }
    if (_containsAny(lower, ['امسح', 'احذف', 'الغي', 'ألغي', 'delete', 'remove', 'cancel'])) {
      return VoiceAlarmIntent(
        action: VoiceIntentAction.deleteAlarm,
        title: _extractTargetQuery(text),
        rawText: rawText,
      );
    }

    // 4. Create alarm intent
    final parsedTime = _extractTime(lower, now);
    if (parsedTime != null ||
        _containsAny(lower, ['منبه', 'صحيني', 'ذكرني', 'alarm', 'wake me', 'remind'])) {
      final targetDate = _extractDate(lower, now);
      var dt = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        parsedTime?.$1 ?? (now.hour + 1) % 24,
        parsedTime?.$2 ?? 0,
      );
      if (parsedTime != null &&
          targetDate.year == now.year &&
          targetDate.month == now.month &&
          targetDate.day == now.day &&
          dt.isBefore(now)) {
        dt = dt.add(const Duration(days: 1));
      }

      final repeat = _extractRepeat(lower);
      final type = _containsAny(lower, ['جماعي', 'مجموعة', 'group'])
          ? AlarmType.group
          : _containsAny(lower, ['صديق', 'لصديق', 'buddy'])
              ? AlarmType.buddy
              : AlarmType.personal;

      final title = _extractCreateTitle(text);

      return VoiceAlarmIntent(
        action: VoiceIntentAction.createAlarm,
        title: title.isEmpty ? 'Voice Alarm' : title,
        localDateTime: dt,
        repeatFrequency: repeat,
        alarmType: type,
        rawText: rawText,
      );
    }

    return VoiceAlarmIntent(action: VoiceIntentAction.unknown, rawText: rawText);
  }

  static bool _containsAny(String haystack, List<String> needles) =>
      needles.any((n) => haystack.contains(n));

  static int? _extractFirstInt(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    return m != null ? int.tryParse(m.group(0)!) : null;
  }

  static DateTime _extractDate(String lower, DateTime now) {
    if (_containsAny(lower, ['بعد بكرة', 'بعد غد', 'day after tomorrow'])) {
      return now.add(const Duration(days: 2));
    }
    if (_containsAny(lower, ['بكرة', 'بكرا', 'غدا', 'غداً', 'tomorrow'])) {
      return now.add(const Duration(days: 1));
    }
    return now;
  }

  static RepeatFrequency _extractRepeat(String lower) {
    if (_containsAny(lower, ['كل ساعة', 'hourly'])) return RepeatFrequency.hourly;
    if (_containsAny(lower, ['كل يوم', 'يومي', 'يوميا', 'يومياً', 'daily', 'every day'])) {
      return RepeatFrequency.daily;
    }
    if (_containsAny(lower, ['كل اسبوع', 'كل أسبوع', 'أسبوعي', 'اسبوعي', 'weekly'])) {
      return RepeatFrequency.weekly;
    }
    if (_containsAny(lower, ['كل شهر', 'شهري', 'monthly'])) return RepeatFrequency.monthly;
    return RepeatFrequency.none;
  }

  static (int, int)? _extractTime(String lower, DateTime now) {
    // Match HH:MM (optional AM/PM)
    final colonMatch =
        RegExp(r'(\d{1,2})\s*:\s*(\d{2})\s*(am|pm|ص|م)?').firstMatch(lower);
    if (colonMatch != null) {
      var h = int.parse(colonMatch.group(1)!);
      final m = int.parse(colonMatch.group(2)!).clamp(0, 59);
      final period = colonMatch.group(3);
      h = _applyAmPm(h, lower, explicitPeriod: period);
      return (h.clamp(0, 23), m);
    }

    // Match Arabic/English hour with optional half/quarter: "الساعة 7 ونص", "at 7 pm", "8 إلا ربع"
    final hourMatch = RegExp(
            r'(?:الساعة|الساعه|ساعة|at)?\s*(\d{1,2})\s*(ونص|ونصف|وربع|الا ربع|إلا ربع|am|pm)?')
        .firstMatch(lower);
    if (hourMatch != null && hourMatch.group(1) != null) {
      var h = int.parse(hourMatch.group(1)!);
      if (h > 23) return null;
      var m = 0;
      final mod = hourMatch.group(2) ?? '';
      if (mod.contains('نص')) m = 30;
      if (mod == 'وربع') m = 15;
      if (mod.contains('الا ربع') || mod.contains('إلا ربع')) {
        h = (h - 1) < 0 ? 23 : h - 1;
        m = 45;
      }
      h = _applyAmPm(h, lower, explicitPeriod: mod);
      return (h.clamp(0, 23), m);
    }

    return null;
  }

  static int _applyAmPm(int hour, String lower, {String? explicitPeriod}) {
    final isPm = explicitPeriod == 'pm' ||
        explicitPeriod == 'م' ||
        _containsAny(lower, ['مساء', 'بالليل', 'بليل', 'العصر', 'المغرب', 'pm']);
    final isAm = explicitPeriod == 'am' ||
        explicitPeriod == 'ص' ||
        _containsAny(lower, ['صباح', 'الصبح', 'الفجر', 'am']);

    if (isPm && hour < 12) return hour + 12;
    if (isAm && hour == 12) return 0;
    return hour;
  }

  static String _extractCreateTitle(String raw) {
    // Strip common command/time filler words to leave the meaningful alarm label
    var cleaned = raw
        .replaceAll(
            RegExp(
                r'(اعمل|اضبط|ضبط|صحيني|ذكرني|منبه|جماعي|لصديق|بكرة|بكرا|غدا|غداً|النهاردة|اليوم|الساعة|الساعه|كل يوم|يوميا|يومياً|يومي|الصبح|صباحا|صباحاً|مساء|مساءً|بالليل|ونص|ونصف|وربع|إلا ربع|الا ربع)'),
            ' ')
        .replaceAll(
            RegExp(r'\b(wake me up|set|create|alarm|remind me|tomorrow|today|daily|group|buddy|at|am|pm|for)\b',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\d{1,2}(:\d{2})?'), ' ')
        .replaceAll(RegExp(r'^(لـ|ل|عشان|على)\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned;
  }

  static String _extractTargetQuery(String raw) {
    return raw
        .replaceAll(
            RegExp(r'(اقفل|أقفل|عطل|امسح|احذف|الغي|ألغي|منبه|disable|delete|remove|cancel|alarm)',
                caseSensitive: false),
            ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
