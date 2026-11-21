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

enum VoiceReplyType {
  confirm,
  edit,
  modifyTime,
  unknown,
}

class VoiceConfirmationReply {
  final VoiceReplyType type;
  final (int, int)? newTime;
  final DateTime? newDate;
  final String rawText;

  const VoiceConfirmationReply({
    required this.type,
    this.newTime,
    this.newDate,
    required this.rawText,
  });
}

/// Structured output produced by the rule-based Egyptian Arabic voice parser.
class StructuredVoiceAlarmResult {
  final String title;
  final String? datetime; // ISO-8601 local/offset string or null if clarification needed
  final String repeat; // 'none' | 'daily' | 'weekly' | 'custom'
  final List<int> customWeekdays; // ISO-8601: 1 = Monday .. 7 = Sunday
  final bool needsClarification;
  final String? question;

  const StructuredVoiceAlarmResult({
    required this.title,
    this.datetime,
    this.repeat = 'none',
    this.customWeekdays = const [],
    this.needsClarification = false,
    this.question,
  });

  DateTime? get parsedLocalDateTime {
    if (datetime == null || datetime!.trim().isEmpty) return null;
    final dt = DateTime.tryParse(datetime!.trim());
    return dt?.toLocal();
  }

  RepeatRule toRepeatRule({int? dayOfMonth}) {
    final rep = repeat.toLowerCase().trim();
    if (rep == 'daily') {
      return const RepeatRule(frequency: RepeatFrequency.daily);
    }
    if (rep == 'weekly' || (rep == 'custom' && customWeekdays.isNotEmpty)) {
      return RepeatRule(
        frequency: RepeatFrequency.weekly,
        weekdays: customWeekdays,
      );
    }
    if (rep == 'hourly') {
      return const RepeatRule(frequency: RepeatFrequency.hourly);
    }
    if (rep == 'monthly') {
      return RepeatRule(
        frequency: RepeatFrequency.monthly,
        dayOfMonth: dayOfMonth,
      );
    }
    return const RepeatRule(frequency: RepeatFrequency.none);
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'datetime': datetime,
        'repeat': repeat,
        'custom_weekdays': customWeekdays,
        'needs_clarification': needsClarification,
        'question': question,
      };

  factory StructuredVoiceAlarmResult.fromJson(Map<String, dynamic> json) {
    final rawRepeat = (json['repeat']?.toString() ?? 'none').toLowerCase().trim();
    final parsedDays = <int>[];
    final rawDays = json['custom_weekdays'] ?? json['weekdays'] ?? json['days'];
    if (rawDays is List) {
      for (final d in rawDays) {
        if (d is num) {
          final v = d.toInt();
          if (v >= 1 && v <= 7 && !parsedDays.contains(v)) parsedDays.add(v);
        } else if (d is String) {
          final mapped = VoiceAlarmParser.weekdayNameToIso(d);
          if (mapped != null && !parsedDays.contains(mapped)) {
            parsedDays.add(mapped);
          }
        }
      }
    }
    String normalizedRepeat = rawRepeat;
    if (rawRepeat.contains('day') && rawRepeat != 'daily') {
      normalizedRepeat = 'weekly';
    }
    if (!const ['none', 'daily', 'weekly', 'custom', 'hourly', 'monthly']
        .contains(normalizedRepeat)) {
      normalizedRepeat = parsedDays.isNotEmpty ? 'weekly' : 'none';
    }

    return StructuredVoiceAlarmResult(
      title: (json['title']?.toString() ?? '').trim(),
      datetime: json['datetime']?.toString().trim().isEmpty == true
          ? null
          : json['datetime']?.toString().trim(),
      repeat: normalizedRepeat,
      customWeekdays: parsedDays,
      needsClarification: json['needs_clarification'] == true,
      question: json['question']?.toString().trim().isEmpty == true
          ? null
          : json['question']?.toString().trim(),
    );
  }
}

class VoiceAlarmIntent {
  final VoiceIntentAction action;
  final String? title;
  final DateTime? localDateTime;
  final DateTime? explicitDate;
  final (int, int)? explicitTime;
  final bool isExplicitToday;
  final RepeatFrequency repeatFrequency;
  final List<int> repeatWeekdays;
  final AlarmType alarmType;
  final int? snoozeMinutes;
  final bool needsClarification;
  final String? clarificationQuestion;
  final StructuredVoiceAlarmResult? structured;
  final String rawText;

  const VoiceAlarmIntent({
    required this.action,
    this.title,
    this.localDateTime,
    this.explicitDate,
    this.explicitTime,
    this.isExplicitToday = false,
    this.repeatFrequency = RepeatFrequency.none,
    this.repeatWeekdays = const [],
    this.alarmType = AlarmType.personal,
    this.snoozeMinutes,
    this.needsClarification = false,
    this.clarificationQuestion,
    this.structured,
    required this.rawText,
  });
}

class VoiceAlarmParser {
  static const _createTriggers = [
    'فكرني',
    'فكّرني',
    'نبهني',
    'نبّهني',
    'صحيني',
    'صحّيني',
    'ظبطلي منبه',
    'اضبطلي منبه',
    'اضبط منبه',
    'ضبطلي منبه',
    'حطلي منبه',
    'حط منبه',
    'عايز منبه',
    'عاوز منبه',
    'اعمل منبه',
    'اعملي منبه',
    'ذكرني',
    'ذكّرني',
    'منبه',
    'تذكير',
    'alarm',
    'wake me',
    'remind me',
    'remind',
  ];

  static const _weekdayGroups = <int, List<String>>{
    DateTime.monday: ['الاثنين', 'الإثنين', 'الاتنين', 'اثنين', 'اتنين', 'monday'],
    DateTime.tuesday: ['الثلاثاء', 'التلات', 'ثلاثاء', 'تلات', 'tuesday'],
    DateTime.wednesday: ['الأربعاء', 'الاربعاء', 'الأربع', 'الاربع', 'أربعاء', 'اربعاء', 'أربع', 'اربع', 'wednesday'],
    DateTime.thursday: ['الخميس', 'خميس', 'thursday'],
    DateTime.friday: ['الجمعة', 'الجمعه', 'جمعة', 'جمعه', 'friday'],
    DateTime.saturday: ['السبت', 'سبت', 'saturday'],
    DateTime.sunday: ['الأحد', 'الاحد', 'الحد', 'أحد', 'احد', 'sunday'],
  };

  static int? weekdayNameToIso(String name) {
    final low = name.toLowerCase().trim();
    for (final entry in _weekdayGroups.entries) {
      if (entry.value.any((v) => low == v || low.contains(v))) {
        return entry.key;
      }
    }
    return null;
  }

  /// Normalizes Arabic-Indic digits (٠١٢٣٤٥٦٧٨٩) and Eastern Arabic digits to Western 0-9.
  static String normalizeDigits(String input) {
    const arabicIndic = '٠١٢٣٤٥٦٧٨٩';
    const persianIndic = '۰۱۲۳۴۵۶۷۸۹';
    final sb = StringBuffer();
    for (final rune in input.runes) {
      final ch = String.fromCharCode(rune);
      final idxA = arabicIndic.indexOf(ch);
      if (idxA != -1) {
        sb.write(idxA);
        continue;
      }
      final idxP = persianIndic.indexOf(ch);
      if (idxP != -1) {
        sb.write(idxP);
        continue;
      }
      sb.write(ch);
    }
    return sb.toString();
  }

  /// Full Arabic normalization run before rule-based matching:
  /// - Removes diacritics (tashkeel) and tatweel
  /// - Unifies أ/إ/آ -> ا, ى -> ي, ة -> ه
  /// - Normalizes Arabic-Indic digits to 0-9
  /// - Normalizes whitespace and common Egyptian spelling variants
  static String normalizeArabic(String input) {
    var s = normalizeDigits(input);
    // Remove diacritics & tatweel
    s = s.replaceAll(RegExp(r'[\u064B-\u065F\u0670\u0640]'), '');
    // Unify Alef, Ya, Ta Marbuta
    s = s
        .replaceAll('أ', 'ا')
        .replaceAll('إ', 'ا')
        .replaceAll('آ', 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
    // Normalize common Egyptian spelling variants
    s = s
        .replaceAll('بكرا', 'بكره')
        .replaceAll('الظهر', 'الضهر')
        .replaceAll('العشاء', 'العشا')
        .replaceAll('دقائق', 'دقايق')
        .replaceAll('ثلث', 'تلت')
        .replaceAll('نصف', 'نص');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Replaces common Egyptian/Arabic number words with digits for time/duration parsing.
  static String _replaceArabicNumberWords(String input) {
    var s = input;
    const wbStart = r'(?<![\u0600-\u06FF])';
    const wbEnd = r'(?![\u0600-\u06FF])';
    // Order matters: longer/compound forms first
    final replacements = <(RegExp, String)>[
      (RegExp('$wbStart(?:اتناشر|إتناشر|اثنا عشر|إثنا عشر|اثنى عشر|تناشر)$wbEnd'), '12'),
      (RegExp('$wbStart(?:حداشر|إحدى عشر|احدى عشر|أحد عشر|احد عشر)$wbEnd'), '11'),
      (RegExp('$wbStart(?:خمسة\\s*و\\s*أربعين|خمسه\\s*و\\s*اربعين)$wbEnd'), '45'),
      (RegExp('$wbStart(?:تلاتين|ثلاثين)$wbEnd'), '30'),
      (RegExp('$wbStart(?:خمسة\\s*و\\s*عشرين|خمسه\\s*و\\s*عشرين)$wbEnd'), '25'),
      (RegExp('$wbStart(?:عشرين)$wbEnd'), '20'),
      (RegExp('$wbStart(?:خمستاشر|خمسة عشر|خمسه عشر)$wbEnd'), '15'),
      (RegExp('$wbStart(?:عشرة|عشره|عشر)$wbEnd'), '10'),
      (RegExp('$wbStart(?:تسعة|تسعه|تسع)$wbEnd'), '9'),
      (RegExp('$wbStart(?:تمانية|تمانيه|ثمانية|ثمانيه|تمنية|تمنيه|ثمان)$wbEnd'), '8'),
      (RegExp('$wbStart(?:سبعة|سبعه|سبع)$wbEnd'), '7'),
      (RegExp('$wbStart(?:ستة|سته|ست)$wbEnd'), '6'),
      (RegExp('$wbStart(?:خمسة|خمسه|خمس)$wbEnd'), '5'),
      (RegExp('$wbStart(?:أربعة|أربعه|اربعة|اربعه|أربع|اربع)$wbEnd'), '4'),
      (RegExp('$wbStart(?:تلاتة|تلاته|ثلاثة|ثلاثه|تلات|ثلاث)$wbEnd'), '3'),
      (RegExp('$wbStart(?:اتنين|اثنين|تنين)$wbEnd'), '2'),
      (RegExp('$wbStart(?:واحدة|واحده|واحد)$wbEnd'), '1'),
    ];
    for (final (re, val) in replacements) {
      s = s.replaceAll(re, val);
    }
    return s;
  }

  /// Parses confirmation / edit / time-correction replies during the confirmation step.
  static VoiceConfirmationReply parseConfirmationReply(
    String rawText, {
    DateTime? nowLocal,
  }) {
    final now = nowLocal ?? DateTime.now();
    final norm = normalizeArabic(rawText);
    final lower = norm.toLowerCase();

    // 1. Check if the user is giving a modified time (e.g. "خليها ٨", "خليه ٨ ونص", "لا خليها ٩ بالليل")
    final withWords = _replaceArabicNumberWords(lower);
    final extractedTime = _extractTime(withWords, now);
    final extractedDate = _extractDate(withWords, now).$1;
    final hasModifyCue = _containsAny(lower, [
      'خليها',
      'خليه',
      'خليهم',
      'غيرها',
      'غيره',
      'غيّرها',
      'غيّره',
      'بدلها',
      'بدله',
      'الساعة',
      'الساعه',
      'make it',
      'change to',
    ]);

    if (extractedTime != null || (hasModifyCue && extractedDate != null)) {
      return VoiceConfirmationReply(
        type: VoiceReplyType.modifyTime,
        newTime: extractedTime,
        newDate: extractedDate,
        rawText: rawText,
      );
    }

    // Handle bare number after "خليها 8" when no الساعة keyword was spoken
    if (hasModifyCue) {
      final bareNum = RegExp(r'\b(\d{1,2})\b').firstMatch(withWords);
      if (bareNum != null) {
        var h = int.parse(bareNum.group(1)!);
        if (h >= 0 && h <= 23) {
          var m = 0;
          if (withWords.contains('ونص') || withWords.contains('ونصف')) m = 30;
          if (withWords.contains('وربع')) m = 15;
          if (withWords.contains('وتلت') || withWords.contains('وثلث')) m = 20;
          if (withWords.contains('إلا ربع') || withWords.contains('الا ربع')) {
            h = (h - 1) < 0 ? 23 : h - 1;
            m = 45;
          }
          if (withWords.contains('إلا تلت') || withWords.contains('الا تلت')) {
            h = (h - 1) < 0 ? 23 : h - 1;
            m = 40;
          }
          h = _applyAmPm(h, withWords).$1;
          return VoiceConfirmationReply(
            type: VoiceReplyType.modifyTime,
            newTime: (h.clamp(0, 23), m),
            newDate: extractedDate,
            rawText: rawText,
          );
        }
      }
    }

    // 2. Confirm words
    if (_containsAny(lower, [
      'أيوه',
      'ايوه',
      'أيوة',
      'ايوة',
      'تمام',
      'ماشي',
      'موافق',
      'احفظ',
      'إحفظ',
      'احفظه',
      'حفظ',
      'سجل',
      'سجله',
      'أكيد',
      'اكيد',
      'اوكي',
      'أوكي',
      'نعم',
      'آه',
      'اه',
      'yes',
      'yeah',
      'ok',
      'okay',
      'save',
      'confirm',
    ])) {
      return VoiceConfirmationReply(
        type: VoiceReplyType.confirm,
        rawText: rawText,
      );
    }

    // 3. Reject / edit words
    if (_containsAny(lower, [
      'لا',
      'لأ',
      'غلط',
      'غير',
      'غيّر',
      'تغيير',
      'عدل',
      'عدّل',
      'تعديل',
      'الغي',
      'إلغي',
      'الغاء',
      'إلغاء',
      'no',
      'edit',
      'change',
      'cancel',
    ])) {
      return VoiceConfirmationReply(
        type: VoiceReplyType.edit,
        rawText: rawText,
      );
    }

    return VoiceConfirmationReply(
      type: VoiceReplyType.unknown,
      rawText: rawText,
    );
  }

  /// Parses Egyptian Arabic, Standard Arabic, or English voice commands into a [VoiceAlarmIntent].
  static VoiceAlarmIntent parse(String rawText, {DateTime? nowLocal}) {
    final now = nowLocal ?? DateTime.now();
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      return VoiceAlarmIntent(action: VoiceIntentAction.unknown, rawText: rawText);
    }

    final digitsNormalized = normalizeDigits(trimmed);
    final normalized = normalizeArabic(trimmed);
    final lower = normalized.toLowerCase();
    final hasExplicitCreateVerb = _containsAny(lower, [
      'فكرني',
      'نبهني',
      'صحيني',
      'ظبطلي',
      'اضبطلي',
      'اضبط منبه',
      'ضبطلي',
      'حطلي',
      'حط منبه',
      'عايز منبه',
      'عاوز منبه',
      'اعمل منبه',
      'اعملي منبه',
      'ذكرني',
      'wake me',
      'remind',
    ]);
    final hasCreateTrigger = hasExplicitCreateVerb || _containsAny(lower, _createTriggers);

    // Non-create commands only when NOT explicitly creating a reminder/alarm
    if (!hasExplicitCreateVerb) {
      // 1. Snooze intent
      if (_containsAny(lower, ['غفوه', 'غفوة', 'اجل', 'snooze'])) {
        final mins = _extractFirstInt(_replaceArabicNumberWords(lower)) ?? 5;
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
      if (_containsAny(lower, [
        'اقفل المنبه',
        'اقفل منبه',
        'عطل',
        'ايقاف',
        'disable',
        'turn off',
      ])) {
        return VoiceAlarmIntent(
          action: VoiceIntentAction.disableAlarm,
          title: _extractTargetQuery(digitsNormalized),
          rawText: rawText,
        );
      }
      if (_containsAny(lower, ['امسح', 'احذف', 'الغي', 'delete', 'remove', 'cancel'])) {
        return VoiceAlarmIntent(
          action: VoiceIntentAction.deleteAlarm,
          title: _extractTargetQuery(digitsNormalized),
          rawText: rawText,
        );
      }
    }

    // 4. Relative time ("بعد ساعة", "كمان ساعتين", "كمان ١٠ دقايق", "بعد نص ساعة", "كمان ساعة ونص")
    final relativeDuration = _extractRelativeDuration(lower);
    if (relativeDuration != null) {
      final dt = now.add(relativeDuration);
      final title = _extractCreateTitle(digitsNormalized);
      final finalTitle = title.isEmpty ? 'منبه صوتي' : title;
      final structured = StructuredVoiceAlarmResult(
        title: finalTitle,
        datetime: _formatLocalIso(dt),
        repeat: 'none',
        needsClarification: false,
      );
      return VoiceAlarmIntent(
        action: VoiceIntentAction.createAlarm,
        title: finalTitle,
        localDateTime: dt,
        explicitDate: DateTime(dt.year, dt.month, dt.day),
        explicitTime: (dt.hour, dt.minute),
        repeatFrequency: RepeatFrequency.none,
        alarmType: _detectAlarmType(lower),
        structured: structured,
        rawText: rawText,
      );
    }

    // 5. Absolute / recurring alarm parsing
    final (repeatFreq, repeatWeekdays) = _extractRepeat(lower);
    final timeReadyText = _replaceArabicNumberWords(lower);
    final parsedTimeInfo = _extractTimeWithPeriodFlag(timeReadyText, now);
    final parsedTime = parsedTimeInfo.$1;
    final hasExplicitPeriod = parsedTimeInfo.$2;

    final extractedDateInfo = _extractDate(
      lower,
      now,
      repeatWeekdays: repeatWeekdays,
    );
    final explicitDate = extractedDateInfo.$1;
    final isExplicitToday = extractedDateInfo.$2;

    if (parsedTime != null ||
        explicitDate != null ||
        repeatFreq != RepeatFrequency.none ||
        hasCreateTrigger) {
      final title = _extractCreateTitle(digitsNormalized);
      final finalTitle = title.isEmpty ? 'منبه صوتي' : title;
      final alarmType = _detectAlarmType(lower);

      // Missing time completely -> ask clarification!
      if (parsedTime == null) {
        final question = explicitDate != null
            ? 'الساعة كام تحب أفكرك؟'
            : 'تحب أفكرك امتى؟';
        final structured = StructuredVoiceAlarmResult(
          title: finalTitle,
          datetime: null,
          repeat: _repeatToString(repeatFreq, repeatWeekdays),
          customWeekdays: repeatWeekdays,
          needsClarification: true,
          question: question,
        );
        return VoiceAlarmIntent(
          action: VoiceIntentAction.createAlarm,
          title: finalTitle,
          explicitDate: explicitDate,
          explicitTime: null,
          isExplicitToday: isExplicitToday,
          repeatFrequency: repeatFreq,
          repeatWeekdays: repeatWeekdays,
          alarmType: alarmType,
          needsClarification: true,
          clarificationQuestion: question,
          structured: structured,
          rawText: rawText,
        );
      }

      final targetDate = explicitDate ?? DateTime(now.year, now.month, now.day);
      var hour = parsedTime.$1;
      final minute = parsedTime.$2;

      var dt = DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        hour,
        minute,
      );

      // If no period (AM/PM) was given and no explicit future date was given:
      // pick the next upcoming occurrence of that clock time.
      if (!hasExplicitPeriod && explicitDate == null) {
        if (!dt.isAfter(now)) {
          if (hour < 12) {
            final pmCandidate = DateTime(
              targetDate.year,
              targetDate.month,
              targetDate.day,
              hour + 12,
              minute,
            );
            if (pmCandidate.isAfter(now)) {
              dt = pmCandidate;
            } else {
              dt = dt.add(const Duration(days: 1));
            }
          } else {
            dt = dt.add(const Duration(days: 1));
          }
        }
      } else if (!hasExplicitPeriod && isExplicitToday) {
        // User said "النهارده" without period: if AM already passed, try PM today
        if (!dt.isAfter(now) && hour < 12) {
          final pmCandidate = DateTime(
            targetDate.year,
            targetDate.month,
            targetDate.day,
            hour + 12,
            minute,
          );
          if (pmCandidate.isAfter(now)) {
            dt = pmCandidate;
          }
        }
      } else if (hasExplicitPeriod &&
          explicitDate == null &&
          repeatFreq == RepeatFrequency.none &&
          !dt.isAfter(now)) {
        // E.g. user said "الساعة 7 الصبح" at 10 AM without saying "النهارده" -> next occurrence is tomorrow 07:00
        dt = dt.add(const Duration(days: 1));
      }

      // If user explicitly said "النهارده / اليوم" and the requested time already passed -> ask clarification!
      if (isExplicitToday && !dt.isAfter(now) && repeatFreq == RepeatFrequency.none) {
        final timeDesc = formatTimeArabic(dt);
        final question =
            'الساعة $timeDesc النهارده عدت بالفعل، تحب أظبطه بكره الساعة $timeDesc؟';
        final structured = StructuredVoiceAlarmResult(
          title: finalTitle,
          datetime: _formatLocalIso(dt),
          repeat: _repeatToString(repeatFreq, repeatWeekdays),
          customWeekdays: repeatWeekdays,
          needsClarification: true,
          question: question,
        );
        return VoiceAlarmIntent(
          action: VoiceIntentAction.createAlarm,
          title: finalTitle,
          localDateTime: dt,
          explicitDate: explicitDate,
          explicitTime: (dt.hour, dt.minute),
          isExplicitToday: true,
          repeatFrequency: repeatFreq,
          repeatWeekdays: repeatWeekdays,
          alarmType: alarmType,
          needsClarification: true,
          clarificationQuestion: question,
          structured: structured,
          rawText: rawText,
        );
      }

      // If repeat is daily/weekly and time already passed today, advance to next valid day
      if (repeatFreq == RepeatFrequency.daily &&
          explicitDate == null &&
          !dt.isAfter(now)) {
        dt = dt.add(const Duration(days: 1));
      } else if (repeatFreq == RepeatFrequency.weekly &&
          repeatWeekdays.isNotEmpty &&
          !dt.isAfter(now)) {
        dt = _nextMatchingWeekday(dt, repeatWeekdays, now);
      }

      final structured = StructuredVoiceAlarmResult(
        title: finalTitle,
        datetime: _formatLocalIso(dt),
        repeat: _repeatToString(repeatFreq, repeatWeekdays),
        customWeekdays: repeatWeekdays,
        needsClarification: false,
      );

      return VoiceAlarmIntent(
        action: VoiceIntentAction.createAlarm,
        title: finalTitle,
        localDateTime: dt,
        explicitDate: explicitDate,
        explicitTime: (dt.hour, dt.minute),
        isExplicitToday: isExplicitToday,
        repeatFrequency: repeatFreq,
        repeatWeekdays: repeatWeekdays,
        alarmType: alarmType,
        needsClarification: false,
        structured: structured,
        rawText: rawText,
      );
    }

    return VoiceAlarmIntent(action: VoiceIntentAction.unknown, rawText: rawText);
  }

  /// Formats an Egyptian Arabic confirmation prompt for TTS & UI.
  static String buildEgyptianConfirmationPrompt({
    required String title,
    required DateTime localDt,
    required RepeatRule repeatRule,
    DateTime? nowLocal,
  }) {
    final now = nowLocal ?? DateTime.now();
    final dayLabel = _formatDayEgyptian(localDt, now, repeatRule);
    final timeLabel = formatTimeArabic(localDt);
    final cleanTitle = title.trim().isEmpty ? 'المنبه' : title.trim();
    return 'تمام، هفكرك $dayLabel الساعة $timeLabel: $cleanTitle. أحفظ؟';
  }

  static String _formatDayEgyptian(
    DateTime dt,
    DateTime now,
    RepeatRule repeatRule,
  ) {
    if (repeatRule.frequency == RepeatFrequency.daily) {
      return 'كل يوم';
    }
    if (repeatRule.frequency == RepeatFrequency.weekly &&
        repeatRule.weekdays.isNotEmpty) {
      const names = {
        DateTime.monday: 'اتنين',
        DateTime.tuesday: 'تلات',
        DateTime.wednesday: 'أربع',
        DateTime.thursday: 'خميس',
        DateTime.friday: 'جمعة',
        DateTime.saturday: 'سبت',
        DateTime.sunday: 'أحد',
      };
      final joined =
          repeatRule.weekdays.map((d) => names[d] ?? '').where((s) => s.isNotEmpty).join(' و');
      return 'كل $joined';
    }
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dt.year, dt.month, dt.day);
    final diff = target.difference(today).inDays;
    if (diff == 0) return 'النهارده';
    if (diff == 1) return 'بكره';
    if (diff == 2) return 'بعد بكره';
    const dayNames = {
      DateTime.monday: 'يوم الاتنين',
      DateTime.tuesday: 'يوم التلات',
      DateTime.wednesday: 'يوم الأربع',
      DateTime.thursday: 'يوم الخميس',
      DateTime.friday: 'يوم الجمعة',
      DateTime.saturday: 'يوم السبت',
      DateTime.sunday: 'يوم الحد',
    };
    return dayNames[dt.weekday] ?? '${dt.day}/${dt.month}';
  }

  static String formatTimeArabic(DateTime dt) {
    final h24 = dt.hour;
    final m = dt.minute;
    final h12 = h24 % 12 == 0 ? 12 : h24 % 12;
    String period;
    if (h24 == 0) {
      period = 'بعد نص الليل';
    } else if (h24 < 5) {
      period = 'الفجر';
    } else if (h24 < 12) {
      period = 'الصبح';
    } else if (h24 == 12) {
      period = 'الضهر';
    } else if (h24 < 17) {
      period = 'العصر';
    } else if (h24 < 19) {
      period = 'المغرب';
    } else {
      period = 'بالليل';
    }
    final minPart = m == 0
        ? ''
        : (m == 30
            ? ' ونص'
            : (m == 15
                ? ' وربع'
                : ':${m.toString().padLeft(2, '0')}'));
    return '$h12$minPart $period';
  }

  static String _formatLocalIso(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$mo-${d}T$h:$mi:$s';
  }

  static String _repeatToString(RepeatFrequency freq, List<int> weekdays) {
    switch (freq) {
      case RepeatFrequency.daily:
        return 'daily';
      case RepeatFrequency.weekly:
        return weekdays.length > 1 ? 'custom' : 'weekly';
      case RepeatFrequency.hourly:
        return 'hourly';
      case RepeatFrequency.monthly:
        return 'monthly';
      default:
        return 'none';
    }
  }

  static AlarmType _detectAlarmType(String lower) {
    if (_containsAny(lower, ['مجموعة', 'مجموعه', 'جماعي', 'جروب', 'group'])) {
      return AlarmType.group;
    }
    if (_containsAny(lower, ['صديق', 'صاحبي', 'buddy'])) {
      return AlarmType.buddy;
    }
    return AlarmType.personal;
  }

  static bool _containsAny(String haystack, List<String> needles) =>
      needles.any((n) => haystack.contains(n));

  static int? _extractFirstInt(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    return m != null ? int.tryParse(m.group(0)!) : null;
  }

  static Duration? _extractRelativeDuration(String lower) {
    final s = _replaceArabicNumberWords(lower);

    // Must contain a relative cue ("بعد", "كمان", "خلال", "in")
    final cueMatch = RegExp(r'(?:بعد|كمان|خلال|in)\s+(.+)').firstMatch(s);
    if (cueMatch == null) return null;
    final tail = cueMatch.group(1)!;

    // Avoid confusing "بعد بكره" or "بعد نص الليل" with relative duration
    if (tail.startsWith('بكره') ||
        tail.startsWith('بكرة') ||
        tail.startsWith('بكرا') ||
        tail.startsWith('غد') ||
        tail.startsWith('نص الليل') ||
        tail.startsWith('نصف الليل')) {
      return null;
    }

    // "نص ساعة" / "نصف ساعة"
    if (RegExp(r'^(?:نص|نصف)\s*(?:ساعة|ساعه)').hasMatch(tail)) {
      return const Duration(minutes: 30);
    }
    // "ربع ساعة"
    if (RegExp(r'^ربع\s*(?:ساعة|ساعه)').hasMatch(tail)) {
      return const Duration(minutes: 15);
    }
    // "تلت ساعة" / "ثلث ساعة"
    if (RegExp(r'^(?:تلت|ثلث)\s*(?:ساعة|ساعه)').hasMatch(tail)) {
      return const Duration(minutes: 20);
    }
    // "ساعة إلا ربع"
    if (RegExp(r'^(?:ساعة|ساعه)\s*(?:إلا|الا)\s*ربع').hasMatch(tail)) {
      return const Duration(minutes: 45);
    }
    // "ساعة ونص" / "ساعة وربع" / "ساعة وتلت" / "ساعة"
    final singleHour = RegExp(
      r'^(?:ساعة|ساعه)(?:\s*(ونص|ونصف|وربع|وتلت|وثلث))?',
    ).firstMatch(tail);
    if (singleHour != null) {
      var mins = 60;
      final mod = singleHour.group(1) ?? '';
      if (mod.contains('نص')) mins += 30;
      if (mod.contains('ربع')) mins += 15;
      if (mod.contains('تلت') || mod.contains('ثلث')) mins += 20;
      return Duration(minutes: mins);
    }
    // "ساعتين" (+ optional ونص / وربع)
    final twoHours = RegExp(
      r'^ساعتين(?:\s*(ونص|ونصف|وربع))?',
    ).firstMatch(tail);
    if (twoHours != null) {
      var mins = 120;
      final mod = twoHours.group(1) ?? '';
      if (mod.contains('نص')) mins += 30;
      if (mod.contains('ربع')) mins += 15;
      return Duration(minutes: mins);
    }
    // "N ساعات" / "N hours"
    final nHours = RegExp(
      r'^(\d{1,2})\s*(?:ساعات|ساعة|ساعه|hours|hour|hrs|hr)(?:\s*(ونص|ونصف|وربع))?',
    ).firstMatch(tail);
    if (nHours != null) {
      var mins = int.parse(nHours.group(1)!) * 60;
      final mod = nHours.group(2) ?? '';
      if (mod.contains('نص')) mins += 30;
      if (mod.contains('ربع')) mins += 15;
      return Duration(minutes: mins);
    }
    // "دقيقتين"
    if (RegExp(r'^دقيقتين').hasMatch(tail)) {
      return const Duration(minutes: 2);
    }
    // "دقيقة"
    if (RegExp(r'^(?:دقيقة|دقيقه)(?![\u0600-\u06FF])').hasMatch(tail)) {
      return const Duration(minutes: 1);
    }
    // "N دقايق" / "N minutes"
    final nMins = RegExp(
      r'^(\d{1,3})\s*(?:دقايق|دقائق|دقيقة|دقيقه|minutes|minute|mins|min)',
    ).firstMatch(tail);
    if (nMins != null) {
      return Duration(minutes: int.parse(nMins.group(1)!));
    }
    return null;
  }

  static (RepeatFrequency, List<int>) _extractRepeat(String lower) {
    if (_containsAny(lower, ['كل ساعة', 'كل ساعه', 'hourly'])) {
      return (RepeatFrequency.hourly, const []);
    }
    if (_containsAny(lower, ['كل يوم', 'يومي', 'يوميا', 'يومياً', 'daily', 'every day'])) {
      return (RepeatFrequency.daily, const []);
    }
    if (_containsAny(lower, ['كل شهر', 'شهري', 'monthly'])) {
      return (RepeatFrequency.monthly, const []);
    }

    // Check "كل" + one or more weekdays (e.g. "كل اتنين وخميس")
    final hasEvery = lower.contains('كل ') || lower.contains('every ');
    if (hasEvery) {
      final days = _extractAllWeekdays(lower);
      if (days.isNotEmpty) {
        return (RepeatFrequency.weekly, days);
      }
      if (_containsAny(lower, ['كل اسبوع', 'كل أسبوع', 'أسبوعي', 'اسبوعي', 'weekly'])) {
        return (RepeatFrequency.weekly, const []);
      }
    }

    if (_containsAny(lower, ['أسبوعي', 'اسبوعي', 'weekly'])) {
      return (RepeatFrequency.weekly, const []);
    }

    return (RepeatFrequency.none, const []);
  }

  static List<int> _extractAllWeekdays(String lower) {
    final found = <int>[];
    for (final entry in _weekdayGroups.entries) {
      if (_containsAny(lower, entry.value)) {
        found.add(entry.key);
      }
    }
    found.sort();
    return found;
  }

  static (DateTime?, bool) _extractDate(
    String lower,
    DateTime now, {
    List<int> repeatWeekdays = const [],
  }) {
    final today = DateTime(now.year, now.month, now.day);

    // Check "بعد بكره" BEFORE "بكره"
    if (_containsAny(lower, ['بعد بكرة', 'بعد بكره', 'بعد بكرا', 'بعد غد', 'day after tomorrow'])) {
      return (today.add(const Duration(days: 2)), false);
    }
    if (_containsAny(lower, ['بكرة', 'بكره', 'بكرا', 'غدا', 'غداً', 'tomorrow'])) {
      return (today.add(const Duration(days: 1)), false);
    }
    if (_containsAny(lower, ['اليوم', 'النهاردة', 'النهارده', 'الليلة', 'الليله', 'today', 'tonight'])) {
      return (today, true);
    }

    final isNextWeek = _containsAny(lower, [
      'الأسبوع الجاي',
      'الاسبوع الجاي',
      'الأسبوع القادم',
      'الاسبوع القادم',
      'next week',
    ]);

    final weekdays = repeatWeekdays.isNotEmpty
        ? repeatWeekdays
        : _extractAllWeekdays(lower);
    if (weekdays.isNotEmpty) {
      // Pick the nearest upcoming weekday among the mentioned ones
      int minDaysAhead = 999;
      for (final wd in weekdays) {
        var diff = (wd - now.weekday) % 7;
        if (diff == 0 && repeatWeekdays.isEmpty) diff = 7;
        if (isNextWeek && diff < 7) diff += 7;
        if (diff < minDaysAhead) minDaysAhead = diff;
      }
      return (today.add(Duration(days: minDaysAhead)), minDaysAhead == 0);
    }

    if (isNextWeek) {
      return (today.add(const Duration(days: 7)), false);
    }

    final dayMonthMatch = RegExp(r'يوم\s*(\d{1,2})(?:\s*[/\-]\s*(\d{1,2}))?').firstMatch(lower);
    if (dayMonthMatch != null) {
      final day = int.tryParse(dayMonthMatch.group(1)!) ?? now.day;
      final month = dayMonthMatch.group(2) != null
          ? (int.tryParse(dayMonthMatch.group(2)!) ?? now.month)
          : now.month;
      var year = now.year;
      var candidate = DateTime(year, month.clamp(1, 12), day.clamp(1, 31));
      if (candidate.isBefore(today)) {
        candidate = DateTime(year + 1, month.clamp(1, 12), day.clamp(1, 31));
      }
      return (candidate, candidate == today);
    }

    return (null, false);
  }

  static DateTime _nextMatchingWeekday(
    DateTime baseDt,
    List<int> weekdays,
    DateTime now,
  ) {
    for (var i = 0; i <= 7; i++) {
      final cand = baseDt.add(Duration(days: i));
      if (weekdays.contains(cand.weekday) && cand.isAfter(now)) {
        return cand;
      }
    }
    return baseDt.add(const Duration(days: 7));
  }

  static (int, int)? _extractTime(String s, DateTime now) =>
      _extractTimeWithPeriodFlag(s, now).$1;

  static ((int, int)?, bool) _extractTimeWithPeriodFlag(String s, DateTime now) {
    // 1. Match HH:MM (e.g. "6:45 AM", "10:30 مساءً", "17:00")
    final colonMatch = RegExp(
      r'(\d{1,2})\s*:\s*(\d{2})\s*(am|pm|ص|م|صباحا|صباحاً|الصبح|مساء|مساءً|بالليل|بليل|العصر|المغرب|الضهر|الظهر|العشا|العشاء)?',
    ).firstMatch(s);
    if (colonMatch != null) {
      var h = int.parse(colonMatch.group(1)!);
      final m = int.parse(colonMatch.group(2)!).clamp(0, 59);
      final period = colonMatch.group(3);
      final applied = _applyAmPm(h, s, explicitPeriod: period);
      return ((applied.$1.clamp(0, 23), m), applied.$2 || h >= 13);
    }

    // 2. Match "الساعة 7 و 5" / "الساعة 7 و 15 دقيقة"
    final andNumericMin = RegExp(
      r'(?:الساعة|الساعه|ساعة|ساعه|at)\s*(\d{1,2})\s*و\s*(\d{1,2})(?:\s*(?:دقيقة|دقيقه|دقايق|دقائق|min))?',
    ).firstMatch(s);
    if (andNumericMin != null) {
      var h = int.parse(andNumericMin.group(1)!);
      final m = int.parse(andNumericMin.group(2)!).clamp(0, 59);
      if (h <= 23) {
        final applied = _applyAmPm(h, s);
        return ((applied.$1.clamp(0, 23), m), applied.$2 || h >= 13);
      }
    }

    // 3. Match "الساعة 9 إلا ربع" / "9 إلا تلت" / "9 إلا 5" / "9 إلا 10"
    final minusMatch = RegExp(
      r'(?:(?:الساعة|الساعه|ساعة|ساعه)\s*)?(\d{1,2})\s*(?:إلا|الا)\s*(ربع|تلت|ثلث|5|10|خمسة|خمسه|عشرة|عشره)',
    ).firstMatch(s);
    if (minusMatch != null) {
      var h = int.parse(minusMatch.group(1)!);
      final frac = minusMatch.group(2)!;
      if (h <= 23) {
        var m = 45;
        if (frac == 'ربع') m = 45;
        if (frac == 'تلت' || frac == 'ثلث') m = 40;
        if (frac == '5' || frac.startsWith('خمس')) m = 55;
        if (frac == '10' || frac.startsWith('عشر')) m = 50;
        final applied = _applyAmPm(h, s);
        var resolvedHour = applied.$1 - 1;
        if (resolvedHour < 0) resolvedHour = 23;
        return ((resolvedHour.clamp(0, 23), m), applied.$2 || h >= 13);
      }
    }

    // 4. Match hour with Arabic/English cue or fraction/period:
    //    "الساعة 7 ونص الصبح", "الساعة 7 وتلت", "الساعة 7 وخمسة", "at 7 pm", "7 الصبح", "10 بالليل"
    final hourMatch = RegExp(
      r'(?:الساعة|الساعه|ساعة|ساعه|at)\s*(\d{1,2})(?:\s*(ونص|ونصف|وربع|وتلت|وثلث|وخمسة|وخمسه|وعشرة|وعشره))?(?:\s*(am|pm|ص|م|صباحا|صباحاً|الصبح|مساء|مساءً|بالليل|بليل|العصر|المغرب|الضهر|الظهر|العشا|العشاء|الفجر|بعد نص الليل))?'
      r'|(\d{1,2})\s*(ونص|ونصف|وربع|وتلت|وثلث|وخمسة|وخمسه|وعشرة|وعشره|am|pm|ص|م|صباحا|صباحاً|الصبح|مساء|مساءً|بالليل|بليل|العصر|المغرب|الضهر|الظهر|العشا|العشاء|الفجر)',
    ).firstMatch(s);
    if (hourMatch != null) {
      final hStr = hourMatch.group(1) ?? hourMatch.group(4);
      final mod = hourMatch.group(2) ?? hourMatch.group(5) ?? '';
      final period = hourMatch.group(3) ?? (hourMatch.group(5) ?? '');
      if (hStr != null) {
        var h = int.parse(hStr);
        if (h > 23) return (null, false);
        var m = 0;
        if (mod.contains('نص')) m = 30;
        if (mod == 'وربع') m = 15;
        if (mod == 'وتلت' || mod == 'وثلث') m = 20;
        if (mod.contains('خمس')) m = 5;
        if (mod.contains('عشر')) m = 10;
        final applied = _applyAmPm(h, s, explicitPeriod: period);
        return ((applied.$1.clamp(0, 23), m), applied.$2 || h >= 13);
      }
    }

    return (null, false);
  }

  /// Resolves AM/PM using Egyptian period words. Returns (resolvedHour, hadExplicitPeriod).
  static (int, bool) _applyAmPm(int hour, String s, {String? explicitPeriod}) {
    final p = (explicitPeriod ?? '').trim();

    final isAfterMidnight = _containsAny(s, ['بعد نص الليل', 'بعد نصف الليل', 'نص الليل', 'نصف الليل']);
    if (isAfterMidnight) {
      if (hour == 12) return (0, true);
      return (hour < 12 ? hour : hour, true);
    }

    final isNoon = _containsAny(s, ['الضهر', 'الظهر', 'ضهرا', 'ضهراً', 'ظهرا', 'ظهراً']);
    if (isNoon) {
      if (hour == 12) return (12, true);
      if (hour >= 1 && hour <= 5) return (hour + 12, true);
      return (hour, true);
    }

    final isPm = p == 'pm' ||
        p == 'م' ||
        _containsAny(s, [
          'مساء',
          'مساءً',
          'بالليل',
          'بليل',
          'الليل',
          'الليلة',
          'الليله',
          'العصر',
          'عصراً',
          'المغرب',
          'العشا',
          'العشاء',
          'pm',
          'tonight',
        ]);
    final isAm = p == 'am' ||
        p == 'ص' ||
        _containsAny(s, [
          'صباح',
          'الصبح',
          'صباحا',
          'صباحاً',
          'الفجر',
          'فجراً',
          'am',
        ]);

    if (isPm) {
      if (hour < 12) return (hour + 12, true);
      return (hour, true);
    }
    if (isAm) {
      if (hour == 12) return (0, true);
      return (hour, true);
    }
    return (hour, false);
  }

  static String _extractCreateTitle(String raw) {
    var cleaned = raw;

    // Remove relative duration phrases first
    cleaned = cleaned.replaceAll(
      RegExp(
        r'(?:بعد|كمان|خلال)\s+(?:(?:نص|نصف|ربع|تلت|ثلث)\s*(?:ساعة|ساعه)|(?:ساعة|ساعه|ساعتين)(?:\s*(?:إلا|الا)\s*ربع|\s*(?:ونص|ونصف|وربع|وتلت|وثلث))?|(?:\d+|واحد|واحدة|اتنين|تلاتة|أربعة|اربعة|خمسة|ستة|سبعة|تمانية|تسعة|عشرة|عشرين|تلاتين)\s*(?:ساعات|ساعة|ساعه|دقايق|دقائق|دقيقة|دقيقه)(?:\s*(?:ونص|ونصف|وربع))?|دقيقتين|دقيقة|دقيقه)',
      ),
      ' ',
    );

    // Remove clock time expressions (digits or Arabic number words)
    cleaned = cleaned.replaceAll(
      RegExp(
        r'(?:الساعة|الساعه|ساعة|ساعه)\s*(?:\d{1,2}|اتناشر|حداشر|عشرة|عشره|تسعة|تسعه|تمانية|تمانيه|ثمانية|سبعة|سبعه|ستة|سته|خمسة|خمسه|أربعة|اربعة|تلاتة|تلاته|ثلاثة|اتنين|واحدة|واحده)(?:\s*:\s*\d{2}|\s*و\s*\d{1,2}|\s*(?:إلا|الا)\s*(?:ربع|تلت|ثلث|خمسة|خمسه|عشرة|عشره|\d{1,2})|\s*(?:ونص|ونصف|وربع|وتلت|وثلث|وخمسة|وخمسه|وعشرة|وعشره))*',
      ),
      ' ',
    );

    // Remove trigger phrases, day words, repeat words, period words, and filler words
    cleaned = cleaned
        .replaceAll(
          RegExp(
            r'(?<![\u0600-\u06FF])(ظبطلي منبه|اضبطلي منبه|ضبطلي منبه|حطلي منبه|عايز منبه|عاوز منبه|اعملي منبه|اعمل منبه|اضبط منبه|حط منبه|فكرني|فكّرني|نبهني|نبّهني|صحيني|صحّيني|ذكرني|ذكّرني|اعمل|اضبط|ضبط|منبه|جماعي|لصديق|بعد بكرة|بعد بكره|بعد بكرا|بعد غد|بكرة|بكره|بكرا|غداً|غدا|النهاردة|النهارده|اليوم|الليلة|الليله|الأسبوع الجاي|الاسبوع الجاي|الأسبوع القادم|الاسبوع القادم|كل يوم|يومياً|يوميا|يومي|كل أسبوع|كل اسبوع|أسبوعياً|اسبوعيا|كل شهر|شهرياً|كل ساعة|كل ساعه|بعد نص الليل|بعد نصف الليل|نص الليل|نصف الليل|الصبح|صباحاً|صباحا|مساءً|مساءا|مساء|بالليل|بليل|الضهر|الظهر|العصر|المغرب|العشاء|العشا|الفجر|ونص|ونصف|وربع|وتلت|وثلث|إلا ربع|الا ربع|إلا تلت|الا تلت|وخمسة|وخمسه|وعشرة|وعشره)(?![\u0600-\u06FF])',
          ),
          ' ',
        )
        // Remove standalone weekday mentions ("يوم الخميس", "كل اتنين وخميس")
        .replaceAll(
          RegExp(
            r'(?:كل\s+|يوم\s+|و\s*)?(?:الاثنين|الإثنين|الاتنين|اتنين|الثلاثاء|التلات|الأربعاء|الاربعاء|الأربع|الاربع|الخميس|خميس|الجمعة|الجمعه|جمعة|السبت|سبت|الأحد|الاحد|الحد)',
          ),
          ' ',
        )
        .replaceAll(
          RegExp(
            r'\b(wake me up|wake me|set|create|alarm|remind me to|remind me|tomorrow|today|tonight|daily|weekly|every day|group|buddy|at|am|pm|for|in)\b',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\b\d{1,2}(:\d{2})?\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Strip leading filler prepositions / connectors ("اني", "إن", "على", "عشان", "لـ", "كل", "و")
    cleaned = cleaned
        .replaceAll(RegExp(r'^(?:إني|اني|أني|إن|ان|أن|عشان|على|لـ|كل|و)\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    return cleaned;
  }

  static String _extractTargetQuery(String raw) {
    return raw
        .replaceAll(
          RegExp(
            r'(اقفل|أقفل|عطل|امسح|احذف|الغي|ألغي|منبه|المنبه|disable|delete|remove|cancel|alarm)',
            caseSensitive: false,
          ),
          ' ',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
