import '../../l10n/tr.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';
import 'custom_repeat_screen.dart';

class AlarmEditorScreen extends ConsumerStatefulWidget {
  final Alarm? existing;
  const AlarmEditorScreen({super.key, this.existing});

  @override
  ConsumerState<AlarmEditorScreen> createState() => _AlarmEditorScreenState();
}

class _AlarmEditorScreenState extends ConsumerState<AlarmEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _notesCtrl;

  late DateTime _selectedDate;
  late TimeOfDay _selectedTime;
  late AlarmType _alarmType;
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

  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPreviewing = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final initialLocal = (e?.startAtUtc ?? DateTime.now().add(const Duration(minutes: 5))).toLocal();

    _titleCtrl = TextEditingController(text: e?.title ?? '');
    _notesCtrl = TextEditingController(text: e?.notes ?? '');
    _selectedDate = DateTime(initialLocal.year, initialLocal.month, initialLocal.day);
    _selectedTime = TimeOfDay(hour: initialLocal.hour, minute: initialLocal.minute);
    _alarmType = e?.type ?? AlarmType.personal;
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

    _ringtoneUri = e?.ringtoneUri ?? 'default';
    _volume = e?.volume ?? 0.85;
    _gradualVolume = e?.gradualVolume ?? true;
    _vibrate = e?.vibrate ?? true;
    _ringOnVibrateSilent = e?.ringOnVibrateSilent ?? true;
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
      setState(() => _ringtoneUri = result.files.single.path!);
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
        interval: _customInterval,
        customUnit: _customUnit,
        weekdays: _weekdays,
        dayOfMonth: _selectedDate.day,
        lastDayOfMonth: _lastDayOfMonth,
        nthWeekday: _nthWeekday,
        customPreset: _repeatFreq == RepeatFrequency.custom ? _customPreset : null,
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
      participants: widget.existing?.participants ?? const [],
    );

    await ref.read(alarmRepositoryProvider).saveAlarm(alarm);
    if (mounted) Navigator.of(context).pop();
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? context.tr('New Alarm', 'منبه جديد') : context.tr('Edit Alarm', 'تعديل المنبه')),
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
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? context.tr('Title is required', 'العنوان مطلوب') : null,
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
            SegmentedButton<AlarmType>(
              segments: [
                ButtonSegment(value: AlarmType.personal, label: Text(context.tr('Personal', 'شخصي'))),
                ButtonSegment(value: AlarmType.group, label: Text(context.tr('Group', 'جماعي'))),
                ButtonSegment(value: AlarmType.buddy, label: Text(context.tr('Buddy', 'صديق'))),
              ],
              selected: {_alarmType},
              onSelectionChanged: (s) => setState(() => _alarmType = s.first),
            ),
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
                      if (picked != null) setState(() => _selectedDate = picked);
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
                      if (picked != null) setState(() => _selectedTime = picked);
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
                  .map((f) => DropdownMenuItem(value: f, child: Text(context.trLabel(f.name == 'none' ? 'NONE' : f.name.toUpperCase()))))
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
                  leading: const Icon(Icons.check_box, color: Color(0xFF00C853)),
                  title: Text(
                    context.trLabel(RepeatRule(
                      frequency: RepeatFrequency.custom,
                      interval: _customInterval,
                      customUnit: _customUnit,
                      weekdays: _weekdays,
                      lastDayOfMonth: _lastDayOfMonth,
                      nthWeekday: _nthWeekday,
                      customPreset: _customPreset,
                    ).displayLabel),
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
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
                  final labels = context.isAr ? ['إ', 'ث', 'ر', 'خ', 'ج', 'س', 'ح'] : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
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
            Text(context.tr('Snooze & Ringing', 'الغفوة والرنين'), style: Theme.of(context).textTheme.titleMedium),
            SwitchListTile(
              title: Text(context.tr('Ring even on Vibrate / Silent', 'الرنين حتى في وضع الصامت والاهتزاز')),
              value: _ringOnVibrateSilent,
              onChanged: (v) => setState(() => _ringOnVibrateSilent = v),
            ),
            SwitchListTile(
              title: Text(context.tr('Gradual volume increase', 'رفع الصوت تدريجياً')),
              value: _gradualVolume,
              onChanged: (v) => setState(() => _gradualVolume = v),
            ),
            SwitchListTile(
              title: Text(context.tr('Vibrate', 'اهتزاز')),
              value: _vibrate,
              onChanged: (v) => setState(() => _vibrate = v),
            ),
            SwitchListTile(
              title: Text(context.tr('Auto-snooze after ring duration', 'غفوة تلقائية بعد انتهاء مدة الرنين')),
              value: _autoSnooze,
              onChanged: (v) => setState(() => _autoSnooze = v),
            ),
            ListTile(
              title: Text(context.tr('Ring Duration: $_ringDurationSec sec (0 = continuous)', 'مدة الرنين: $_ringDurationSec ثانية (0 = مستمر)')),
              subtitle: Slider(
                value: _ringDurationSec.toDouble(),
                min: 0,
                max: 60,
                divisions: 12,
                onChanged: (v) => setState(() => _ringDurationSec = v.round()),
              ),
            ),
            ListTile(
              title: Text('${context.tr('Volume', 'مستوى الصوت')}: ${(_volume * 100).round()}%'),
              subtitle: Slider(
                value: _volume,
                min: 0.1,
                max: 1.0,
                onChanged: (v) => setState(() => _volume = v),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickCustomAudio,
                    icon: const Icon(Icons.music_note),
                    label: Text(
                      _ringtoneUri == 'default'
                          ? context.tr('Default Ringtone', 'النغمة الافتراضية')
                          : context.tr('Custom Audio Selected', 'تم اختيار صوت مخصص'),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: _togglePreview,
                  icon: Icon(_isPreviewing ? Icons.stop : Icons.play_arrow),
                ),
              ],
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
