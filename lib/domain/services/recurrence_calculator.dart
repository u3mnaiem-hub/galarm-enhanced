import 'package:timezone/timezone.dart' as tz;
import '../entities/alarm.dart';

class RecurrenceCalculator {
  /// Computes the next scheduled UTC fire time after [fromUtc] (or returns [alarm.startAtUtc]
  /// if it is still in the future and not yet fired).
  ///
  /// Returns `null` if the alarm has no future occurrence (one-time alarm in the past,
  /// disabled, archived, or endDateUtc / maxOccurrences reached).
  static DateTime? computeNextFireUtc(
    Alarm alarm, {
    DateTime? referenceUtc,
  }) {
    if (!alarm.isEnabled || alarm.state == AlarmState.archived) {
      return null;
    }

    final now = (referenceUtc ?? DateTime.now()).toUtc();

    // If currently snoozed and snooze target is in the future, honor snooze time
    if (alarm.snoozedUntilUtc != null && alarm.snoozedUntilUtc!.isAfter(now)) {
      return alarm.snoozedUntilUtc;
    }

    // If initial start time is still in the future, return it directly
    if (alarm.startAtUtc.isAfter(now)) {
      return alarm.startAtUtc;
    }

    final rule = alarm.repeatRule;
    if (!rule.isRecurring) {
      return null;
    }

    var candidate = alarm.startAtUtc;
    var index = 0;

    // Guard against infinite loops on malformed intervals
    final safeInterval = rule.interval < 1 ? 1 : rule.interval;
    const maxIterations = 10000;

    while (!candidate.isAfter(now) && index < maxIterations) {
      index++;
      if (rule.maxOccurrences != null && index >= rule.maxOccurrences!) {
        return null;
      }
      candidate = _stepOnce(candidate, rule, safeInterval, alarm.creatorTimezoneId);
      if (rule.endDateUtc != null && candidate.isAfter(rule.endDateUtc!)) {
        return null;
      }
    }

    if (rule.maxOccurrences != null && index >= rule.maxOccurrences!) {
      return null;
    }
    if (rule.endDateUtc != null && candidate.isAfter(rule.endDateUtc!)) {
      return null;
    }

    return candidate;
  }

  static DateTime _stepOnce(
    DateTime currentUtc,
    RepeatRule rule,
    int interval,
    String timezoneId,
  ) {
    switch (rule.frequency) {
      case RepeatFrequency.none:
        return currentUtc;
      case RepeatFrequency.hourly:
        return currentUtc.add(Duration(hours: interval));
      case RepeatFrequency.daily:
        return _addCalendarDays(currentUtc, interval, timezoneId);
      case RepeatFrequency.weekly:
        if (rule.weekdays.isEmpty) {
          return _addCalendarDays(currentUtc, 7 * interval, timezoneId);
        }
        return _nextMatchingWeekday(currentUtc, rule.weekdays, interval, timezoneId);
      case RepeatFrequency.monthly:
        return _addCalendarMonths(
          currentUtc,
          interval,
          rule.dayOfMonth,
          timezoneId,
        );
      case RepeatFrequency.yearly:
        return _addCalendarMonths(currentUtc, 12 * interval, null, timezoneId);
      case RepeatFrequency.custom:
        if (rule.lastDayOfMonth || rule.customPreset == 'last_day_of_month') {
          return _addCalendarMonthsLastDay(currentUtc, interval, timezoneId);
        }
        if ((rule.nthWeekday != null && rule.weekdays.isNotEmpty) ||
            rule.customPreset == '2nd_saturday_of_month') {
          final nth = rule.nthWeekday ?? 2;
          final weekday =
              rule.weekdays.isNotEmpty ? rule.weekdays.first : DateTime.saturday;
          return _addCalendarMonthsNthWeekday(
            currentUtc,
            interval,
            nth,
            weekday,
            timezoneId,
          );
        }
        switch (rule.customUnit) {
          case CustomRepeatUnit.hours:
            return currentUtc.add(Duration(hours: interval));
          case CustomRepeatUnit.days:
            return _addCalendarDays(currentUtc, interval, timezoneId);
          case CustomRepeatUnit.weeks:
            return _addCalendarDays(currentUtc, 7 * interval, timezoneId);
          case CustomRepeatUnit.months:
            return _addCalendarMonths(currentUtc, interval, null, timezoneId);
        }
    }
  }

  static tz.Location _resolveLocation(String timezoneId) {
    try {
      return tz.getLocation(timezoneId);
    } catch (_) {
      return tz.UTC;
    }
  }

  static DateTime _addCalendarDays(
    DateTime currentUtc,
    int days,
    String timezoneId,
  ) {
    final loc = _resolveLocation(timezoneId);
    final local = tz.TZDateTime.from(currentUtc, loc);
    final nextLocal = tz.TZDateTime(
      loc,
      local.year,
      local.month,
      local.day + days,
      local.hour,
      local.minute,
      local.second,
    );
    return nextLocal.toUtc();
  }

  static DateTime _nextMatchingWeekday(
    DateTime currentUtc,
    List<int> weekdays,
    int weekInterval,
    String timezoneId,
  ) {
    final sorted = [...weekdays]..sort();
    final loc = _resolveLocation(timezoneId);
    final local = tz.TZDateTime.from(currentUtc, loc);

    // Check remaining days in current week
    for (final day in sorted) {
      if (day > local.weekday) {
        final diff = day - local.weekday;
        return tz.TZDateTime(
          loc,
          local.year,
          local.month,
          local.day + diff,
          local.hour,
          local.minute,
          local.second,
        ).toUtc();
      }
    }

    // Jump to first selected weekday in the next interval week
    final daysUntilMonday = 8 - local.weekday;
    final extraWeeksDays = (weekInterval - 1) * 7;
    final offsetFromMonday = sorted.first - 1;
    final totalDays = daysUntilMonday + extraWeeksDays + offsetFromMonday;
    return tz.TZDateTime(
      loc,
      local.year,
      local.month,
      local.day + totalDays,
      local.hour,
      local.minute,
      local.second,
    ).toUtc();
  }

  static DateTime _addCalendarMonths(
    DateTime currentUtc,
    int months,
    int? preferredDayOfMonth,
    String timezoneId,
  ) {
    final loc = _resolveLocation(timezoneId);
    final local = tz.TZDateTime.from(currentUtc, loc);
    final totalMonths = local.year * 12 + (local.month - 1) + months;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final maxDays = _daysInMonth(targetYear, targetMonth);
    final targetDay = (preferredDayOfMonth ?? local.day).clamp(1, maxDays);

    return tz.TZDateTime(
      loc,
      targetYear,
      targetMonth,
      targetDay,
      local.hour,
      local.minute,
      local.second,
    ).toUtc();
  }

  static int _daysInMonth(int year, int month) {
    final nextMonth = month == 12 ? DateTime.utc(year + 1, 1, 1) : DateTime.utc(year, month + 1, 1);
    return nextMonth.subtract(const Duration(days: 1)).day;
  }

  static DateTime _addCalendarMonthsLastDay(
    DateTime currentUtc,
    int months,
    String timezoneId,
  ) {
    final loc = _resolveLocation(timezoneId);
    final local = tz.TZDateTime.from(currentUtc, loc);
    final totalMonths = local.year * 12 + (local.month - 1) + months;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final lastDay = _daysInMonth(targetYear, targetMonth);
    return tz.TZDateTime(
      loc,
      targetYear,
      targetMonth,
      lastDay,
      local.hour,
      local.minute,
      local.second,
    ).toUtc();
  }

  static DateTime _addCalendarMonthsNthWeekday(
    DateTime currentUtc,
    int months,
    int nth,
    int targetWeekday,
    String timezoneId,
  ) {
    final loc = _resolveLocation(timezoneId);
    final local = tz.TZDateTime.from(currentUtc, loc);
    final totalMonths = local.year * 12 + (local.month - 1) + months;
    final targetYear = totalMonths ~/ 12;
    final targetMonth = (totalMonths % 12) + 1;
    final firstOfMonth = DateTime.utc(targetYear, targetMonth, 1);
    final offset = (targetWeekday - firstOfMonth.weekday + 7) % 7;
    final maxDays = _daysInMonth(targetYear, targetMonth);
    final day = (1 + offset + (nth - 1) * 7).clamp(1, maxDays);
    return tz.TZDateTime(
      loc,
      targetYear,
      targetMonth,
      day,
      local.hour,
      local.minute,
      local.second,
    ).toUtc();
  }

  /// Converts a UTC timestamp into the local wall-clock time of [targetTimezoneId].
  static DateTime convertUtcToTimezone(DateTime utcTime, String targetTimezoneId) {
    final loc = _resolveLocation(targetTimezoneId);
    return tz.TZDateTime.from(utcTime.toUtc(), loc);
  }
}
