import 'dart:convert';

enum AlarmType { personal, group, buddy }

enum AlarmState { upcoming, ringing, done, missed, archived }

enum RepeatFrequency { none, hourly, daily, weekly, monthly, yearly, custom }

enum CustomRepeatUnit { hours, days, weeks, months }

enum ParticipantStatus { pending, confirmed, declined, done, missed }

class RepeatRule {
  final RepeatFrequency frequency;
  final int interval;
  final CustomRepeatUnit customUnit;
  final List<int> weekdays; // 1 = Monday .. 7 = Sunday (ISO 8601)
  final int? dayOfMonth;
  final bool lastDayOfMonth;
  final int? nthWeekday; // e.g. 2 for 2nd Saturday of month
  final String? customPreset;
  final DateTime? endDateUtc;
  final int? maxOccurrences;

  const RepeatRule({
    this.frequency = RepeatFrequency.none,
    this.interval = 1,
    this.customUnit = CustomRepeatUnit.days,
    this.weekdays = const [],
    this.dayOfMonth,
    this.lastDayOfMonth = false,
    this.nthWeekday,
    this.customPreset,
    this.endDateUtc,
    this.maxOccurrences,
  });

  bool get isRecurring => frequency != RepeatFrequency.none;

  String get displayLabel {
    if (frequency != RepeatFrequency.custom) {
      return frequency.name.toUpperCase();
    }
    switch (customPreset) {
      case 'alternate_days':
        return 'Repeat on alternate days';
      case 'every_3_days':
        return 'Repeat every 3 days';
      case 'every_2_weeks':
        return 'Repeat every 2 weeks';
      case 'quarterly':
        return 'Repeat every 3 months (quarterly)';
      case 'last_day_of_month':
        return 'Repeat last day of every month';
      case '2nd_saturday_of_month':
        return 'Repeat on 2nd Saturday of every month';
      default:
        if (lastDayOfMonth) return 'Repeat last day of every month';
        if (nthWeekday == 2 && weekdays.contains(DateTime.saturday)) {
          return 'Repeat on 2nd Saturday of every month';
        }
        if (customUnit == CustomRepeatUnit.days && interval == 2) {
          return 'Repeat on alternate days';
        }
        return 'Every $interval ${customUnit.name}';
    }
  }

  Map<String, dynamic> toJson() => {
        'frequency': frequency.name,
        'interval': interval,
        'customUnit': customUnit.name,
        'weekdays': weekdays,
        'dayOfMonth': dayOfMonth,
        'lastDayOfMonth': lastDayOfMonth,
        'nthWeekday': nthWeekday,
        'customPreset': customPreset,
        'endDateUtc': endDateUtc?.toIso8601String(),
        'maxOccurrences': maxOccurrences,
      };

  factory RepeatRule.fromJson(Map<String, dynamic> json) {
    return RepeatRule(
      frequency: RepeatFrequency.values.firstWhere(
        (e) => e.name == json['frequency'],
        orElse: () => RepeatFrequency.none,
      ),
      interval: (json['interval'] as num?)?.toInt() ?? 1,
      customUnit: CustomRepeatUnit.values.firstWhere(
        (e) => e.name == json['customUnit'],
        orElse: () => CustomRepeatUnit.days,
      ),
      weekdays: (json['weekdays'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          const [],
      dayOfMonth: (json['dayOfMonth'] as num?)?.toInt(),
      lastDayOfMonth: json['lastDayOfMonth'] as bool? ?? false,
      nthWeekday: (json['nthWeekday'] as num?)?.toInt(),
      customPreset: json['customPreset'] as String?,
      endDateUtc: json['endDateUtc'] != null
          ? DateTime.tryParse(json['endDateUtc'] as String)?.toUtc()
          : null,
      maxOccurrences: (json['maxOccurrences'] as num?)?.toInt(),
    );
  }

  String toJsonString() => jsonEncode(toJson());

  factory RepeatRule.fromJsonString(String raw) {
    if (raw.isEmpty) return const RepeatRule();
    return RepeatRule.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

class SnoozeConfig {
  final int snoozeDurationMinutes;
  final int maxSnoozeCount;
  final bool autoSnooze;
  final int ringDurationSeconds; // 0 = continuous until dismissed

  const SnoozeConfig({
    this.snoozeDurationMinutes = 5,
    this.maxSnoozeCount = 3,
    this.autoSnooze = true,
    this.ringDurationSeconds = 0,
  });

  Map<String, dynamic> toJson() => {
        'snoozeDurationMinutes': snoozeDurationMinutes,
        'maxSnoozeCount': maxSnoozeCount,
        'autoSnooze': autoSnooze,
        'ringDurationSeconds': ringDurationSeconds,
      };

  factory SnoozeConfig.fromJson(Map<String, dynamic> json) => SnoozeConfig(
        snoozeDurationMinutes:
            (json['snoozeDurationMinutes'] as num?)?.toInt() ?? 5,
        maxSnoozeCount: (json['maxSnoozeCount'] as num?)?.toInt() ?? 3,
        autoSnooze: json['autoSnooze'] as bool? ?? true,
        ringDurationSeconds:
            (json['ringDurationSeconds'] as num?)?.toInt() ?? 0,
      );

  String toJsonString() => jsonEncode(toJson());

  factory SnoozeConfig.fromJsonString(String raw) {
    if (raw.isEmpty) return const SnoozeConfig();
    return SnoozeConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }
}

class AlarmParticipant {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final String? timezoneId;
  final ParticipantStatus status;
  final DateTime? updatedAtUtc;

  const AlarmParticipant({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.timezoneId,
    this.status = ParticipantStatus.pending,
    this.updatedAtUtc,
  });

  AlarmParticipant copyWith({
    ParticipantStatus? status,
    DateTime? updatedAtUtc,
  }) {
    return AlarmParticipant(
      uid: uid,
      displayName: displayName,
      photoUrl: photoUrl,
      timezoneId: timezoneId,
      status: status ?? this.status,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    );
  }
}

class AlarmOccurrence {
  final int occurrenceIndex;
  final DateTime scheduledAtUtc;
  final AlarmState state;
  final int snoozeCount;
  final DateTime? acknowledgedAtUtc;

  const AlarmOccurrence({
    required this.occurrenceIndex,
    required this.scheduledAtUtc,
    required this.state,
    this.snoozeCount = 0,
    this.acknowledgedAtUtc,
  });
}

class Alarm {
  final String id;
  final String ownerId;
  final String title;
  final String notes;
  final DateTime startAtUtc;
  final String creatorTimezoneId;
  final RepeatRule repeatRule;
  final SnoozeConfig snoozeConfig;
  final String ringtoneUri; // "default", "chime", "radar", or file:// URI
  final double volume; // 0.0 - 1.0
  final bool gradualVolume;
  final bool vibrate;
  final bool ringOnVibrateSilent;
  final AlarmType type;
  final AlarmState state;
  final bool isEnabled;
  final int occurrenceCount;
  final int currentSnoozeCount;
  final DateTime? snoozedUntilUtc;
  final DateTime updatedAtUtc;
  final List<AlarmParticipant> participants;

  const Alarm({
    required this.id,
    required this.ownerId,
    required this.title,
    this.notes = '',
    required this.startAtUtc,
    required this.creatorTimezoneId,
    this.repeatRule = const RepeatRule(),
    this.snoozeConfig = const SnoozeConfig(),
    this.ringtoneUri = 'default',
    this.volume = 0.85,
    this.gradualVolume = true,
    this.vibrate = true,
    this.ringOnVibrateSilent = true,
    this.type = AlarmType.personal,
    this.state = AlarmState.upcoming,
    this.isEnabled = true,
    this.occurrenceCount = 0,
    this.currentSnoozeCount = 0,
    this.snoozedUntilUtc,
    required this.updatedAtUtc,
    this.participants = const [],
  });

  Alarm copyWith({
    String? title,
    String? notes,
    DateTime? startAtUtc,
    String? creatorTimezoneId,
    RepeatRule? repeatRule,
    SnoozeConfig? snoozeConfig,
    String? ringtoneUri,
    double? volume,
    bool? gradualVolume,
    bool? vibrate,
    bool? ringOnVibrateSilent,
    AlarmType? type,
    AlarmState? state,
    bool? isEnabled,
    int? occurrenceCount,
    int? currentSnoozeCount,
    DateTime? snoozedUntilUtc,
    bool clearSnooze = false,
    DateTime? updatedAtUtc,
    List<AlarmParticipant>? participants,
  }) {
    return Alarm(
      id: id,
      ownerId: ownerId,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      startAtUtc: startAtUtc ?? this.startAtUtc,
      creatorTimezoneId: creatorTimezoneId ?? this.creatorTimezoneId,
      repeatRule: repeatRule ?? this.repeatRule,
      snoozeConfig: snoozeConfig ?? this.snoozeConfig,
      ringtoneUri: ringtoneUri ?? this.ringtoneUri,
      volume: volume ?? this.volume,
      gradualVolume: gradualVolume ?? this.gradualVolume,
      vibrate: vibrate ?? this.vibrate,
      ringOnVibrateSilent: ringOnVibrateSilent ?? this.ringOnVibrateSilent,
      type: type ?? this.type,
      state: state ?? this.state,
      isEnabled: isEnabled ?? this.isEnabled,
      occurrenceCount: occurrenceCount ?? this.occurrenceCount,
      currentSnoozeCount: currentSnoozeCount ?? this.currentSnoozeCount,
      snoozedUntilUtc:
          clearSnooze ? null : (snoozedUntilUtc ?? this.snoozedUntilUtc),
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      participants: participants ?? this.participants,
    );
  }

  Map<String, dynamic> toBackupMap() => {
        'id': id,
        'ownerId': ownerId,
        'title': title,
        'notes': notes,
        'startAtUtc': startAtUtc.toUtc().toIso8601String(),
        'creatorTimezoneId': creatorTimezoneId,
        'repeatRule': repeatRule.toJson(),
        'snoozeConfig': snoozeConfig.toJson(),
        'ringtoneUri': ringtoneUri,
        'volume': volume,
        'gradualVolume': gradualVolume,
        'vibrate': vibrate,
        'ringOnVibrateSilent': ringOnVibrateSilent,
        'type': type.name,
        'state': state.name,
        'isEnabled': isEnabled,
        'occurrenceCount': occurrenceCount,
        'currentSnoozeCount': currentSnoozeCount,
        'snoozedUntilUtc': snoozedUntilUtc?.toUtc().toIso8601String(),
        'updatedAtUtc': updatedAtUtc.toUtc().toIso8601String(),
        'participants': participants
            .map((p) => {
                  'uid': p.uid,
                  'displayName': p.displayName,
                  'photoUrl': p.photoUrl,
                  'timezoneId': p.timezoneId,
                  'status': p.status.name,
                  'updatedAtUtc': p.updatedAtUtc?.toUtc().toIso8601String(),
                })
            .toList(),
      };

  factory Alarm.fromBackupMap(Map<String, dynamic> map) {
    final nowUtc = DateTime.now().toUtc();
    final rawParticipants = map['participants'] as List<dynamic>? ?? const [];
    final parsedParticipants = rawParticipants
        .whereType<Map<String, dynamic>>()
        .map(
          (p) => AlarmParticipant(
            uid: (p['uid'] as String?) ?? '',
            displayName: (p['displayName'] as String?) ?? 'Member',
            photoUrl: p['photoUrl'] as String?,
            timezoneId: p['timezoneId'] as String?,
            status: ParticipantStatus.values.firstWhere(
              (e) => e.name == p['status'],
              orElse: () => ParticipantStatus.pending,
            ),
            updatedAtUtc: p['updatedAtUtc'] != null
                ? DateTime.tryParse(p['updatedAtUtc'] as String)?.toUtc()
                : null,
          ),
        )
        .where((p) => p.uid.isNotEmpty)
        .toList();

    return Alarm(
      id: (map['id'] as String?)?.isNotEmpty == true
          ? map['id'] as String
          : 'restored_${nowUtc.microsecondsSinceEpoch}',
      ownerId: (map['ownerId'] as String?) ?? 'local_user',
      title: (map['title'] as String?) ?? 'Alarm',
      notes: (map['notes'] as String?) ?? '',
      startAtUtc: map['startAtUtc'] != null
          ? (DateTime.tryParse(map['startAtUtc'] as String)?.toUtc() ?? nowUtc)
          : nowUtc,
      creatorTimezoneId: (map['creatorTimezoneId'] as String?) ?? 'UTC',
      repeatRule: map['repeatRule'] is Map<String, dynamic>
          ? RepeatRule.fromJson(map['repeatRule'] as Map<String, dynamic>)
          : RepeatRule.fromJsonString((map['repeatRuleJson'] as String?) ?? ''),
      snoozeConfig: map['snoozeConfig'] is Map<String, dynamic>
          ? SnoozeConfig.fromJson(map['snoozeConfig'] as Map<String, dynamic>)
          : SnoozeConfig.fromJsonString((map['snoozeConfigJson'] as String?) ?? ''),
      ringtoneUri: (map['ringtoneUri'] as String?) ?? 'default',
      volume: (map['volume'] as num?)?.toDouble() ?? 0.85,
      gradualVolume: map['gradualVolume'] as bool? ?? true,
      vibrate: map['vibrate'] as bool? ?? true,
      ringOnVibrateSilent: map['ringOnVibrateSilent'] as bool? ?? true,
      type: AlarmType.values.firstWhere(
        (e) => e.name == map['type'],
        orElse: () => AlarmType.personal,
      ),
      state: AlarmState.values.firstWhere(
        (e) => e.name == map['state'],
        orElse: () => AlarmState.upcoming,
      ),
      isEnabled: map['isEnabled'] as bool? ?? true,
      occurrenceCount: (map['occurrenceCount'] as num?)?.toInt() ?? 0,
      currentSnoozeCount: (map['currentSnoozeCount'] as num?)?.toInt() ?? 0,
      snoozedUntilUtc: map['snoozedUntilUtc'] != null
          ? DateTime.tryParse(map['snoozedUntilUtc'] as String)?.toUtc()
          : null,
      updatedAtUtc: map['updatedAtUtc'] != null
          ? (DateTime.tryParse(map['updatedAtUtc'] as String)?.toUtc() ?? nowUtc)
          : nowUtc,
      participants: parsedParticipants,
    );
  }
}

class ChatMessage {
  final String id;
  final String alarmId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime sentAtUtc;
  final List<String> readBy;

  const ChatMessage({
    required this.id,
    required this.alarmId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAtUtc,
    this.readBy = const [],
  });
}

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String kind; // participant_added, group_change, chat, buddy_done, buddy_missed, invite
  final String? alarmId;
  final DateTime createdAtUtc;
  final bool isRead;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.kind,
    this.alarmId,
    required this.createdAtUtc,
    this.isRead = false,
  });
}

class UserProfile {
  final String uid;
  final String phoneNumber;
  final String phoneHash;
  final String displayName;
  final String? photoUrl;
  final String timezoneId;

  const UserProfile({
    required this.uid,
    this.phoneNumber = '',
    required this.phoneHash,
    required this.displayName,
    this.photoUrl,
    required this.timezoneId,
  });
}
