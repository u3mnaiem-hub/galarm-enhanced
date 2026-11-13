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
  String _statusMessage = 'اضغط الميكروفون وقول أمرك (مثلاً: صحيني بكرة الساعة 7 ونص الصبح)';
  String _language = 'ar-EG';

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
        final localDt = intent.localDateTime ?? DateTime.now().add(const Duration(hours: 1));
        var tzId = 'UTC';
        try {
          tzId = await FlutterTimezone.getLocalTimezone();
        } catch (_) {}

        final alarm = Alarm(
          id: const Uuid().v4(),
          ownerId: ref.read(currentUserIdProvider),
          title: intent.title ?? 'Voice Alarm',
          startAtUtc: localDt.toUtc(),
          creatorTimezoneId: tzId,
          repeatRule: RepeatRule(frequency: intent.repeatFrequency),
          type: intent.alarmType,
          updatedAtUtc: DateTime.now().toUtc(),
        );
        await repo.saveAlarm(alarm);

        final timeStr = DateFormat('hh:mm a').format(localDt);
        final reply = _language == 'ar-EG'
            ? 'تم ضبط منبه "${alarm.title}" الساعة $timeStr'
            : 'Alarm "${alarm.title}" set for $timeStr';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
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
          const SizedBox(height: 16),
          if (_transcript.isNotEmpty)
            Text(
              '"$_transcript"',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          const SizedBox(height: 8),
          Text(
            _statusMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          FloatingActionButton.large(
            onPressed: _listening
                ? () => ref.read(nativeVoiceChannelProvider).stopListening()
                : _startListening,
            child: Icon(_listening ? Icons.stop : Icons.mic),
          ),
        ],
      ),
    );
  }
}
