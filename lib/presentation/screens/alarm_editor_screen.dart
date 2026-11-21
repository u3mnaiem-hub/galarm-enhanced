import 'dart:io';
import '../../l10n/tr.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/entities/buddy_group.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'contacts_groups_tab.dart';
import 'custom_repeat_screen.dart';

class AlarmEditorScreen extends ConsumerStatefulWidget {
  final Alarm? existing;
  final AlarmType? initialType;
  const AlarmEditorScreen({super.key, this.existing, this.initialType});

  @override
  ConsumerState<AlarmEditorScreen> createState() => _AlarmEditorScreenState();
}

class _AlarmEditorScreenState extends ConsumerState<AlarmEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late RepeatFrequency _repeatFreq;
  late int _customInterval;
  late CustomRepeatUnit _customUnit;
  late List<int> _weekdays;
  late bool _lastDayOfMonth;
  int? _nthWeekday;
  String? _customPreset;

  late int _snoozeMinutes;
  late int _maxSnoozeCount;
  late int _ringDurationSec;
  late bool _autoSnooze;

  late String _ringtoneUri;
  late double _volume;
  late bool _gradualVolume;
  late bool _vibrate;
  late bool _ringOnVibrateSilent;

  late AlarmType _alarmType;
  late List<AlarmParticipant> _participants;
  String? _selectedBuddyId;
  String? _selectedGroupId;

  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPreviewing = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final initialLocal =
        (e?.startAtUtc ?? DateTime.now().add(const Duration(minutes: 5)))
            .toLocal();

    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _selectedDate =
        DateTime(initialLocal.year, initialLocal.month, initialLocal.day);
    _selectedTime =
        TimeOfDay(hour: initialLocal.hour, minute: initialLocal.minute);
    _repeatFreq = e?.repeatRule.frequency ?? RepeatFrequency.none;
    _customInterval = e?.repeatRule.interval ?? 2;
    _customUnit = e?.repeatRule.customUnit ?? CustomRepeatUnit.days;
    _weekdays = [...(e?.repeatRule.weekdays ?? const <int>[])];
    _lastDayOfMonth = e?.repeatRule.lastDayOfMonth ?? false;
    _nthWeekday = e?.repeatRule.nthWeekday;
    _customPreset = e?.repeatRule.customPreset ?? 'alternate_days';

    _snoozeMinutes = e?.snoozeConfig.snoozeDurationMinutes ?? 5;
    _maxSnoozeCount = e?.snoozeConfig.maxSnoozeCount ?? 3;
    _ringDurationSec = e?.snoozeConfig.ringDurationSeconds ?? 0;
    _autoSnooze = e?.snoozeConfig.autoSnooze ?? true;

    final mainDefaultUri = ref.read(defaultRingtoneUriProvider);
    _ringtoneUri = e?.ringtoneUri ?? mainDefaultUri;
    _volume = e?.volume ?? 0.85;
    _gradualVolume = e?.gradualVolume ?? true;
    _vibrate = e?.vibrate ?? true;
    _ringOnVibrateSilent = e?.ringOnVibrateSilent ?? true;

    _alarmType = e?.type ?? widget.initialType ?? AlarmType.personal;
    _participants = [...(e?.participants ?? const <AlarmParticipant>[])];
    if (_alarmType == AlarmType.buddy && _participants.isNotEmpty) {
      _selectedBuddyId = _participants.first.uid;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _notesCtrl.dispose();
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickCustomAudio() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final pickedPath = result.files.single.path!;
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final ringtonesDir = Directory(p.join(docsDir.path, 'ringtones'));
        if (!await ringtonesDir.exists()) {
          await ringtonesDir.create(recursive: true);
        }
        final fileName = p.basename(pickedPath);
        final savedPath = p.join(ringtonesDir.path, fileName);
        if (pickedPath != savedPath) {
          await File(pickedPath).copy(savedPath);
        }
        if (mounted) {
          setState(() => _ringtoneUri = savedPath);
        }
      } catch (_) {
        if (mounted) {
          setState(() => _ringtoneUri = pickedPath);
        }
      }
    }
  }

  Future<void> _togglePreview() async {
    if (_isPreviewing) {
      await _previewPlayer.stop();
      setState(() => _isPreviewing = false);
      return;
    }
    if (_ringtoneUri.startsWith('/')) {
      await _previewPlayer.setVolume(_volume);
      await _previewPlayer.play(DeviceFileSource(_ringtoneUri));
      setState(() => _isPreviewing = true);
    }
  }

  String _ringtoneDisplayLabel(BuildContext context, String mainDefaultUri, String mainDefaultName) {
    if (_ringtoneUri == 'default' || _ringtoneUri.isEmpty) {
      return context.tr('System Default Ringtone', 'نغمة النظام الافتراضية');
    }
    final name = p.basename(_ringtoneUri);
    if (_ringtoneUri == mainDefaultUri) {
      final display = mainDefaultName.isNotEmpty ? mainDefaultName : name;
      return context.tr(
        'Main Ringtone: $display',
        'النغمة الرئيسية: $display',
      );
    }
    return context.tr(
      'Custom for this alarm: $name',
      'نغمة مخصصة لهذا المنبه: $name',
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final localDt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      _selectedTime.hour,
      _selectedTime.minute,
    );
    String tzId = 'UTC';
    try {
      tzId = await FlutterTimezone.getLocalTimezone();
    } catch (_) {}

    final nowUtc = DateTime.now().toUtc();
    final alarm = Alarm(
      id: widget.existing?.id ?? const Uuid().v4(),
      ownerId: widget.existing?.ownerId ?? ref.read(currentUserIdProvider),
      title: _titleCtrl.text.trim(),
      notes: _notesCtrl.text.trim(),
      startAtUtc: localDt.toUtc(),
      creatorTimezoneId: widget.existing?.creatorTimezoneId ?? tzId,
      repeatRule: RepeatRule(
        frequency: _repeatFreq,
        interval: _repeatFreq == RepeatFrequency.custom ? _customInterval : 1,
        customUnit: _customUnit,
        weekdays: _weekdays,
        dayOfMonth: _selectedDate.day,
        lastDayOfMonth: _lastDayOfMonth,
        nthWeekday: _nthWeekday,
        customPreset:
            _repeatFreq == RepeatFrequency.custom ? _customPreset : null,
      ),
      snoozeConfig: SnoozeConfig(
        snoozeDurationMinutes: _snoozeMinutes,
        maxSnoozeCount: _maxSnoozeCount,
        autoSnooze: _autoSnooze,
        ringDurationSeconds: _ringDurationSec,
      ),
      ringtoneUri: _ringtoneUri,
      volume: _volume,
      gradualVolume: _gradualVolume,
      vibrate: _vibrate,
      ringOnVibrateSilent: _ringOnVibrateSilent,
      type: _alarmType,
      state: AlarmState.upcoming,
      isEnabled: true,
      updatedAtUtc: nowUtc,
      participants:
          _alarmType == AlarmType.personal ? const [] : _participants,
    );

    await ref.read(alarmRepositoryProvider).saveAlarm(alarm);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addParticipantManually() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final added = await showDialog<AlarmParticipant>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _alarmType == AlarmType.buddy
              ? context.tr('Add Buddy', 'إضافة صديق')
              : context.tr('Add Group Member', 'إضافة عضو للمجموعة'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.tr('Name', 'الاسم'),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(
                labelText: context.tr('Phone (optional)', 'رقم الهاتف (اختياري)'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.tr('Cancel', 'إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              final phone = phoneCtrl.text.trim();
              Navigator.of(ctx).pop(
                AlarmParticipant(
                  uid: phone.isNotEmpty
                      ? 'phone_${phone.replaceAll(RegExp(r'\s+'), '')}'
                      : const Uuid().v4(),
                  displayName: phone.isNotEmpty ? '$name ($phone)' : name,
                  status: ParticipantStatus.pending,
                  updatedAtUtc: DateTime.now().toUtc(),
                ),
              );
            },
            child: Text(context.tr('Add', 'إضافة')),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();

    if (added != null && mounted) {
      setState(() {
        if (_alarmType == AlarmType.buddy) {
          _participants = [added];
        } else if (!_participants.any((p) => p.uid == added.uid)) {
          _participants.add(added);
        }
      });
    }
  }

  Future<void> _pickParticipantFromContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'Contacts permission is needed to pick from contacts.',
                  'مطلوب إذن جهات الاتصال للاختيار من الهاتف.',
                ),
              ),
            ),
          );
        }
        return;
      }
      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      final full = await FlutterContacts.getContact(contact.id) ?? contact;
      final phone = full.phones.isNotEmpty ? full.phones.first.number : '';
      final name = full.displayName.isNotEmpty
          ? full.displayName
          : (phone.isNotEmpty ? phone : context.tr('Contact', 'جهة اتصال'));
      final participant = AlarmParticipant(
        uid: phone.isNotEmpty
            ? 'phone_${phone.replaceAll(RegExp(r'\s+'), '')}'
            : 'contact_${full.id}',
        displayName: name,
        status: ParticipantStatus.pending,
        updatedAtUtc: DateTime.now().toUtc(),
      );
      if (mounted) {
        setState(() {
          if (_alarmType == AlarmType.buddy) {
            _participants = [participant];
          } else if (!_participants.any((p) => p.uid == participant.uid)) {
            _participants.add(participant);
          }
        });
      }
    } catch (_) {
      await _addParticipantManually();
    }
  }

  Future<void> _openCustomRepeatScreen() async {
    final currentRule = RepeatRule(
      frequency: RepeatFrequency.custom,
      interval: _customInterval,
      customUnit: _customUnit,
      weekdays: _weekdays,
      lastDayOfMonth: _lastDayOfMonth,
      nthWeekday: _nthWeekday,
      customPreset: _customPreset,
    );
    final picked = await Navigator.of(context).push<RepeatRule>(
      MaterialPageRoute(
        builder: (_) => CustomRepeatScreen(initialRule: currentRule),
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _repeatFreq = RepeatFrequency.custom;
        _customInterval = picked.interval;
        _customUnit = picked.customUnit;
        _weekdays = [...picked.weekdays];
        _lastDayOfMonth = picked.lastDayOfMonth;
        _nthWeekday = picked.nthWeekday;
        _customPreset = picked.customPreset;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final mainDefaultUri = ref.watch(defaultRingtoneUriProvider);
    final mainDefaultName = ref.watch(defaultRingtoneNameProvider);
    final savedBuddies = ref.watch(buddiesStreamProvider).valueOrNull ?? const <SavedBuddy>[];
    final savedGroups = ref.watch(groupsStreamProvider).valueOrNull ?? const <SavedGroup>[];
    final buddyMap = {for (final b in savedBuddies) b.id: b};

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? context.tr('New Alarm', 'منبه جديد')
              : context.tr('Edit Alarm', 'تعديل المنبه'),
        ),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref
                    .read(alarmRepositoryProvider)
                    .deleteAlarm(widget.existing!.id);
                if (mounted) Navigator.of(context).pop();
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 28 + bottomInset),
            children: [
              TextFormField(
                controller: _titleCtrl,
                decoration: InputDecoration(
                  labelText: context.tr('Alarm Title', 'عنوان المنبه'),
                  border: const OutlineInputBorder(),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.tr('Title is required', 'العنوان مطلوب')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.tr('Notes (optional)', 'ملاحظات (اختياري)'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.tr('Alarm For', 'المنبه لـ'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              SegmentedButton<AlarmType>(
                segments: [
                  ButtonSegment(
                    value: AlarmType.personal,
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(context.tr('Myself', 'لنفسي')),
                  ),
                  ButtonSegment(
                    value: AlarmType.buddy,
                    icon: const Icon(Icons.people_outline, size: 18),
                    label: Text(context.tr('Buddy', 'صديق')),
                  ),
                  ButtonSegment(
                    value: AlarmType.group,
                    icon: const Icon(Icons.groups_outlined, size: 18),
                    label: Text(context.tr('Group', 'مجموعة')),
                  ),
                ],
                selected: {_alarmType},
                onSelectionChanged: (sel) {
                  setState(() {
                    _alarmType = sel.first;
                    if (_alarmType == AlarmType.personal) {
                      _participants = [];
                      _selectedBuddyId = null;
                      _selectedGroupId = null;
                    } else if (_alarmType == AlarmType.buddy) {
                      _selectedGroupId = null;
                      if (_selectedBuddyId == null && savedBuddies.isNotEmpty) {
                        _selectedBuddyId = savedBuddies.first.id;
                        _participants = [savedBuddies.first.toAlarmParticipant()];
                      } else if (_selectedBuddyId != null && buddyMap[_selectedBuddyId] != null) {
                        _participants = [buddyMap[_selectedBuddyId]!.toAlarmParticipant()];
                      } else {
                        _participants = [];
                      }
                    } else if (_alarmType == AlarmType.group) {
                      _selectedBuddyId = null;
                      if (_selectedGroupId == null && savedGroups.isNotEmpty) {
                        final g = savedGroups.first;
                        _selectedGroupId = g.id;
                        _participants = g.memberIds
                            .map((id) => buddyMap[id]?.toAlarmParticipant())
                            .whereType<AlarmParticipant>()
                            .toList();
                      }
                    }
                  });
                },
              ),
              if (_alarmType == AlarmType.buddy) ...[
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.people_alt_rounded,
                              color: AppTheme.buddyPurple,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr('Choose a Saved Buddy', 'اختر صديقاً من المحفوظين'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ContactsGroupsTab(),
                                ),
                              ),
                              child: Text(context.tr('Manage', 'إدارة')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (savedBuddies.isEmpty)
                          Text(
                            context.tr(
                              'No saved buddies yet. Tap "Manage" to add buddies first.',
                              'لا يوجد أصدقاء محفوظون بعد. اضغط «إدارة» لإضافة أصدقاء أولاً.',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          ...savedBuddies.map(
                            (b) => RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: b.id,
                              groupValue: _selectedBuddyId,
                              title: Text(
                                b.name,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              subtitle: b.phone.isNotEmpty ? Text(b.phone) : null,
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _selectedBuddyId = val;
                                  _participants = [b.toAlarmParticipant()];
                                });
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_alarmType == AlarmType.group) ...[
                const SizedBox(height: 12),
                Card(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.groups_rounded,
                              color: AppTheme.groupTeal,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                context.tr('Choose a Saved Group', 'اختر مجموعة من المحفوظات'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const ContactsGroupsTab(),
                                ),
                              ),
                              child: Text(context.tr('Manage', 'إدارة')),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        if (savedGroups.isEmpty)
                          Text(
                            context.tr(
                              'No saved groups yet. Tap "Manage" to create a group first.',
                              'لا توجد مجموعات محفوظة بعد. اضغط «إدارة» لإنشاء مجموعة أولاً.',
                            ),
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          )
                        else
                          ...savedGroups.map((g) {
                            final members = g.memberIds
                                .map((id) => buddyMap[id]?.name)
                                .whereType<String>()
                                .toList();
                            return RadioListTile<String>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: g.id,
                              groupValue: _selectedGroupId,
                              title: Text(
                                g.name,
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                members.isNotEmpty
                                    ? '${members.length} • ${members.join('، ')}'
                                    : context.tr('No members', 'لا يوجد أعضاء'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onChanged: (val) {
                                if (val == null) return;
                                setState(() {
                                  _selectedGroupId = val;
                                  _participants = g.memberIds
                                      .map((id) => buddyMap[id]?.toAlarmParticipant())
                                      .whereType<AlarmParticipant>()
                                      .toList();
                                });
                              },
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate,
                          firstDate: DateTime(2024),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setState(() => _selectedDate = picked);
                        }
                      },
                      icon: const Icon(Icons.calendar_today),
                      label: Text(
                        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: _selectedTime,
                        );
                        if (picked != null) {
                          setState(() => _selectedTime = picked);
                        }
                      },
                      icon: const Icon(Icons.access_time),
                      label: Text(_selectedTime.format(context)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<RepeatFrequency>(
                value: _repeatFreq,
                decoration: InputDecoration(
                  labelText: context.tr('Repeat', 'التكرار'),
                  border: const OutlineInputBorder(),
                ),
                items: RepeatFrequency.values
                    .map(
                      (f) => DropdownMenuItem(
                        value: f,
                        child: Text(
                          context.trLabel(
                            f.name == 'none' ? 'NONE' : f.name.toUpperCase(),
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) async {
                  if (v == null) return;
                  setState(() => _repeatFreq = v);
                  if (v == RepeatFrequency.custom) {
                    await _openCustomRepeatScreen();
                  }
                },
              ),
              if (_repeatFreq == RepeatFrequency.custom) ...[
                const SizedBox(height: 8),
                Card(
                  child: ListTile(
                    leading: const Icon(
                      Icons.check_box,
                      color: Color(0xFF00C853),
                    ),
                    title: Text(
                      context.trLabel(
                        RepeatRule(
                          frequency: RepeatFrequency.custom,
                          interval: _customInterval,
                          customUnit: _customUnit,
                          weekdays: _weekdays,
                          lastDayOfMonth: _lastDayOfMonth,
                          nthWeekday: _nthWeekday,
                          customPreset: _customPreset,
                        ).displayLabel,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    trailing: TextButton(
                      onPressed: _openCustomRepeatScreen,
                      child: Text(context.tr('Change', 'تغيير')),
                    ),
                    onTap: _openCustomRepeatScreen,
                  ),
                ),
              ],
              if (_repeatFreq == RepeatFrequency.weekly) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: List.generate(7, (i) {
                    final day = i + 1;
                    final labels = context.isAr
                        ? ['إ', 'ث', 'ر', 'خ', 'ج', 'س', 'ح']
                        : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
                    final selected = _weekdays.contains(day);
                    return FilterChip(
                      label: Text(labels[i]),
                      selected: selected,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            _weekdays.add(day);
                          } else {
                            _weekdays.remove(day);
                          }
                        });
                      },
                    );
                  }),
                ),
              ],
              const Divider(height: 32),
              Text(
                context.tr('Snooze & Ringing', 'الغفوة والرنين'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              SwitchListTile(
                title: Text(
                  context.tr(
                    'Ring even on Vibrate / Silent',
                    'الرنين حتى في وضع الصامت والاهتزاز',
                  ),
                ),
                value: _ringOnVibrateSilent,
                onChanged: (v) => setState(() => _ringOnVibrateSilent = v),
              ),
              SwitchListTile(
                title: Text(
                  context.tr(
                    'Gradual volume increase',
                    'رفع الصوت تدريجياً',
                  ),
                ),
                value: _gradualVolume,
                onChanged: (v) => setState(() => _gradualVolume = v),
              ),
              SwitchListTile(
                title: Text(context.tr('Vibrate', 'اهتزاز')),
                value: _vibrate,
                onChanged: (v) => setState(() => _vibrate = v),
              ),
              SwitchListTile(
                title: Text(
                  context.tr(
                    'Auto-snooze after ring duration',
                    'غفوة تلقائية بعد انتهاء مدة الرنين',
                  ),
                ),
                value: _autoSnooze,
                onChanged: (v) => setState(() => _autoSnooze = v),
              ),
              ListTile(
                title: Text(
                  context.tr(
                    'Ring Duration: $_ringDurationSec sec (0 = continuous)',
                    'مدة الرنين: $_ringDurationSec ثانية (0 = مستمر)',
                  ),
                ),
                subtitle: Slider(
                  value: _ringDurationSec.toDouble(),
                  min: 0,
                  max: 60,
                  divisions: 12,
                  onChanged: (v) =>
                      setState(() => _ringDurationSec = v.round()),
                ),
              ),
              ListTile(
                title: Text(
                  '${context.tr('Volume', 'مستوى الصوت')}: ${(_volume * 100).round()}%',
                ),
                subtitle: Slider(
                  value: _volume,
                  min: 0.1,
                  max: 1.0,
                  onChanged: (v) => setState(() => _volume = v),
                ),
              ),
              Card(
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.music_note),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _ringtoneDisplayLabel(
                                context,
                                mainDefaultUri,
                                mainDefaultName,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                          if (_ringtoneUri.startsWith('/'))
                            IconButton.filledTonal(
                              onPressed: _togglePreview,
                              icon: Icon(
                                _isPreviewing ? Icons.stop : Icons.play_arrow,
                              ),
                              tooltip: context.tr('Preview', 'معاينة'),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickCustomAudio,
                            icon: const Icon(Icons.audio_file_outlined, size: 18),
                            label: Text(
                              context.tr(
                                'Choose Ringtone for this Alarm',
                                'اختيار نغمة خاصة لهذا المنبه',
                              ),
                            ),
                          ),
                          if (_ringtoneUri != mainDefaultUri)
                            TextButton.icon(
                              onPressed: () async {
                                if (_isPreviewing) {
                                  await _previewPlayer.stop();
                                }
                                setState(() {
                                  _isPreviewing = false;
                                  _ringtoneUri = mainDefaultUri;
                                });
                              },
                              icon: const Icon(Icons.restore, size: 18),
                              label: Text(
                                context.tr(
                                  'Use Main Default Ringtone',
                                  'استخدام النغمة الرئيسية الافتراضية',
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _save,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(context.tr('Save Alarm', 'حفظ المنبه')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
