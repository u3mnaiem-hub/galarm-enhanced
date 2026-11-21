import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

class AlarmsTable extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text()();
  TextColumn get title => text()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  DateTimeColumn get startAtUtc => dateTime()();
  TextColumn get creatorTimezoneId => text()();
  TextColumn get repeatRuleJson => text().withDefault(const Constant('{}'))();
  TextColumn get snoozeConfigJson => text().withDefault(const Constant('{}'))();
  TextColumn get ringtoneUri => text().withDefault(const Constant('default'))();
  RealColumn get volume => real().withDefault(const Constant(0.85))();
  BoolColumn get gradualVolume => boolean().withDefault(const Constant(true))();
  BoolColumn get vibrate => boolean().withDefault(const Constant(true))();
  BoolColumn get ringOnVibrateSilent => boolean().withDefault(const Constant(true))();
  TextColumn get alarmType => text().withDefault(const Constant('personal'))();
  TextColumn get state => text().withDefault(const Constant('upcoming'))();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(true))();
  IntColumn get occurrenceCount => integer().withDefault(const Constant(0))();
  IntColumn get currentSnoozeCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get snoozedUntilUtc => dateTime().nullable()();
  DateTimeColumn get updatedAtUtc => dateTime()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class AlarmParticipantsTable extends Table {
  TextColumn get alarmId => text()();
  TextColumn get uid => text()();
  TextColumn get displayName => text()();
  TextColumn get photoUrl => text().nullable()();
  TextColumn get timezoneId => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  DateTimeColumn get updatedAtUtc => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {alarmId, uid};
}

class AlarmOccurrencesTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get alarmId => text()();
  IntColumn get occurrenceIndex => integer()();
  DateTimeColumn get scheduledAtUtc => dateTime()();
  TextColumn get state => text()();
  IntColumn get snoozeCount => integer().withDefault(const Constant(0))();
  DateTimeColumn get acknowledgedAtUtc => dateTime().nullable()();
}

class SyncQueueTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get entityType => text()(); // 'alarm', 'participant', 'delete_alarm'
  TextColumn get entityId => text()();
  TextColumn get payloadJson => text()();
  DateTimeColumn get createdAtUtc => dateTime()();
}

class NotificationsTable extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get body => text()();
  TextColumn get kind => text()();
  TextColumn get alarmId => text().nullable()();
  DateTimeColumn get createdAtUtc => dateTime()();
  BoolColumn get isRead => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {id};
}

class BlockedUsersTable extends Table {
  TextColumn get uid => text()();
  TextColumn get displayName => text()();
  DateTimeColumn get blockedAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {uid};
}

class BuddiesTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get phone => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

class GroupsTable extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get memberIdsJson => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAtUtc => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  AlarmsTable,
  AlarmParticipantsTable,
  AlarmOccurrencesTable,
  SyncQueueTable,
  NotificationsTable,
  BlockedUsersTable,
  BuddiesTable,
  GroupsTable,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(buddiesTable);
            await m.createTable(groupsTable);
          }
        },
      );

  Future<List<AlarmsTableData>> getActiveAlarms() =>
      (select(alarmsTable)..where((t) => t.isDeleted.equals(false))).get();

  Stream<List<AlarmsTableData>> watchActiveAlarms() =>
      (select(alarmsTable)
            ..where((t) => t.isDeleted.equals(false))
            ..orderBy([(t) => OrderingTerm.asc(t.startAtUtc)]))
          .watch();

  Future<void> upsertAlarm(AlarmsTableCompanion entry) =>
      into(alarmsTable).insertOnConflictUpdate(entry);

  Future<void> softDeleteAlarm(String alarmId, DateTime nowUtc) =>
      (update(alarmsTable)..where((t) => t.id.equals(alarmId))).write(
        AlarmsTableCompanion(
          isDeleted: const Value(true),
          isEnabled: const Value(false),
          updatedAtUtc: Value(nowUtc),
        ),
      );

  Future<List<AlarmParticipantsTableData>> getParticipantsForAlarm(String alarmId) =>
      (select(alarmParticipantsTable)..where((t) => t.alarmId.equals(alarmId))).get();

  Future<void> upsertParticipant(AlarmParticipantsTableCompanion entry) =>
      into(alarmParticipantsTable).insertOnConflictUpdate(entry);

  Future<void> deleteParticipantsForAlarm(String alarmId) =>
      (delete(alarmParticipantsTable)..where((t) => t.alarmId.equals(alarmId))).go();

  Future<void> insertOccurrence(AlarmOccurrencesTableCompanion entry) =>
      into(alarmOccurrencesTable).insert(entry);

  Future<List<AlarmOccurrencesTableData>> getOccurrencesForAlarm(String alarmId) =>
      (select(alarmOccurrencesTable)
            ..where((t) => t.alarmId.equals(alarmId))
            ..orderBy([(t) => OrderingTerm.desc(t.scheduledAtUtc)]))
          .get();

  Future<void> enqueueSync(String entityType, String entityId, String payloadJson) =>
      into(syncQueueTable).insert(
        SyncQueueTableCompanion.insert(
          entityType: entityType,
          entityId: entityId,
          payloadJson: payloadJson,
          createdAtUtc: DateTime.now().toUtc(),
        ),
      );

  Future<List<SyncQueueTableData>> getPendingSyncItems() =>
      (select(syncQueueTable)..orderBy([(t) => OrderingTerm.asc(t.id)])).get();

  Future<void> removeSyncItem(int id) =>
      (delete(syncQueueTable)..where((t) => t.id.equals(id))).go();

  Stream<List<NotificationsTableData>> watchNotifications() =>
      (select(notificationsTable)..orderBy([(t) => OrderingTerm.desc(t.createdAtUtc)])).watch();

  Future<void> upsertNotification(NotificationsTableCompanion entry) =>
      into(notificationsTable).insertOnConflictUpdate(entry);

  Future<void> markNotificationRead(String id) =>
      (update(notificationsTable)..where((t) => t.id.equals(id)))
          .write(const NotificationsTableCompanion(isRead: Value(true)));

  Future<void> clearNotifications() => delete(notificationsTable).go();

  Stream<List<BlockedUsersTableData>> watchBlockedUsers() =>
      select(blockedUsersTable).watch();

  Future<void> blockUser(String uid, String displayName) =>
      into(blockedUsersTable).insertOnConflictUpdate(
        BlockedUsersTableCompanion.insert(
          uid: uid,
          displayName: displayName,
          blockedAtUtc: DateTime.now().toUtc(),
        ),
      );

  Future<void> unblockUser(String uid) =>
      (delete(blockedUsersTable)..where((t) => t.uid.equals(uid))).go();

  // Buddies CRUD
  Stream<List<BuddiesTableData>> watchBuddies() =>
      (select(buddiesTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<BuddiesTableData>> getAllBuddies() =>
      (select(buddiesTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<void> upsertBuddy(BuddiesTableCompanion entry) =>
      into(buddiesTable).insertOnConflictUpdate(entry);

  Future<void> deleteBuddy(String id) =>
      (delete(buddiesTable)..where((t) => t.id.equals(id))).go();

  // Groups CRUD
  Stream<List<GroupsTableData>> watchGroups() =>
      (select(groupsTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();

  Future<List<GroupsTableData>> getAllGroups() =>
      (select(groupsTable)..orderBy([(t) => OrderingTerm.asc(t.name)])).get();

  Future<void> upsertGroup(GroupsTableCompanion entry) =>
      into(groupsTable).insertOnConflictUpdate(entry);

  Future<void> deleteGroup(String id) =>
      (delete(groupsTable)..where((t) => t.id.equals(id))).go();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'galarm_enhanced.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
