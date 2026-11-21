import 'dart:convert';
import 'alarm.dart';

class SavedBuddy {
  final String id;
  final String name;
  final String phone;
  final DateTime createdAtUtc;

  const SavedBuddy({
    required this.id,
    required this.name,
    this.phone = '',
    required this.createdAtUtc,
  });

  SavedBuddy copyWith({
    String? name,
    String? phone,
  }) {
    return SavedBuddy(
      id: id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      createdAtUtc: createdAtUtc,
    );
  }

  AlarmParticipant toAlarmParticipant() {
    return AlarmParticipant(
      uid: id,
      displayName: phone.isNotEmpty ? '$name ($phone)' : name,
      status: ParticipantStatus.pending,
      updatedAtUtc: DateTime.now().toUtc(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'phone': phone,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      };

  factory SavedBuddy.fromJson(Map<String, dynamic> map) {
    final nowUtc = DateTime.now().toUtc();
    return SavedBuddy(
      id: (map['id'] as String?)?.isNotEmpty == true
          ? map['id'] as String
          : 'buddy_${nowUtc.microsecondsSinceEpoch}',
      name: (map['name'] as String?) ?? 'Buddy',
      phone: (map['phone'] as String?) ?? '',
      createdAtUtc: map['createdAtUtc'] != null
          ? (DateTime.tryParse(map['createdAtUtc'] as String)?.toUtc() ?? nowUtc)
          : nowUtc,
    );
  }
}

class SavedGroup {
  final String id;
  final String name;
  final List<String> memberIds;
  final DateTime createdAtUtc;

  const SavedGroup({
    required this.id,
    required this.name,
    this.memberIds = const [],
    required this.createdAtUtc,
  });

  SavedGroup copyWith({
    String? name,
    List<String>? memberIds,
  }) {
    return SavedGroup(
      id: id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      createdAtUtc: createdAtUtc,
    );
  }

  String get memberIdsJson => jsonEncode(memberIds);

  static List<String> decodeMemberIds(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'memberIds': memberIds,
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      };

  factory SavedGroup.fromJson(Map<String, dynamic> map) {
    final nowUtc = DateTime.now().toUtc();
    final rawMembers = map['memberIds'];
    final members = rawMembers is List
        ? rawMembers.map((e) => e.toString()).toList()
        : (rawMembers is String ? decodeMemberIds(rawMembers) : const <String>[]);
    return SavedGroup(
      id: (map['id'] as String?)?.isNotEmpty == true
          ? map['id'] as String
          : 'group_${nowUtc.microsecondsSinceEpoch}',
      name: (map['name'] as String?) ?? 'Group',
      memberIds: members,
      createdAtUtc: map['createdAtUtc'] != null
          ? (DateTime.tryParse(map['createdAtUtc'] as String)?.toUtc() ?? nowUtc)
          : nowUtc,
    );
  }
}
