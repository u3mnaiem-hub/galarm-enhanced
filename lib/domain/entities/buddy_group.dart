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

/// Independent member stored directly inside a [SavedGroup] (not linked to [SavedBuddy]).
class GroupMember {
  final String id;
  final String name;
  final String phone;

  const GroupMember({
    required this.id,
    required this.name,
    this.phone = '',
  });

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
      };

  factory GroupMember.fromJson(Map<String, dynamic> map) {
    return GroupMember(
      id: (map['id'] as String?)?.isNotEmpty == true
          ? map['id'] as String
          : 'member_${DateTime.now().microsecondsSinceEpoch}',
      name: (map['name'] as String?) ?? 'Member',
      phone: (map['phone'] as String?) ?? '',
    );
  }
}

class SavedGroup {
  final String id;
  final String name;
  final List<GroupMember> members;
  final DateTime createdAtUtc;

  const SavedGroup({
    required this.id,
    required this.name,
    this.members = const [],
    required this.createdAtUtc,
  });

  SavedGroup copyWith({
    String? name,
    List<GroupMember>? members,
  }) {
    return SavedGroup(
      id: id,
      name: name ?? this.name,
      members: members ?? this.members,
      createdAtUtc: createdAtUtc,
    );
  }

  /// Stored in `groups_table.member_ids_json` as JSON array of GroupMember objects.
  String get membersJson => jsonEncode(members.map((m) => m.toJson()).toList());

  static List<GroupMember> decodeMembers(String raw) {
    if (raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        final list = <GroupMember>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            list.add(GroupMember.fromJson(item));
          } else if (item is Map) {
            list.add(GroupMember.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        return list;
      }
    } catch (_) {}
    return const [];
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'members': members.map((m) => m.toJson()).toList(),
        'createdAtUtc': createdAtUtc.toUtc().toIso8601String(),
      };

  factory SavedGroup.fromJson(Map<String, dynamic> map) {
    final nowUtc = DateTime.now().toUtc();
    final rawMembers = map['members'];
    final parsed = <GroupMember>[];
    if (rawMembers is List) {
      for (final item in rawMembers) {
        if (item is Map<String, dynamic>) {
          parsed.add(GroupMember.fromJson(item));
        } else if (item is Map) {
          parsed.add(GroupMember.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else if (rawMembers is String) {
      parsed.addAll(decodeMembers(rawMembers));
    }
    return SavedGroup(
      id: (map['id'] as String?)?.isNotEmpty == true
          ? map['id'] as String
          : 'group_${nowUtc.microsecondsSinceEpoch}',
      name: (map['name'] as String?) ?? 'Group',
      members: parsed,
      createdAtUtc: map['createdAtUtc'] != null
          ? (DateTime.tryParse(map['createdAtUtc'] as String)?.toUtc() ?? nowUtc)
          : nowUtc,
    );
  }
}
