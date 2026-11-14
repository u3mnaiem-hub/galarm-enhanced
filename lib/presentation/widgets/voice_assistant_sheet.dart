import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../data/platform/native_voice_channel.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/services/voice_alarm_parser.dart';
import '../providers/app_providers.dart';

class VoiceAssistantSheet extends ConsumerStatefulWidget {
  const VoiceAssistantSheet({super.key});

  @override
  ConsumerState<VoiceAssistantSheet> createState() =>
      _VoiceAssistantSheetState();
}

class _VoiceAssistantSheetState extends ConsumerState<VoiceAssistantSheet> {
  StreamSubscription<VoiceEvent>? _sub;
  bool _listening = false;
  String _transcript = '';
  String _statusMessage =
      'قول اسم المنبه واليوم والساعة (مثلاً: منبه الدواء اليوم الساعة 10:30 مساءً)';
  String _language = 'ar-EG';

  // Pending draft state so the voice assistant waits until BOTH date and time are answered
  String? _pendingTitle;
  DateTime? _pendingDate;
  bool _pendingIsToday = false;
  (int, int)? _pendingTime;
  RepeatFrequency _pendingRepeat = RepeatFrequency.none;
  AlarmType _pendingType = AlarmType.personal;

  @override
  void initState() {
    super.initState();
    final voice = ref.read(nativeVoiceChannelProvider);
    _sub = voice.events.listen(_onVoiceEvent);
    _startListening();
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _startListening() async {
    final voice = ref.read(nativeVoiceChannelProvider);
    final hasPerm = await voice.hasRecordPermission();
    if (!hasPerm) {
      await voice.requestRecordPermission();
      return;
    }
    setState(() {
      _listening = true;
      _transcript = '';
      _statusMessage = _language == 'ar-EG' ? 'جاري الاستماع...' : 'Listening...';
    });
    await voice.startListening(language: _language);
  }

  Future<void> _onVoiceEvent(VoiceEvent e) async {
    if (!mounted) return;
    if (e.type == 'partial') {
      setState(() => _transcript = e.text ?? '');
    } else if (e.type == 'result') {
      final text = e.text ?? '';
      setState(() {
        _listening = false;
        _transcript = text;
      });
      await _executeCommand(text);
    } else if (e.type == 'error') {
      setState(() {
        _listening = false;
        _statusMessage = e.message ?? 'لم يتم التقاط الصوت، حاول مرة أخرى.';
      });
    } else if (e.type == 'end') {
      setState(() => _listening = false);
    }
  }

  Future<void> _executeCommand(String text) async {
    final intent = VoiceAlarmParser.parse(text);
    final repo = ref.read(alarmRepositoryProvider);
    final voice = ref.read(nativeVoiceChannelProvider);
    final alarms = ref.read(alarmsStreamProvider).valueOrNull ?? const [];

    switch (intent.action) {
      case VoiceIntentAction.createAlarm:
        if (intent.title != null &&
            intent.title!.isNotEmpty &&
            intent.title != 'Voice Alarm') {
          _pendingTitle = intent.title;
        }
        if (intent.explicitDate != null) {
          _pendingDate = intent.explicitDate;
          _pendingIsToday = intent.isExplicitToday;
        }
        if (intent.explicitTime != null) {
          _pendingTime = intent.explicitTime;
        }
        if (intent.repeatFrequency != RepeatFrequency.none) {
          _pendingRepeat = intent.repeatFrequency;
        }
        if (intent.alarmType != AlarmType.personal) {
          _pendingType = intent.alarmType;
        }

        // Wait for complete date AND time from the user before creating the alarm
        if (_pendingDate == null && _pendingTime == null) {
          final prompt = _language == 'ar-EG'
              ? 'تمام، إمتى موعد المنبه باليوم والساعة؟ (مثلاً: اليوم الساعة 9 مساءً أو بكرة الساعة 7 الصبح)'
              : 'Got it. What day and time should the alarm ring?';
          setState(() => _statusMessage = prompt);
          await voice.speak(prompt, language: _language);
          await Future<void>.delayed(const Duration(milliseconds: 2200));
          if (mounted) await _startListening();
          return;
        }
        if (_pendingDate == null) {
          final prompt = _language == 'ar-EG'
              ? 'أي يوم تحب يرن المنبه؟ (قول: اليوم، أو بكرة، أو اسم اليوم)'
              : 'Which day should the alarm be set for? (e.g., today or tomorrow)';
          setState(() => _statusMessage = prompt);
          await voice.speak(prompt, language: _language);
          await Future<void>.delayed(const Duration(milliseconds: 2000));
          if (mounted) await _startListening();
          return;
        }
        if (_pendingTime == null) {
          final prompt = _language == 'ar-EG'
              ? 'الساعة كام تحب يرن المنبه؟ (متاح لحد 11:59 مساءً لو اليوم)'
              : 'What time should the alarm ring?';
          setState(() => _statusMessage = prompt);
          await voice.speak(prompt, language: _language);
          await Future<void>.delayed(const Duration(milliseconds: 2000));
          if (mounted) await _startListening();
          return;
        }

        final now = DateTime.now();
        final date = _pendingDate!;
        var hour = _pendingTime!.$1;
        final minute = _pendingTime!.$2;

        // If the alarm is for today ("اليوم"), allow setting any time today up to 11:59 PM (23:59)
        if (_pendingIsToday ||
            (date.year == now.year && date.month == now.month && date.day == now.day)) {
          final candidate = DateTime(date.year, date.month, date.day, hour, minute);
          if (candidate.isBefore(now) && hour < 12) {
            final pmCandidate = DateTime(date.year, date.month, date.day, hour + 12, minute);
            if (!pmCandidate.isBefore(now) || _pendingIsToday) {
              hour += 12;
            }
          }
        }

        final localDt = DateTime(date.year, date.month, date.day, hour, minute);
        var tzId = 'UTC';
        try {
          tzId = await FlutterTimezone.getLocalTimezone();
        } catch (_) {}

        final alarm = Alarm(
          id: const Uuid().v4(),
          ownerId: ref.read(currentUserIdProvider),
          title: _pendingTitle ?? 'Voice Alarm',
          startAtUtc: localDt.toUtc(),
          creatorTimezoneId: tzId,
          repeatRule: RepeatRule(frequency: _pendingRepeat),
          type: _pendingType,
          updatedAtUtc: DateTime.now().toUtc(),
        );
        await repo.saveAlarm(alarm);

        final dateStr = DateFormat('yyyy-MM-dd').format(localDt);
        final timeStr = DateFormat('hh:mm a').format(localDt);
        final reply = _language == 'ar-EG'
            ? 'تم ضبط منبه "${alarm.title}" يوم $dateStr الساعة $timeStr'
            : 'Alarm "${alarm.title}" set for $dateStr at $timeStr';

        // Reset pending draft
        _pendingTitle = null;
        _pendingDate = null;
        _pendingIsToday = false;
        _pendingTime = null;
        _pendingRepeat = RepeatFrequency.none;
        _pendingType = AlarmType.personal;

        setState(() => _statusMessage = reply);
        await voice.speak(reply, language: _language);
        break;

      case VoiceIntentAction.enableAlarm:
      case VoiceIntentAction.disableAlarm:
      case VoiceIntentAction.deleteAlarm:
        final query = (intent.title ?? '').toLowerCase();
        final match = alarms.where((a) =>
            query.isEmpty || a.title.toLowerCase().contains(query)).firstOrNull;
        if (match == null) {
          final reply = 'لم أجد منبه بهذا الاسم.';
          setState(() => _statusMessage = reply);
          await voice.speak(reply, language: _language);
          return;
        }
        if (intent.action == VoiceIntentAction.deleteAlarm) {
          await repo.deleteAlarm(match.id);
        } else {
          final shouldEnable = intent.action == VoiceIntentAction.enableAlarm;
          await repo.saveAlarm(match.copyWith(isEnabled: shouldEnable));
        }
        final reply = switch (intent.action) {
          VoiceIntentAction.deleteAlarm => 'تم حذف منبه ${match.title}',
          VoiceIntentAction.enableAlarm => 'تم تشغيل منبه ${match.title}',
          _ => 'تم إيقاف منبه ${match.title}',
        };
        setState(() => _statusMessage = reply);
        await voice.speak(reply, language: _language);
        break;

      case VoiceIntentAction.snoozeAlarm:
        final active = alarms.where((a) => a.isEnabled).firstOrNull;
        if (active != null) {
          await repo.snoozeAlarm(active);
          final reply = 'تم تأجيل المنبه ${intent.snoozeMinutes ?? 5} دقائق';
          setState(() => _statusMessage = reply);
          await voice.speak(reply, language: _language);
        }
        break;

      case VoiceIntentAction.markDone:
        final active = alarms.where((a) => a.isEnabled).firstOrNull;
        if (active != null) {
          await repo.markOccurrenceDone(active);
          const reply = 'تم تحديد المنبه كمكتمل';
          setState(() => _statusMessage = reply);
          await voice.speak(reply, language: _language);
        }
        break;

      case VoiceIntentAction.unknown:
        const reply = 'لم أفهم الأمر. جرب: صحيني بكرة الساعة 7 الصبح';
        setState(() => _statusMessage = reply);
        await voice.speak(reply, language: _language);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('المساعد الصوتي',
                    style: Theme.of(context).textTheme.titleLarge),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ar-EG', label: Text('عربي')),
                    ButtonSegment(value: 'en-US', label: Text('EN')),
                  ],
                  selected: {_language},
                  onSelectionChanged: (s) => setState(() => _language = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_transcript.isNotEmpty)
              Text(
                '"$_transcript"',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            const SizedBox(height: 6),
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            FloatingActionButton(
              onPressed: _listening
                  ? () => ref.read(nativeVoiceChannelProvider).stopListening()
                  : _startListening,
              child: Icon(_listening ? Icons.stop : Icons.mic),
            ),
          ],
        ),
      ),
    );
  }
}
