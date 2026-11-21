import 'dart:convert';
import 'package:drift/drift.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/entities/buddy_group.dart';
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

    await _db.deleteParticipantsForAlarm(updated.id);
    for (final p in updated.participants) {
      await _db.upsertParticipant(
        AlarmParticipantsTableCompanion(
          alarmId: Value(updated.id),
          uid: Value(p.uid),
          displayName: Value(p.displayName),
          photoUrl: Value(p.photoUrl),
          timezoneId: Value(p.timezoneId),
          status: Value(p.status.name),
          updatedAtUtc: Value(p.updatedAtUtc ?? nowUtc),
        ),
      );
    }

    if (_remote != null && updated.type != AlarmType.personal) {
      try {
        final allBuddies = await _db.getAllBuddies();
        final buddyPhoneById = {for (final b in allBuddies) b.id: b.phone};
        final recipientPhones = updated.participants
            .map((p) => buddyPhoneById[p.uid] ?? '')
            .where((ph) => ph.isNotEmpty)
            .toList();
        await _remote!.syncAlarm(updated, recipientPhones: recipientPhones);
      } catch (_) {
        await _db.enqueueSync('alarm', updated.id, '{}');
      }
    }

    await _scheduleOrCancelNative(updated);
  }

  /// Saves an incoming buddy/group alarm received via FCM or Firestore into local SQLite
  /// and schedules it natively so it rings on this device without re-pushing to Firestore.
  Future<void> saveIncomingSharedAlarm(Alarm incoming) async {
    await _db.upsertAlarm(
      AlarmsTableCompanion(
        id: Value(incoming.id),
        ownerId: Value(incoming.ownerId),
        title: Value(incoming.title),
        notes: Value(incoming.notes),
        startAtUtc: Value(incoming.startAtUtc.toUtc()),
        creatorTimezoneId: Value(incoming.creatorTimezoneId),
        repeatRuleJson: Value(incoming.repeatRule.toJsonString()),
        snoozeConfigJson: Value(incoming.snoozeConfig.toJsonString()),
        ringtoneUri: Value(incoming.ringtoneUri),
        volume: Value(incoming.volume),
        gradualVolume: Value(incoming.gradualVolume),
        vibrate: Value(incoming.vibrate),
        ringOnVibrateSilent: Value(incoming.ringOnVibrateSilent),
        alarmType: Value(incoming.type.name),
        state: Value(incoming.state.name),
        isEnabled: Value(incoming.isEnabled),
        occurrenceCount: Value(incoming.occurrenceCount),
        currentSnoozeCount: Value(incoming.currentSnoozeCount),
        snoozedUntilUtc: Value(incoming.snoozedUntilUtc),
        updatedAtUtc: Value(incoming.updatedAtUtc.toUtc()),
        isDeleted: const Value(false),
      ),
    );
    await _scheduleOrCancelNative(incoming);
  }

  Future<void> deleteAlarm(String alarmId, {bool isOnline = false}) async {
    final nowUtc = DateTime.now().toUtc();
    await _db.softDeleteAlarm(alarmId, nowUtc);
    await _db.deleteParticipantsForAlarm(alarmId);
    await _native.cancelAlarm(alarmId.hashCode, alarmId);
    if (_remote != null) {
      try {
        await _remote!.deleteAlarm(alarmId);
      } catch (_) {
        await _db.enqueueSync('delete_alarm', alarmId, '{}');
      }
    }
  }

  // --- Saved Buddies & Groups CRUD ---
  Stream<List<SavedBuddy>> watchBuddies() {
    return _db.watchBuddies().map(
          (rows) => rows
              .map(
                (r) => SavedBuddy(
                  id: r.id,
                  name: r.name,
                  phone: r.phone,
                  createdAtUtc: r.createdAtUtc.toUtc(),
                ),
              )
              .toList(),
        );
  }

  Future<void> saveBuddy(SavedBuddy buddy) async {
    await _db.upsertBuddy(
      BuddiesTableCompanion(
        id: Value(buddy.id),
        name: Value(buddy.name),
        phone: Value(buddy.phone),
        createdAtUtc: Value(buddy.createdAtUtc.toUtc()),
      ),
    );
  }

  Future<void> deleteBuddy(String id) async {
    await _db.deleteBuddy(id);
    // Also remove this buddy from any saved groups
    final groups = await _db.getAllGroups();
    for (final g in groups) {
      final members = SavedGroup.decodeMemberIds(g.memberIdsJson);
      if (members.contains(id)) {
        final updated = members.where((m) => m != id).toList();
        await _db.upsertGroup(
          GroupsTableCompanion(
            id: Value(g.id),
            name: Value(g.name),
            memberIdsJson: Value(jsonEncode(updated)),
            createdAtUtc: Value(g.createdAtUtc.toUtc()),
          ),
        );
      }
    }
  }

  Stream<List<SavedGroup>> watchGroups() {
    return _db.watchGroups().map(
          (rows) => rows
              .map(
                (r) => SavedGroup(
                  id: r.id,
                  name: r.name,
                  memberIds: SavedGroup.decodeMemberIds(r.memberIdsJson),
                  createdAtUtc: r.createdAtUtc.toUtc(),
                ),
              )
              .toList(),
        );
  }

  Future<void> saveGroup(SavedGroup group) async {
    await _db.upsertGroup(
      GroupsTableCompanion(
        id: Value(group.id),
        name: Value(group.name),
        memberIdsJson: Value(group.memberIdsJson),
        createdAtUtc: Value(group.createdAtUtc.toUtc()),
      ),
    );
  }

  Future<void> deleteGroup(String id) async {
    await _db.deleteGroup(id);
  }

  Future<String> exportAlarmsBackupJson({
    String defaultRingtoneUri = 'default',
    String defaultRingtoneName = '',
  }) async {
    final rows = await _db.getActiveAlarms();
    final alarms = <Map<String, dynamic>>[];
    for (final r in rows) {
      final participantsRows = await _db.getParticipantsForAlarm(r.id);
      final alarm = _mapRowToAlarm(r, participantsRows);
      alarms.add(alarm.toBackupMap());
    }
    final buddyRows = await _db.getAllBuddies();
    final buddies = buddyRows
        .map(
          (b) => SavedBuddy(
            id: b.id,
            name: b.name,
            phone: b.phone,
            createdAtUtc: b.createdAtUtc.toUtc(),
          ).toJson(),
        )
        .toList();
    final groupRows = await _db.getAllGroups();
    final groups = groupRows
        .map(
          (g) => SavedGroup(
            id: g.id,
            name: g.name,
            memberIds: SavedGroup.decodeMemberIds(g.memberIdsJson),
            createdAtUtc: g.createdAtUtc.toUtc(),
          ).toJson(),
        )
        .toList();

    final payload = <String, dynamic>{
      'app': 'U3m Alarm',
      'version': 2,
      'exportedAtUtc': DateTime.now().toUtc().toIso8601String(),
      'defaultRingtoneUri': defaultRingtoneUri,
      'defaultRingtoneName': defaultRingtoneName,
      'alarms': alarms,
      'buddies': buddies,
      'groups': groups,
    };
    return const JsonEncoder.withIndent('  ').convert(payload);
  }

  Future<int> importAlarmsBackupJson(String rawJson) async {
    final decoded = jsonDecode(rawJson);
    List<dynamic> alarmsList;
    List<dynamic> buddiesList = const [];
    List<dynamic> groupsList = const [];

    if (decoded is Map<String, dynamic> && decoded['alarms'] is List) {
      alarmsList = decoded['alarms'] as List<dynamic>;
      if (decoded['buddies'] is List) {
        buddiesList = decoded['buddies'] as List<dynamic>;
      }
      if (decoded['groups'] is List) {
        groupsList = decoded['groups'] as List<dynamic>;
      }
    } else if (decoded is List) {
      alarmsList = decoded;
    } else {
      throw const FormatException('Invalid backup file format');
    }

    for (final item in buddiesList) {
      if (item is Map<String, dynamic>) {
        await saveBuddy(SavedBuddy.fromJson(item));
      }
    }
    for (final item in groupsList) {
      if (item is Map<String, dynamic>) {
        await saveGroup(SavedGroup.fromJson(item));
      }
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

    final nextFire = RecurrenceCalculator.computeNextFireUtc(
      alarm.copyWith(clearSnooze: true),
      referenceUtc: nowUtc,
    );
    final keepRecurring = alarm.repeatRule.isRecurring && nextFire != null;
    final nextState = keepRecurring
        ? AlarmState.upcoming
        : AlarmState.done;
    final nextAlarm = alarm.copyWith(
      state: nextState,
      isEnabled: keepRecurring,
      occurrenceCount: alarm.occurrenceCount + 1,
      currentSnoozeCount: 0,
      clearSnooze: true,
      updatedAtUtc: nowUtc,
    );
    await saveAlarm(nextAlarm);
    if (alarm.type == AlarmType.buddy || alarm.type == AlarmType.group) {
      await _db.upsertNotification(
        NotificationsTableCompanion(
          id: Value('done_${alarm.id}_${nowUtc.millisecondsSinceEpoch}'),
          title: Value(
            alarm.type == AlarmType.buddy
                ? 'Buddy Alarm Done • ${alarm.title}'
                : 'Group Alarm Done • ${alarm.title}',
          ),
          body: Value(
            alarm.participants.isNotEmpty
                ? 'Updated for: ${alarm.participants.map((p) => p.displayName).join(", ")}'
                : 'Marked as completed.',
          ),
          kind: Value(
            alarm.type == AlarmType.buddy ? 'buddy_done' : 'group_change',
          ),
          alarmId: Value(alarm.id),
          createdAtUtc: Value(nowUtc),
          isRead: const Value(false),
        ),
      );
    }
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
    if (alarm.type == AlarmType.buddy || alarm.type == AlarmType.group) {
      await _db.upsertNotification(
        NotificationsTableCompanion(
          id: Value('missed_${alarm.id}_${nowUtc.millisecondsSinceEpoch}'),
          title: Value(
            alarm.type == AlarmType.buddy
                ? 'Buddy Alarm Missed • ${alarm.title}'
                : 'Group Alarm Missed • ${alarm.title}',
          ),
          body: Value(
            alarm.participants.isNotEmpty
                ? 'Participants notified: ${alarm.participants.map((p) => p.displayName).join(", ")}'
                : 'Alarm was missed.',
          ),
          kind: Value(
            alarm.type == AlarmType.buddy ? 'buddy_missed' : 'group_change',
          ),
          alarmId: Value(alarm.id),
          createdAtUtc: Value(nowUtc),
          isRead: const Value(false),
        ),
      );
    }
    await _native.stopRinging();
  }

  Future<void> syncNativeEvents() async {
    final events = await _native.consumeHistoryEvents();
    if (events.isEmpty) return;

    final rows = await _db.getActiveAlarms();
    final alarmMap = <String, Alarm>{};
    for (final r in rows) {
      final participantsRows = await _db.getParticipantsForAlarm(r.id);
      alarmMap[r.id] = _mapRowToAlarm(r, participantsRows);
    }

    final nowUtc = DateTime.now().toUtc();
    for (final ev in events) {
      final alarmId = ev['alarmId'] as String?;
      if (alarmId == null || alarmId.isEmpty) continue;

      final scheduledMillis = (ev['scheduledAtMillis'] as num?)?.toInt() ??
          nowUtc.millisecondsSinceEpoch;
      final ackMillis = (ev['acknowledgedAtMillis'] as num?)?.toInt();
      final stateStr = (ev['state'] as String?) ?? 'done';
      final snoozeCount = (ev['snoozeCount'] as num?)?.toInt() ?? 0;
      final occIndex = (ev['occurrenceIndex'] as num?)?.toInt() ?? 1;

      await _db.insertOccurrence(
        AlarmOccurrencesTableCompanion.insert(
          alarmId: alarmId,
          occurrenceIndex: occIndex,
          scheduledAtUtc: DateTime.fromMillisecondsSinceEpoch(
            scheduledMillis,
            isUtc: true,
          ),
          state: stateStr,
          snoozeCount: Value(snoozeCount),
          acknowledgedAtUtc: Value(
            ackMillis != null
                ? DateTime.fromMillisecondsSinceEpoch(ackMillis, isUtc: true)
                : null,
          ),
        ),
      );

      final existing = alarmMap[alarmId];
      if (existing != null) {
        final nextFire = RecurrenceCalculator.computeNextFireUtc(
          existing.copyWith(clearSnooze: true),
          referenceUtc: nowUtc,
        );
        final keepRecurring = existing.repeatRule.isRecurring && nextFire != null;
        final updatedAlarm = existing.copyWith(
          state: keepRecurring
              ? AlarmState.upcoming
              : (stateStr == 'missed' ? AlarmState.missed : AlarmState.done),
          isEnabled: keepRecurring,
          occurrenceCount: existing.occurrenceCount + 1,
          currentSnoozeCount: 0,
          clearSnooze: true,
          updatedAtUtc: nowUtc,
        );
        alarmMap[alarmId] = updatedAlarm;
        await saveAlarm(updatedAlarm);
      }
    }
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
      repeatRuleJson: alarm.repeatRule.toJsonString(),
      creatorTimezoneId: alarm.creatorTimezoneId,
      startAtMillis: alarm.startAtUtc.millisecondsSinceEpoch,
      occurrenceCount: alarm.occurrenceCount,
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
