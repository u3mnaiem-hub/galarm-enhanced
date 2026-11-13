import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import '../../domain/entities/alarm.dart';

class FirestoreService {
  final FirebaseFirestore _db;

  FirestoreService({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  /// Normalizes a phone number (digits + leading +) and hashes it with SHA-256
  /// so raw phone numbers are never sent when matching contacts.
  static String hashPhoneNumber(String rawPhone, {String defaultCountryCode = '+20'}) {
    var cleaned = rawPhone.replaceAll(RegExp(r'[\s\-\(\)]'), '');
    if (cleaned.startsWith('00')) {
      cleaned = '+${cleaned.substring(2)}';
    } else if (!cleaned.startsWith('+')) {
      if (cleaned.startsWith('0')) {
        cleaned = '$defaultCountryCode${cleaned.substring(1)}';
      } else {
        cleaned = '$defaultCountryCode$cleaned';
      }
    }
    return sha256.convert(utf8.encode(cleaned)).toString();
  }

  Future<void> upsertUserProfile(UserProfile profile) async {
    await _db.collection('users').doc(profile.uid).set({
      'uid': profile.uid,
      'phoneHash': profile.phoneHash,
      'displayName': profile.displayName,
      'photoUrl': profile.photoUrl,
      'timezoneId': profile.timezoneId,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> updateFcmToken(String uid, String token) async {
    await _db.collection('users').doc(uid).set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
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
          phoneHash: d['phoneHash'] as String? ?? '',
          displayName: d['displayName'] as String? ?? 'User',
          photoUrl: d['photoUrl'] as String?,
          timezoneId: d['timezoneId'] as String? ?? 'UTC',
        ));
      }
    }
    return results;
  }

  Future<void> syncAlarm(Alarm alarm) async {
    final docRef = _db.collection('alarms').doc(alarm.id);
    await docRef.set({
      'ownerId': alarm.ownerId,
      'title': alarm.title,
      'notes': alarm.notes,
      'startAtUtc': Timestamp.fromDate(alarm.startAtUtc.toUtc()),
      'tz': alarm.creatorTimezoneId,
      'repeatRule': alarm.repeatRule.toJson(),
      'snoozeConfig': alarm.snoozeConfig.toJson(),
      'ringtone': alarm.ringtoneUri,
      'volume': alarm.volume,
      'gradualVolume': alarm.gradualVolume,
      'vibrate': alarm.vibrate,
      'ringOnVibrateSilent': alarm.ringOnVibrateSilent,
      'type': alarm.type.name,
      'state': alarm.state.name,
      'isEnabled': alarm.isEnabled,
      'participantUids': [
        alarm.ownerId,
        ...alarm.participants.map((p) => p.uid),
      ].toSet().toList(),
      'updatedAt': Timestamp.fromDate(alarm.updatedAtUtc.toUtc()),
    }, SetOptions(merge: true));

    for (final p in alarm.participants) {
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
