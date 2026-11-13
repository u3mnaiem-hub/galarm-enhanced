import 'package:flutter_test/flutter_test.dart';
import 'package:galarm_enhanced/domain/entities/alarm.dart';
import 'package:galarm_enhanced/domain/services/recurrence_calculator.dart';
import 'package:timezone/data/latest.dart' as tz_data;

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
  });

  test('Daily recurring alarm advances to next day even after missed occurrence', () {
    final start = DateTime.utc(2026, 11, 10, 7, 0);
    final alarm = Alarm(
      id: 'a1',
      ownerId: 'u1',
      title: 'Morning',
      startAtUtc: start,
      creatorTimezoneId: 'Africa/Cairo',
      repeatRule: const RepeatRule(frequency: RepeatFrequency.daily),
      updatedAtUtc: start,
    );

    final next = RecurrenceCalculator.computeNextFireUtc(
      alarm,
      referenceUtc: DateTime.utc(2026, 11, 12, 8, 0),
    );
    expect(next, DateTime.utc(2026, 11, 13, 7, 0));
  });

  test('Weekly recurring alarm picks next selected weekday', () {
    // 2026-11-13 is Friday (weekday = 5)
    final start = DateTime.utc(2026, 11, 13, 9, 0);
    final alarm = Alarm(
      id: 'a2',
      ownerId: 'u1',
      title: 'Standup',
      startAtUtc: start,
      creatorTimezoneId: 'UTC',
      repeatRule: const RepeatRule(
        frequency: RepeatFrequency.weekly,
        weekdays: [1, 3, 5], // Mon, Wed, Fri
      ),
      updatedAtUtc: start,
    );

    final next = RecurrenceCalculator.computeNextFireUtc(
      alarm,
      referenceUtc: DateTime.utc(2026, 11, 13, 9, 5),
    );
    // Next matching weekday after Friday is Monday 2026-11-16
    expect(next, DateTime.utc(2026, 11, 16, 9, 0));
  });

  test('Custom interval every 3 hours computes exact next slot', () {
    final start = DateTime.utc(2026, 11, 13, 10, 0);
    final alarm = Alarm(
      id: 'a3',
      ownerId: 'u1',
      title: 'Hydrate',
      startAtUtc: start,
      creatorTimezoneId: 'UTC',
      repeatRule: const RepeatRule(
        frequency: RepeatFrequency.custom,
        interval: 3,
        customUnit: CustomRepeatUnit.hours,
      ),
      updatedAtUtc: start,
    );

    final next = RecurrenceCalculator.computeNextFireUtc(
      alarm,
      referenceUtc: DateTime.utc(2026, 11, 13, 14, 0),
    );
    expect(next, DateTime.utc(2026, 11, 13, 16, 0));
  });

  test('Timezone conversion converts UTC to Cairo local time (+2)', () {
    final utc = DateTime.utc(2026, 11, 13, 10, 0);
    final cairo = RecurrenceCalculator.convertUtcToTimezone(utc, 'Africa/Cairo');
    expect(cairo.hour, 12);
  });
}
