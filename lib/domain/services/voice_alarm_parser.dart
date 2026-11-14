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
  final DateTime? explicitDate;
  final (int, int)? explicitTime;
  final bool isExplicitToday;
  final RepeatFrequency repeatFrequency;
  final AlarmType alarmType;
  final int? snoozeMinutes;
  final String rawText;

  const VoiceAlarmIntent({
    required this.action,
    this.title,
    this.localDateTime,
    this.explicitDate,
    this.explicitTime,
    this.isExplicitToday = false,
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

    // 4. Create alarm intent (or follow-up date/time answer)
    final parsedTime = _extractTime(lower, now);
    final extractedDateInfo = _extractDate(lower, now);
    final explicitDate = extractedDateInfo.$1;
    final isExplicitToday = extractedDateInfo.$2;

    if (parsedTime != null ||
        explicitDate != null ||
        _containsAny(lower, ['منبه', 'صحيني', 'ذكرني', 'alarm', 'wake me', 'remind'])) {
      final targetDate = explicitDate ?? now;
      var hour = parsedTime?.$1 ?? (now.hour + 1) % 24;
      final minute = parsedTime?.$2 ?? 0;

      // If user said "today" (اليوم / النهاردة), allow any time today up to 23:59 (11:59 PM)
      if (parsedTime != null &&
          targetDate.year == now.year &&
          targetDate.month == now.month &&
          targetDate.day == now.day) {
        var candidate = DateTime(targetDate.year, targetDate.month, targetDate.day, hour, minute);
        if (candidate.isBefore(now) && hour < 12) {
          final pmCandidate = DateTime(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            hour + 12,
            minute,
          );
          if (!pmCandidate.isBefore(now) || isExplicitToday) {
            hour += 12;
          }
        }
      }

      var dt = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        hour,
        minute,
      );

      if (!isExplicitToday &&
          explicitDate == null &&
          parsedTime != null &&
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
        explicitDate: explicitDate,
        explicitTime: parsedTime,
        isExplicitToday: isExplicitToday,
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

  static (DateTime?, bool) _extractDate(String lower, DateTime now) {
    if (_containsAny(lower, ['اليوم', 'النهاردة', 'النهارده', 'ليوم', 'today', 'tonight', 'الليلة'])) {
      return (DateTime(now.year, now.month, now.day), true);
    }
    if (_containsAny(lower, ['بعد بكرة', 'بعد غد', 'day after tomorrow'])) {
      final d = now.add(const Duration(days: 2));
      return (DateTime(d.year, d.month, d.day), false);
    }
    if (_containsAny(lower, ['بكرة', 'بكرا', 'غدا', 'غداً', 'tomorrow'])) {
      final d = now.add(const Duration(days: 1));
      return (DateTime(d.year, d.month, d.day), false);
    }

    final weekdayMap = <List<String>, int>{
      ['الاثنين', 'الإثنين', 'اتنين', 'monday']: DateTime.monday,
      ['الثلاثاء', 'التلات', 'ثلاثاء', 'tuesday']: DateTime.tuesday,
      ['الأربعاء', 'الاربعاء', 'الاربع', 'الأربع', 'wednesday']: DateTime.wednesday,
      ['الخميس', 'خميس', 'thursday']: DateTime.thursday,
      ['الجمعة', 'الجمعه', 'جمعة', 'friday']: DateTime.friday,
      ['السبت', 'سبت', 'saturday']: DateTime.saturday,
      ['الأحد', 'الاحد', 'الحد', 'أحد', 'sunday']: DateTime.sunday,
    };
    for (final entry in weekdayMap.entries) {
      if (_containsAny(lower, entry.key)) {
        var daysAhead = (entry.value - now.weekday) % 7;
        if (daysAhead == 0) daysAhead = 7;
        final d = now.add(Duration(days: daysAhead));
        return (DateTime(d.year, d.month, d.day), false);
      }
    }

    final dayMonthMatch = RegExp(r'يوم\s*(\d{1,2})(?:\s*[/\-]\s*(\d{1,2}))?').firstMatch(lower);
    if (dayMonthMatch != null) {
      final day = int.tryParse(dayMonthMatch.group(1)!) ?? now.day;
      final month = dayMonthMatch.group(2) != null
          ? (int.tryParse(dayMonthMatch.group(2)!) ?? now.month)
          : now.month;
      var year = now.year;
      var candidate = DateTime(year, month.clamp(1, 12), day.clamp(1, 31));
      if (candidate.isBefore(DateTime(now.year, now.month, now.day))) {
        candidate = DateTime(year + 1, month.clamp(1, 12), day.clamp(1, 31));
      }
      return (candidate, candidate.year == now.year && candidate.month == now.month && candidate.day == now.day);
    }

    return (null, false);
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
    // Match "11 و 59 دقيقة" or "11:59"
    final andMinutesMatch = RegExp(
            r'(?:الساعة|الساعه|ساعة|at)?\s*(\d{1,2})\s*(?:و|:\s*)(\d{1,2})\s*(?:دقيقة|دقيقه|دقائق|min|minutes)?\s*(am|pm|ص|م|صباحا|صباحاً|مساء|مساءً|بالليل|بليل)?')
        .firstMatch(lower);
    if (andMinutesMatch != null) {
      var h = int.parse(andMinutesMatch.group(1)!);
      final m = int.parse(andMinutesMatch.group(2)!).clamp(0, 59);
      final period = andMinutesMatch.group(3);
      h = _applyAmPm(h, lower, explicitPeriod: period);
      return (h.clamp(0, 23), m);
    }

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
            r'(?:الساعة|الساعه|ساعة|at)\s*(\d{1,2})\s*(ونص|ونصف|وربع|الا ربع|إلا ربع|am|pm|ص|م|صباحا|صباحاً|مساء|مساءً|بالليل|بليل)?|(\d{1,2})\s*(ونص|ونصف|وربع|الا ربع|إلا ربع|am|pm|ص|م|صباحا|صباحاً|مساء|مساءً|بالليل|بليل)')
        .firstMatch(lower);
    if (hourMatch != null) {
      final hStr = hourMatch.group(1) ?? hourMatch.group(3);
      final mod = hourMatch.group(2) ?? hourMatch.group(4) ?? '';
      if (hStr != null) {
        var h = int.parse(hStr);
        if (h > 23) return null;
        var m = 0;
        if (mod.contains('نص')) m = 30;
        if (mod == 'وربع') m = 15;
        if (mod.contains('الا ربع') || mod.contains('إلا ربع')) {
          h = (h - 1) < 0 ? 23 : h - 1;
          m = 45;
        }
        h = _applyAmPm(h, lower, explicitPeriod: mod);
        return (h.clamp(0, 23), m);
      }
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
