import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/services/recurrence_calculator.dart';
import '../local/app_database.dart';
import '../platform/native_alarm_channel.dart';
import '../remote/firestore_service.dart';

class AlarmRepository {
  final AppDatabase _db;
  final NativeAlarmChannel _native;
  final FirestoreService? _remote;

  AlarmRepository(this._db, this._native, [this._remote]);

  Stream<List<Alarm>> watchAlarms() {
    return _db.watchActiveAlarms().asyncMap((rows) async {
      final result = <Alarm>[];
      for (final r in rows) {
        final participantsRows = await _db.getParticipantsForAlarm(r.id);
        result.add(_mapRowToAlarm(r, participantsRows));
      }
      return result;
    });
  }

  Future<void> saveAlarm(Alarm alarm, {bool isOnline = false}) async {
    final nowUtc = DateTime.now().toUtc();
    final updated = alarm.copyWith(
      type: AlarmType.personal,
      updatedAtUtc: nowUtc,
    );

    await _db.upsertAlarm(
      AlarmsTableCompanion(
        id: Value(updated.id),
        ownerId: Value(updated.ownerId),
        title: Value(updated.title),
        notes: Value(updated.notes),
        startAtUtc: Value(updated.startAtUtc.toUtc()),
        creatorTimezoneId: Value(updated.creatorTimezoneId),
        repeatRuleJson: Value(updated.repeatRule.toJsonString()),
        snoozeConfigJson: Value(updated.snoozeConfig.toJsonString()),
        ringtoneUri: Value(updated.ringtoneUri),
        volume: Value(updated.volume),
        gradualVolume: Value(updated.gradualVolume),
        vibrate: Value(updated.vibrate),
        ringOnVibrateSilent: Value(updated.ringOnVibrateSilent),
        alarmType: Value(updated.type.name),
        state: Value(updated.state.name),
        isEnabled: Value(updated.isEnabled),
        occurrenceCount: Value(updated.occurrenceCount),
        currentSnoozeCount: Value(updated.currentSnoozeCount),
        snoozedUntilUtc: Value(updated.snoozedUntilUtc),
        updatedAtUtc: Value(updated.updatedAtUtc),
        isDeleted: const Value(false),
      ),
    );

    await _scheduleOrCancelNative(updated);
  }

  Future<void> deleteAlarm(String alarmId, {bool isOnline = false}) async {
    final nowUtc = DateTime.now().toUtc();
    await _db.softDeleteAlarm(alarmId, nowUtc);
    await _native.cancelAlarm(alarmId.hashCode, alarmId);
  }

  Future<String> exportAlarmsBackupJson({
    String defaultRingtoneUri = 'default',
    String defaultRingtoneName = '',
  }) async {
    final rows = await _db.getActiveAlarms();
    final alarms = <Map<String, dynamic>>[];
    for (final r in rows) {
      final alarm = _mapRowToAlarm(r, const []);
      alarms.add(alarm.toBackupMap());
    }
    final payload = <String, dynamic>{
      'app': 'U3m Alarm',
      'version': 1,
      'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'defaultRingtoneUri': defaultRingtoneUri,
      'defaultRingtoneName': defaultRingtoneName,
      'alarms': alarms,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<int> importAlarmsBackupJson(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    List<dynamic> alarmsList;
    if (decoded is Map<String, dynamic> && decoded['alarms'] is List) {
      alarmsList = decoded['alarms'] as List<dynamic>;
    } else if (decoded is List) {
      alarmsList = decoded;
    } else {
      throw const FormatException('Invalid backup file format');
    }

    int count = 0;
    for (final item in alarmsList) {
      if (item is Map<String, dynamic>) {
        final alarm = Alarm.fromBackupMap(item);
        await saveAlarm(alarm);
        count++;
      }
    }
    return count;
  }

  Future<void> markOccurrenceDone(Alarm alarm) async {
    final nowUtc = DateTime.now().toUtc();
    await _db.insertOccurrence(
      AlarmOccurrencesTableCompanion.insert(
        alarmId: alarm.id,
        occurrenceIndex: alarm.occurrenceCount + 1,
        scheduledAtUtc: alarm.snoozedUntilUtc ?? alarm.startAtUtc,
        state: AlarmState.done.name,
        snoozeCount: Value(alarm.currentSnoozeCount),
        acknowledgedAtUtc: Value(nowUtc),
      ),
    );

    final nextState = alarm.repeatRule.isRecurring
        ? AlarmState.upcoming
        : AlarmState.done;
    final nextAlarm = alarm.copyWith(
      state: nextState,
      isEnabled: alarm.repeatRule.isRecurring,
      occurrenceCount: alarm.occurrenceCount + 1,
      currentSnoozeCount: 0,
      clearSnooze: true,
      updatedAtUtc: nowUtc,
    );
    await saveAlarm(nextAlarm);
    await _native.stopRinging();
  }

  Future<void> snoozeAlarm(Alarm alarm) async {
    final nowUtc = DateTime.now().toUtc();
    final nextSnoozeCount = alarm.currentSnoozeCount + 1;
    if (nextSnoozeCount > alarm.snoozeConfig.maxSnoozeCount) {
      await markOccurrenceMissed(alarm);
      return;
    }

    final snoozeTarget = nowUtc.add(
      Duration(minutes: alarm.snoozeConfig.snoozeDurationMinutes),
    );
    final updated = alarm.copyWith(
      state: AlarmState.upcoming,
      currentSnoozeCount: nextSnoozeCount,
      snoozedUntilUtc: snoozeTarget,
      updatedAtUtc: nowUtc,
    );
    await saveAlarm(updated);
    await _native.stopRinging();
  }

  Future<void> markOccurrenceMissed(Alarm alarm) async {
    final nowUtc = DateTime.now().toUtc();
    await _db.insertOccurrence(
      AlarmOccurrencesTableCompanion.insert(
        alarmId: alarm.id,
        occurrenceIndex: alarm.occurrenceCount + 1,
        scheduledAtUtc: alarm.snoozedUntilUtc ?? alarm.startAtUtc,
        state: AlarmState.missed.name,
        snoozeCount: Value(alarm.currentSnoozeCount),
      ),
    );

    // Crucial: a missed occurrence of a recurring alarm must NOT block future repetitions
    final nextFire = RecurrenceCalculator.computeNextFireUtc(
      alarm.copyWith(clearSnooze: true),
      referenceUtc: nowUtc,
    );
    final nextAlarm = alarm.copyWith(
      state: alarm.repeatRule.isRecurring && nextFire != null
          ? AlarmState.upcoming
          : AlarmState.missed,
      isEnabled: alarm.repeatRule.isRecurring && nextFire != null,
      occurrenceCount: alarm.occurrenceCount + 1,
      currentSnoozeCount: 0,
      clearSnooze: true,
      updatedAtUtc: nowUtc,
    );
    await saveAlarm(nextAlarm);
    await _native.stopRinging();
  }

  Future<void> rescheduleAllAlarms() async {
    final rows = await _db.getActiveAlarms();
    for (final r in rows) {
      final participantsRows = await _db.getParticipantsForAlarm(r.id);
      final alarm = _mapRowToAlarm(r, participantsRows);
      await _scheduleOrCancelNative(alarm);
    }
  }

  Future<void> flushSyncQueue() async {
    if (_remote == null) return;
    final items = await _db.getPendingSyncItems();
    final alarms = await _db.getActiveAlarms();
    final alarmMap = {for (final a in alarms) a.id: a};

    for (final item in items) {
      try {
        if (item.entityType == 'delete_alarm') {
          await _remote!.deleteAlarm(item.entityId);
        } else if (item.entityType == 'alarm') {
          final row = alarmMap[item.entityId];
          if (row != null) {
            final participantsRows = await _db.getParticipantsForAlarm(row.id);
            await _remote!.syncAlarm(_mapRowToAlarm(row, participantsRows));
          }
        }
        await _db.removeSyncItem(item.id);
      } catch (_) {
        // Keep in queue for next connectivity window
      }
    }
  }

  Future<void> _scheduleOrCancelNative(Alarm alarm) async {
    final nextFireUtc = RecurrenceCalculator.computeNextFireUtc(alarm);
    if (nextFireUtc == null || !alarm.isEnabled) {
      await _native.cancelAlarm(alarm.id.hashCode, alarm.id);
      return;
    }

    await _native.scheduleExactAlarm(
      alarmRequestCode: alarm.id.hashCode,
      alarmId: alarm.id,
      title: alarm.title,
      notes: alarm.notes,
      triggerAtMillisUtc: nextFireUtc.millisecondsSinceEpoch,
      ringtoneUri: alarm.ringtoneUri,
      volume: alarm.volume,
      gradualVolume: alarm.gradualVolume,
      vibrate: alarm.vibrate,
      ringOnVibrateSilent: alarm.ringOnVibrateSilent,
      ringDurationSeconds: alarm.snoozeConfig.ringDurationSeconds,
      snoozeDurationMinutes: alarm.snoozeConfig.snoozeDurationMinutes,
      maxSnoozeCount: alarm.snoozeConfig.maxSnoozeCount,
      currentSnoozeCount: alarm.currentSnoozeCount,
    );
  }

  Alarm _mapRowToAlarm(
    AlarmsTableData r,
    List<AlarmParticipantsTableData> pRows,
  ) {
    return Alarm(
      id: r.id,
      ownerId: r.ownerId,
      title: r.title,
      notes: r.notes,
      startAtUtc: r.startAtUtc.toUtc(),
      creatorTimezoneId: r.creatorTimezoneId,
      repeatRule: RepeatRule.fromJsonString(r.repeatRuleJson),
      snoozeConfig: SnoozeConfig.fromJsonString(r.snoozeConfigJson),
      ringtoneUri: r.ringtoneUri,
      volume: r.volume,
      gradualVolume: r.gradualVolume,
      vibrate: r.vibrate,
      ringOnVibrateSilent: r.ringOnVibrateSilent,
      type: AlarmType.values.firstWhere(
        (e) => e.name == r.alarmType,
        orElse: () => AlarmType.personal,
      ),
      state: AlarmState.values.firstWhere(
        (e) => e.name == r.state,
        orElse: () => AlarmState.upcoming,
      ),
      isEnabled: r.isEnabled,
      occurrenceCount: r.occurrenceCount,
      currentSnoozeCount: r.currentSnoozeCount,
      snoozedUntilUtc: r.snoozedUntilUtc?.toUtc(),
      updatedAtUtc: r.updatedAtUtc.toUtc(),
      participants: pRows
          .map((p) => AlarmParticipant(
                uid: p.uid,
                displayName: p.displayName,
                photoUrl: p.photoUrl,
                timezoneId: p.timezoneId,
                status: ParticipantStatus.values.firstWhere(
                  (e) => e.name == p.status,
                  orElse: () => ParticipantStatus.pending,
                ),
                updatedAtUtc: p.updatedAtUtc?.toUtc(),
              ))
          .toList(),
    );
  }
}
