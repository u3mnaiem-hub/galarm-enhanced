import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import '../../domain/entities/alarm.dart';

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Normalizes a phone number into E.164 format (e.g. "+201012345678").
  static String normalizePhoneNumber(
    String rawPhone, {
    String defaultCountryCode = '+20',
  }) {
    var cleaned = rawPhone.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    if (cleaned.isEmpty) return '';
    if (cleaned.startsWith('00')) {
      cleaned = '+${cleaned.substring(2)}';
    } else if (!cleaned.startsWith('+')) {
      if (cleaned.startsWith('0')) {
        cleaned = '$defaultCountryCode${cleaned.substring(1)}';
      } else {
        cleaned = '$defaultCountryCode$cleaned';
      }
    }
    return cleaned;
  }

  /// Normalizes a phone number and hashes it with SHA-256.
  static String hashPhoneNumber(
    String rawPhone, {
    String defaultCountryCode = '+20',
  }) {
    final cleaned = normalizePhoneNumber(
      rawPhone,
      defaultCountryCode: defaultCountryCode,
    );
    return sha256.convert(utf8.encode(cleaned)).toString();
  }

  /// Saves the signed-in user in `users/{uid}` and indexes them by normalized phone
  /// number in `users_by_phone/{phoneNumber}` so buddies/groups can reach them directly.
  Future<void> upsertUserProfile(UserProfile profile) async {
    final normalizedPhone = profile.phoneNumber.isNotEmpty
        ? normalizePhoneNumber(profile.phoneNumber)
        : '';

    await _db.collection('users').doc(profile.uid).set({
      'uid': profile.uid,
      'phoneNumber': normalizedPhone,
      'phoneHash': profile.phoneHash,
      'displayName': profile.displayName,
      'photoUrl': profile.photoUrl,
      'timezoneId': profile.timezoneId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    if (normalizedPhone.isNotEmpty) {
      await _db.collection('users_by_phone').doc(normalizedPhone).set({
        'uid': profile.uid,
        'phoneNumber': normalizedPhone,
        'phoneHash': profile.phoneHash,
        'displayName': profile.displayName,
        'timezoneId': profile.timezoneId,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  Future<void> updateFcmToken(
    String uid,
    String token, {
    String? phoneNumber,
  }) async {
    if (uid.isEmpty || token.isEmpty) return;
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final normalizedPhone =
        phoneNumber != null && phoneNumber.isNotEmpty ? normalizePhoneNumber(phoneNumber) : '';
    if (normalizedPhone.isNotEmpty) {
      await _db.collection('users_by_phone').doc(normalizedPhone).set({
        'uid': uid,
        'fcmTokens': FieldValue.arrayUnion([token]),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Looks up a registered U3m Alarm user by phone number.
  Future<UserProfile?> findUserByPhone(String rawPhone) async {
    final normalized = normalizePhoneNumber(rawPhone);
    if (normalized.isEmpty) return null;

    final byPhoneDoc =
        await _db.collection('users_by_phone').doc(normalized).get();
    if (byPhoneDoc.exists) {
      final d = byPhoneDoc.data()!;
      return UserProfile(
        uid: (d['uid'] as String?) ?? byPhoneDoc.id,
        phoneNumber: (d['phoneNumber'] as String?) ?? normalized,
        phoneHash: (d['phoneHash'] as String?) ?? hashPhoneNumber(normalized),
        displayName: (d['displayName'] as String?) ?? normalized,
        photoUrl: d['photoUrl'] as String?,
        timezoneId: (d['timezoneId'] as String?) ?? 'Africa/Cairo',
      );
    }

    final snap = await _db
        .collection('users')
        .where('phoneNumber', isEqualTo: normalized)
        .limit(1)
        .get();
    if (snap.docs.isNotEmpty) {
      final doc = snap.docs.first;
      final d = doc.data();
      return UserProfile(
        uid: doc.id,
        phoneNumber: (d['phoneNumber'] as String?) ?? normalized,
        phoneHash: (d['phoneHash'] as String?) ?? '',
        displayName: (d['displayName'] as String?) ?? normalized,
        photoUrl: d['photoUrl'] as String?,
        timezoneId: (d['timezoneId'] as String?) ?? 'Africa/Cairo',
      );
    }
    return null;
  }

  /// Matches a list of SHA-256 phone hashes against registered users (chunked by 10 for Firestore `whereIn`).
  Future<List<UserProfile>> matchPhoneHashes(List<String> phoneHashes) async {
    if (phoneHashes.isEmpty) return [];
    final results = <UserProfile>[];
    for (var i = 0; i < phoneHashes.length; i += 10) {
      final chunk = phoneHashes.sublist(i, (i + 10).clamp(0, phoneHashes.length));
      final snap = await _db
          .collection('users')
          .where('phoneHash', whereIn: chunk)
          .get();
      for (final doc in snap.docs) {
        final d = doc.data();
        results.add(UserProfile(
          uid: doc.id,
          phoneNumber: d['phoneNumber'] as String? ?? '',
          phoneHash: d['phoneHash'] as String? ?? '',
          displayName: d['displayName'] as String? ?? 'User',
          photoUrl: d['photoUrl'] as String?,
          timezoneId: d['timezoneId'] as String? ?? 'UTC',
        ));
      }
    }
    return results;
  }

  /// Syncs a buddy/group alarm to Firestore and resolves recipients by phone number
  /// so Cloud Functions (FCM) and real-time listeners ring the alarm on their phones.
  Future<void> syncAlarm(
    Alarm alarm, {
    List<String> recipientPhones = const [],
  }) async {
    final docRef = _db.collection('alarms').doc(alarm.id);

    final resolvedParticipants = <AlarmParticipant>[];
    final normalizedPhones = <String>{};

    for (final rawPhone in recipientPhones) {
      final norm = normalizePhoneNumber(rawPhone);
      if (norm.isNotEmpty) normalizedPhones.add(norm);
    }

    for (final p in alarm.participants) {
      // Extract phone number if stored inside displayName like "Ahmed (+2010...)"
      String? extractedPhone;
      final phoneMatch = RegExp(r'\(([\+\d\s\-]{6,})\)').firstMatch(p.displayName);
      if (phoneMatch != null) {
        extractedPhone = normalizePhoneNumber(phoneMatch.group(1)!);
        if (extractedPhone.isNotEmpty) normalizedPhones.add(extractedPhone);
      }

      UserProfile? remoteUser;
      if (extractedPhone != null && extractedPhone.isNotEmpty) {
        remoteUser = await findUserByPhone(extractedPhone);
      }

      resolvedParticipants.add(
        AlarmParticipant(
          uid: remoteUser?.uid ?? p.uid,
          displayName: remoteUser?.displayName ?? p.displayName,
          photoUrl: remoteUser?.photoUrl ?? p.photoUrl,
          timezoneId: remoteUser?.timezoneId ?? p.timezoneId,
          status: p.status,
          updatedAtUtc: p.updatedAtUtc,
        ),
      );
    }

    // Also resolve any extra recipientPhones that weren't in participants
    for (final phone in normalizedPhones) {
      final user = await findUserByPhone(phone);
      if (user != null && !resolvedParticipants.any((p) => p.uid == user.uid)) {
        resolvedParticipants.add(
          AlarmParticipant(
            uid: user.uid,
            displayName: user.displayName,
            photoUrl: user.photoUrl,
            timezoneId: user.timezoneId,
            status: ParticipantStatus.pending,
            updatedAtUtc: DateTime.now().toUtc(),
          ),
        );
      }
    }

    final participantUids = <String>{
      alarm.ownerId,
      ...resolvedParticipants.map((p) => p.uid),
    }.toList();

    await docRef.set({
      'id': alarm.id,
      'ownerId': alarm.ownerId,
      'title': alarm.title,
      'notes': alarm.notes,
      'startAtUtc': Timestamp.fromDate(alarm.startAtUtc.toUtc()),
      'startAtMillis': alarm.startAtUtc.toUtc().millisecondsSinceEpoch,
      'tz': alarm.creatorTimezoneId,
      'repeatRule': alarm.repeatRule.toJson(),
      'repeatRuleJson': alarm.repeatRule.toJsonString(),
      'snoozeConfig': alarm.snoozeConfig.toJson(),
      'ringtone': alarm.ringtoneUri,
      'volume': alarm.volume,
      'gradualVolume': alarm.gradualVolume,
      'vibrate': alarm.vibrate,
      'ringOnVibrateSilent': alarm.ringOnVibrateSilent,
      'type': alarm.type.name,
      'state': alarm.state.name,
      'isEnabled': alarm.isEnabled,
      'participantUids': participantUids,
      'participantPhones': normalizedPhones.toList(),
      'updatedAt': Timestamp.fromDate(alarm.updatedAtUtc.toUtc()),
    }, SetOptions(merge: true));

    for (final p in resolvedParticipants) {
      await docRef.collection('participants').doc(p.uid).set({
        'uid': p.uid,
        'displayName': p.displayName,
        'photoUrl': p.photoUrl,
        'timezoneId': p.timezoneId,
        'status': p.status.name,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    }
  }

  /// Watches shared buddy/group alarms sent to [myUid] in real time.
  Stream<List<Alarm>> watchSharedAlarmsForUser(String myUid) {
    if (myUid.isEmpty || myUid == 'local_user') {
      return const Stream.empty();
    }
    return _db
        .collection('alarms')
        .where('participantUids', arrayContains: myUid)
        .snapshots()
        .map((snap) => snap.docs.map(_mapDocToAlarm).whereType<Alarm>().toList());
  }

  /// Watches shared buddy/group alarms targeted at [myPhoneNumber] in real time.
  Stream<List<Alarm>> watchSharedAlarmsForPhone(String myPhoneNumber) {
    final normalized = normalizePhoneNumber(myPhoneNumber);
    if (normalized.isEmpty) {
      return const Stream.empty();
    }
    return _db
        .collection('alarms')
        .where('participantPhones', arrayContains: normalized)
        .snapshots()
        .map((snap) => snap.docs.map(_mapDocToAlarm).whereType<Alarm>().toList());
  }

  Alarm? _mapDocToAlarm(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final d = doc.data();
      final ts = d['startAtUtc'];
      final startAtUtc = ts is Timestamp
          ? ts.toDate().toUtc()
          : DateTime.fromMillisecondsSinceEpoch(
              (d['startAtMillis'] as num?)?.toInt() ??
                  DateTime.now().toUtc().millisecondsSinceEpoch,
              isUtc: true,
            );
      final updTs = d['updatedAt'];
      final updatedAtUtc =
          updTs is Timestamp ? updTs.toDate().toUtc() : DateTime.now().toUtc();

      return Alarm(
        id: doc.id,
        ownerId: (d['ownerId'] as String?) ?? 'remote_user',
        title: (d['title'] as String?) ?? 'Shared Alarm',
        notes: (d['notes'] as String?) ?? '',
        startAtUtc: startAtUtc,
        creatorTimezoneId: (d['tz'] as String?) ?? 'Africa/Cairo',
        repeatRule: d['repeatRule'] is Map<String, dynamic>
            ? RepeatRule.fromJson(d['repeatRule'] as Map<String, dynamic>)
            : RepeatRule.fromJsonString((d['repeatRuleJson'] as String?) ?? ''),
        snoozeConfig: d['snoozeConfig'] is Map<String, dynamic>
            ? SnoozeConfig.fromJson(d['snoozeConfig'] as Map<String, dynamic>)
            : const SnoozeConfig(),
        ringtoneUri: 'default',
        volume: (d['volume'] as num?)?.toDouble() ?? 0.85,
        gradualVolume: d['gradualVolume'] as bool? ?? true,
        vibrate: d['vibrate'] as bool? ?? true,
        ringOnVibrateSilent: d['ringOnVibrateSilent'] as bool? ?? true,
        type: AlarmType.values.firstWhere(
          (e) => e.name == d['type'],
          orElse: () => AlarmType.group,
        ),
        state: AlarmState.values.firstWhere(
          (e) => e.name == d['state'],
          orElse: () => AlarmState.upcoming,
        ),
        isEnabled: d['isEnabled'] as bool? ?? true,
        updatedAtUtc: updatedAtUtc,
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteAlarm(String alarmId) async {
    await _db.collection('alarms').doc(alarmId).delete();
  }

  Future<void> updateParticipantStatus({
    required String alarmId,
    required String uid,
    required ParticipantStatus status,
  }) async {
    await _db
        .collection('alarms')
        .doc(alarmId)
        .collection('participants')
        .doc(uid)
        .set({
      'status': status.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Publishes a lightweight status update on the shared alarm document so the creator
  /// and other group members see Done/Missed/Snoozed updates in their Notifications tab.
  Future<void> publishAlarmStatusEvent({
    required String alarmId,
    required String alarmTitle,
    required String alarmType,
    required String actorUid,
    required String actorName,
    required String status,
  }) async {
    final nowMillis = DateTime.now().toUtc().millisecondsSinceEpoch;
    final eventId = 'status_${alarmId}_${actorUid}_${status}_$nowMillis';
    await _db.collection('alarms').doc(alarmId).set({
      'lastStatusEvent': {
        'id': eventId,
        'alarmId': alarmId,
        'alarmTitle': alarmTitle,
        'alarmType': alarmType,
        'actorUid': actorUid,
        'actorName': actorName,
        'status': status,
        'atMillis': nowMillis,
      },
    }, SetOptions(merge: true));
  }

  /// Streams status events from shared alarms where [myUid] is a participant or owner.
  Stream<List<Map<String, dynamic>>> watchSharedAlarmStatusEvents(String myUid) {
    if (myUid.isEmpty || myUid == 'local_user') {
      return const Stream.empty();
    }
    return _db
        .collection('alarms')
        .where('participantUids', arrayContains: myUid)
        .snapshots()
        .map((snap) {
      final events = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final ev = doc.data()['lastStatusEvent'];
        if (ev is Map<String, dynamic>) {
          events.add(ev);
        }
      }
      return events;
    });
  }

  Future<void> recordOccurrence({
    required String alarmId,
    required AlarmOccurrence occurrence,
  }) async {
    await _db
        .collection('alarms')
        .doc(alarmId)
        .collection('occurrences')
        .doc(occurrence.occurrenceIndex.toString())
        .set({
      'occurrenceIndex': occurrence.occurrenceIndex,
      'scheduledAtUtc': Timestamp.fromDate(occurrence.scheduledAtUtc.toUtc()),
      'state': occurrence.state.name,
      'snoozeCount': occurrence.snoozeCount,
      'acknowledgedAtUtc': occurrence.acknowledgedAtUtc != null
          ? Timestamp.fromDate(occurrence.acknowledgedAtUtc!.toUtc())
          : null,
    }, SetOptions(merge: true));
  }

  Stream<List<ChatMessage>> watchChatMessages(String alarmId) {
    return _db
        .collection('alarms')
        .doc(alarmId)
        .collection('messages')
        .orderBy('sentAtUtc', descending: false)
        .snapshots()
        .map((snap) => snap.docs.map((doc) {
              final d = doc.data();
              return ChatMessage(
                id: doc.id,
                alarmId: alarmId,
                senderId: d['senderId'] as String? ?? '',
                senderName: d['senderName'] as String? ?? 'User',
                text: d['text'] as String? ?? '',
                sentAtUtc: (d['sentAtUtc'] as Timestamp?)?.toDate().toUtc() ??
                    DateTime.now().toUtc(),
                readBy: (d['readBy'] as List<dynamic>?)
                        ?.map((e) => e.toString())
                        .toList() ??
                    const [],
              );
            }).toList());
  }

  Future<void> sendChatMessage(ChatMessage msg) async {
    await _db
        .collection('alarms')
        .doc(msg.alarmId)
        .collection('messages')
        .doc(msg.id)
        .set({
      'senderId': msg.senderId,
      'senderName': msg.senderName,
      'text': msg.text,
      'sentAtUtc': Timestamp.fromDate(msg.sentAtUtc.toUtc()),
      'readBy': msg.readBy,
    });
  }

  Future<void> blockUser(String myUid, String targetUid, String displayName) async {
    await _db
        .collection('users')
        .doc(myUid)
        .collection('blocked')
        .doc(targetUid)
        .set({
      'uid': targetUid,
      'displayName': displayName,
      'blockedAtUtc': FieldValue.serverTimestamp(),
    });
  }

  Future<void> unblockUser(String myUid, String targetUid) async {
    await _db
        .collection('users')
        .doc(myUid)
        .collection('blocked')
        .doc(targetUid)
        .delete();
  }
}
