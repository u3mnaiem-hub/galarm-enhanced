import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../data/platform/native_voice_channel.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/services/gemini_voice_parser.dart';
import '../../domain/services/voice_alarm_parser.dart';
import '../../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../screens/alarm_editor_screen.dart';

enum _VoicePhase {
  idle,
  listening,
  parsing,
  awaitingClarification,
  awaitingConfirmation,
  saved,
}

class VoiceAssistantSheet extends ConsumerStatefulWidget {
  const VoiceAssistantSheet({super.key});

  @override
  ConsumerState<VoiceAssistantSheet> createState() =>
      _VoiceAssistantSheetState();
}

class _VoiceAssistantSheetState extends ConsumerState<VoiceAssistantSheet>
    with SingleTickerProviderStateMixin {
  static const int _maxAutoRetries = 2;

  StreamSubscription<VoiceEvent>? _sub;
  late final AnimationController _pulseCtrl;

  _VoicePhase _phase = _VoicePhase.idle;
  String _language = 'ar-EG';

  // Live transcript accumulation across retries
  String _accumulatedText = '';
  String _currentPartial = '';
  int _retryCount = 0;
  bool _manualFinishRequested = false;
  bool _micPermissionDenied = false;

  // TTS -> auto-listen coordination
  bool _listenAfterTts = false;
  Timer? _ttsFallbackTimer;

  String _statusMessage =
      'اتكلم براحتك.. مثلاً: "فكرني بكره الساعة ٧ الصبح اخد الدوا"';

  // Pending structured draft
  String? _draftTitle;
  DateTime? _draftDateTime;
  RepeatRule _draftRepeat = const RepeatRule();
  AlarmType _draftType = AlarmType.personal;
  bool _waitingForPastTimeTomorrowConfirm = false;

  String get _fullLiveTranscript {
    final parts = [_accumulatedText.trim(), _currentPartial.trim()]
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.join(' ').trim();
  }

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    final voice = ref.read(nativeVoiceChannelProvider);
    _sub = voice.events.listen(_onVoiceEvent);
    _startListening(resetTranscript: true);
  }

  @override
  void dispose() {
    _ttsFallbackTimer?.cancel();
    _sub?.cancel();
    _pulseCtrl.dispose();
    final voice = ref.read(nativeVoiceChannelProvider);
    voice.cancelListening();
    voice.stopSpeaking();
    super.dispose();
  }

  Future<void> _speakAndMaybeListen(
    String text, {
    required bool listenAfter,
  }) async {
    final voice = ref.read(nativeVoiceChannelProvider);
    _ttsFallbackTimer?.cancel();
    _listenAfterTts = listenAfter;
    await voice.speak(text, language: _language);
    if (listenAfter) {
      // Fallback timer in case a device TTS engine doesn't fire onDone
      final estMs = (text.length * 75).clamp(2200, 6500);
      _ttsFallbackTimer = Timer(Duration(milliseconds: estMs), () {
        if (mounted && _listenAfterTts) {
          _listenAfterTts = false;
          _startListening(resetTranscript: true);
        }
      });
    }
  }

  Future<void> _startListening({bool resetTranscript = false}) async {
    final voice = ref.read(nativeVoiceChannelProvider);
    final hasPerm = await voice.hasRecordPermission();
    if (!hasPerm) {
      setState(() {
        _micPermissionDenied = true;
        _phase = _VoicePhase.idle;
        _statusMessage =
            'يرجى منح صلاحية الميكروفون عشان أقدر أسمعك.';
      });
      await voice.requestRecordPermission();
      return;
    }

    _ttsFallbackTimer?.cancel();
    _listenAfterTts = false;
    await voice.stopSpeaking();

    setState(() {
      _micPermissionDenied = false;
      _manualFinishRequested = false;
      if (resetTranscript) {
        _accumulatedText = '';
        _currentPartial = '';
        _retryCount = 0;
      }
      _phase = _VoicePhase.listening;
      if (_phase == _VoicePhase.listening && _draftTitle == null) {
        _statusMessage =
            _language == 'ar-EG' ? 'جاري الاستماع... اتكلم براحتك' : 'Listening...';
      }
    });

    await voice.startListening(language: _language);
  }

  Future<void> _finishSpeakingManually() async {
    final voice = ref.read(nativeVoiceChannelProvider);
    _manualFinishRequested = true;
    await voice.stopListening();

    // Give Android a brief window to deliver final onResults; if not, process what we have
    final snapshot = _fullLiveTranscript;
    await Future<void>.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;
    if (_phase == _VoicePhase.listening) {
      final textToProcess =
          _fullLiveTranscript.isNotEmpty ? _fullLiveTranscript : snapshot;
      if (textToProcess.isNotEmpty) {
        await _handleFinalTranscript(textToProcess);
      } else {
        setState(() {
          _phase = _VoicePhase.idle;
          _statusMessage = 'لم أسمع كلاماً بعد. اضغط الميكروفون وحاول مرة أخرى.';
        });
      }
    }
  }

  Future<void> _onVoiceEvent(VoiceEvent e) async {
    if (!mounted) return;

    if (e.type == 'tts_done') {
      _ttsFallbackTimer?.cancel();
      if (_listenAfterTts) {
        _listenAfterTts = false;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (mounted) await _startListening(resetTranscript: true);
      }
      return;
    }

    if (e.type == 'partial') {
      final partial = (e.text ?? '').trim();
      if (partial.isNotEmpty) {
        setState(() => _currentPartial = partial);
      }
      return;
    }

    if (e.type == 'result') {
      final chunk = (e.text ?? '').trim();
      if (chunk.isNotEmpty) {
        _accumulatedText = _accumulatedText.isEmpty
            ? chunk
            : '$_accumulatedText $chunk'.trim();
        _currentPartial = '';
      }
      final combined = _accumulatedText.trim();
      if (combined.isEmpty) {
        await _retryOrStop('لم أسمع كلاماً واضحاً، حاول مرة أخرى.');
      } else {
        await _handleFinalTranscript(combined);
      }
      return;
    }

    if (e.type == 'error') {
      if (e.isPermissionError) {
        setState(() {
          _micPermissionDenied = true;
          _phase = _VoicePhase.idle;
          _statusMessage =
              'مفيش صلاحية للميكروفون. اسمح بالصلاحية من الإعدادات وحاول تاني.';
        });
        return;
      }

      if (e.isNetworkError) {
        // Keep whatever partial text was captured, otherwise show clear Arabic error
        if (_fullLiveTranscript.isNotEmpty) {
          await _handleFinalTranscript(_fullLiveTranscript);
          return;
        }
        setState(() {
          _phase = _VoicePhase.idle;
          _statusMessage =
              'لا يوجد اتصال بالإنترنت للتعرف الصوتي. تأكد من الاتصال وحاول مرة أخرى.';
        });
        return;
      }

      // Preserve any partial text collected before timeout/no-match
      if (_currentPartial.trim().isNotEmpty) {
        _accumulatedText = _accumulatedText.isEmpty
            ? _currentPartial.trim()
            : '$_accumulatedText ${_currentPartial.trim()}'.trim();
        _currentPartial = '';
      }

      if (_manualFinishRequested) {
        final combined = _accumulatedText.trim();
        if (combined.isNotEmpty) {
          await _handleFinalTranscript(combined);
        } else {
          setState(() {
            _phase = _VoicePhase.idle;
            _statusMessage = 'لم أسمع كلاماً. اضغط الميكروفون للمحاولة مجدداً.';
          });
        }
        return;
      }

      if (e.isRecoverableSilenceError) {
        await _retryOrStop(
          e.message ?? 'لم أسمع كلاماً واضحاً، حاول مرة أخرى.',
        );
        return;
      }

      setState(() {
        _phase = _VoicePhase.idle;
        _statusMessage = e.message ?? 'حدث خطأ أثناء الاستماع، حاول مرة أخرى.';
      });
      return;
    }

    if (e.type == 'end') {
      // Wait briefly for onResults; if recognizer ended early with partial text and no result, handled by error/result
    }
  }

  Future<void> _retryOrStop(String fallbackError) async {
    if (_retryCount < _maxAutoRetries) {
      _retryCount++;
      setState(() {
        _phase = _VoicePhase.listening;
        _statusMessage = _accumulatedText.isNotEmpty
            ? 'بكمل الاستماع... (محاولة ${_retryCount + 1})'
            : 'لسه بسمعك... اتكلم براحتك (محاولة ${_retryCount + 1})';
      });
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        await ref.read(nativeVoiceChannelProvider).startListening(
              language: _language,
            );
      }
      return;
    }

    // Retries exhausted: if we already captured text, process it!
    final combined = _accumulatedText.trim();
    if (combined.isNotEmpty) {
      await _handleFinalTranscript(combined);
    } else {
      setState(() {
        _phase = _VoicePhase.idle;
        _statusMessage = fallbackError;
      });
    }
  }

  Future<void> _handleFinalTranscript(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // 1. If we are waiting for user confirmation ("أيوه / تمام / احفظ" | "لا / غيّر" | "خليها ٨")
    if (_draftDateTime != null &&
        (_phase == _VoicePhase.awaitingConfirmation ||
            (_phase == _VoicePhase.listening &&
                !_waitingForPastTimeTomorrowConfirm &&
                _draftTitle != null))) {
      final reply = VoiceAlarmParser.parseConfirmationReply(trimmed);
      if (reply.type == VoiceReplyType.confirm) {
        await _saveConfirmedAlarm();
        return;
      }
      if (reply.type == VoiceReplyType.edit) {
        _resetDraft();
        const msg = 'حاضر، قول المنبه من جديد أو اضغط تعديل.';
        setState(() {
          _phase = _VoicePhase.idle;
          _statusMessage = msg;
        });
        await _speakAndMaybeListen(msg, listenAfter: true);
        return;
      }
      if (reply.type == VoiceReplyType.modifyTime &&
          (reply.newTime != null || reply.newDate != null)) {
        final cur = _draftDateTime!;
        final newDate = reply.newDate ?? cur;
        final newHour = reply.newTime?.$1 ?? cur.hour;
        final newMin = reply.newTime?.$2 ?? cur.minute;
        _draftDateTime = DateTime(
          newDate.year,
          newDate.month,
          newDate.day,
          newHour,
          newMin,
        );
        await _presentConfirmation();
        return;
      }
    }

    // 2. If we asked whether to move a passed today-time to tomorrow
    if (_waitingForPastTimeTomorrowConfirm && _draftDateTime != null) {
      final reply = VoiceAlarmParser.parseConfirmationReply(trimmed);
      if (reply.type == VoiceReplyType.confirm) {
        _waitingForPastTimeTomorrowConfirm = false;
        _draftDateTime = _draftDateTime!.add(const Duration(days: 1));
        await _presentConfirmation();
        return;
      }
      if (reply.type == VoiceReplyType.modifyTime &&
          (reply.newTime != null || reply.newDate != null)) {
        _waitingForPastTimeTomorrowConfirm = false;
        final cur = _draftDateTime!;
        final newDate = reply.newDate ?? cur;
        final newHour = reply.newTime?.$1 ?? cur.hour;
        final newMin = reply.newTime?.$2 ?? cur.minute;
        _draftDateTime = DateTime(
          newDate.year,
          newDate.month,
          newDate.day,
          newHour,
          newMin,
        );
        await _presentConfirmation();
        return;
      }
      if (reply.type == VoiceReplyType.edit) {
        _waitingForPastTimeTomorrowConfirm = false;
        _resetDraft();
        const msg = 'تمام، تحب أظبطه امتى؟';
        setState(() {
          _phase = _VoicePhase.awaitingClarification;
          _statusMessage = msg;
        });
        await _speakAndMaybeListen(msg, listenAfter: true);
        return;
      }
    }

    // 3. Normal or clarification parsing (Gemini LLM first if configured, offline fallback always ready)
    setState(() {
      _phase = _VoicePhase.parsing;
      _statusMessage = 'جاري الفهم...';
    });

    final now = DateTime.now();
    var tzId = 'Africa/Cairo';
    try {
      tzId = await FlutterTimezone.getLocalTimezone();
    } catch (_) {}

    final apiKey = GeminiVoiceParser.resolveApiKey(
      ref.read(geminiApiKeyProvider),
    );

    // Check quick non-create commands (delete / disable / snooze / done) first when no draft is active
    final offlineIntent = VoiceAlarmParser.parse(trimmed, nowLocal: now);
    if (_draftTitle == null &&
        offlineIntent.action != VoiceIntentAction.createAlarm &&
        offlineIntent.action != VoiceIntentAction.unknown) {
      await _executeNonCreateAction(offlineIntent);
      return;
    }

    StructuredVoiceAlarmResult? structured;
    bool fellBackDueToNetwork = false;

    if (apiKey.isNotEmpty) {
      final contextSummary = _draftTitle != null
          ? 'Title so far: "$_draftTitle", DateTime so far: ${_draftDateTime?.toIso8601String() ?? "none"}'
          : null;
      final outcome = await GeminiVoiceParser.parseEgyptianArabic(
        transcript: trimmed,
        apiKey: apiKey,
        nowLocal: now,
        timezoneId: tzId,
        previousContextSummary: contextSummary,
      );
      structured = outcome.result;
      fellBackDueToNetwork = outcome.networkError;
    }

    // Fallback to our upgraded Egyptian Arabic offline parser
    structured ??= offlineIntent.structured;

    if (structured == null) {
      const msg = 'مفهمتش الأمر. جرب تقول: فكرني بكره الساعة ٧ الصبح اخد الدوا';
      setState(() {
        _phase = _VoicePhase.idle;
        _statusMessage = msg;
      });
      await _speakAndMaybeListen(msg, listenAfter: false);
      return;
    }

    // Merge with any pending draft (e.g., user first said "فكرني اشتري عيش", then answered "بكره الساعة ٨")
    if (structured.title.isNotEmpty &&
        structured.title != 'منبه صوتي' &&
        structured.title != 'Voice Alarm') {
      _draftTitle = structured.title;
    } else if (_draftTitle == null || _draftTitle!.isEmpty) {
      _draftTitle = structured.title.isNotEmpty ? structured.title : 'منبه صوتي';
    }

    if (structured.repeat != 'none') {
      _draftRepeat = structured.toRepeatRule(
        dayOfMonth: structured.parsedLocalDateTime?.day,
      );
    }
    if (offlineIntent.alarmType != AlarmType.personal) {
      _draftType = offlineIntent.alarmType;
    }

    final parsedDt = structured.parsedLocalDateTime;
    if (parsedDt != null) {
      _draftDateTime = parsedDt;
    }

    // Clarification needed? Ask ONE short question at a time.
    if (structured.needsClarification || _draftDateTime == null) {
      final isPastToday = _draftDateTime != null && !_draftDateTime!.isAfter(now);
      _waitingForPastTimeTomorrowConfirm = isPastToday;
      final question = structured.question?.trim().isNotEmpty == true
          ? structured.question!.trim()
          : 'تحب أفكرك امتى؟';
      setState(() {
        _phase = _VoicePhase.awaitingClarification;
        _statusMessage = fellBackDueToNetwork
            ? '$question\n(تم التحليل محلياً لعدم توفر الإنترنت)'
            : question;
      });
      await _speakAndMaybeListen(question, listenAfter: true);
      return;
    }

    // We have a complete draft! Either save directly (if skip confirmation is on) or read back for confirmation.
    final skipConfirm = ref.read(skipVoiceConfirmationProvider);
    if (skipConfirm) {
      await _saveConfirmedAlarm();
    } else {
      await _presentConfirmation(fellBackDueToNetwork: fellBackDueToNetwork);
    }
  }

  Future<void> _presentConfirmation({bool fellBackDueToNetwork = false}) async {
    final dt = _draftDateTime!;
    final title = _draftTitle ?? 'منبه صوتي';
    final confirmSpeech = VoiceAlarmParser.buildEgyptianConfirmationPrompt(
      title: title,
      localDt: dt,
      repeatRule: _draftRepeat,
    );

    setState(() {
      _phase = _VoicePhase.awaitingConfirmation;
      _statusMessage = fellBackDueToNetwork
          ? '$confirmSpeech\n(تم التحليل محلياً بدون إنترنت)'
          : confirmSpeech;
    });

    await _speakAndMaybeListen(confirmSpeech, listenAfter: true);
  }

  Future<void> _saveConfirmedAlarm() async {
    final dt = _draftDateTime;
    if (dt == null) return;

    var tzId = 'Africa/Cairo';
    try {
      tzId = await FlutterTimezone.getLocalTimezone();
    } catch (_) {}

    final alarm = Alarm(
      id: const Uuid().v4(),
      ownerId: ref.read(currentUserIdProvider),
      title: (_draftTitle?.trim().isNotEmpty == true)
          ? _draftTitle!.trim()
          : 'منبه صوتي',
      startAtUtc: dt.toUtc(),
      creatorTimezoneId: tzId,
      repeatRule: _draftRepeat,
      ringtoneUri: ref.read(defaultRingtoneUriProvider),
      type: _draftType,
      updatedAtUtc: DateTime.now().toUtc(),
    );

    await ref.read(alarmRepositoryProvider).saveAlarm(alarm);

    final timeStr = VoiceAlarmParser.formatTimeArabic(dt);
    final reply = 'تم حفظ المنبه: "${alarm.title}" الساعة $timeStr';

    _resetDraft();
    setState(() {
      _phase = _VoicePhase.saved;
      _statusMessage = reply;
    });
    await _speakAndMaybeListen(reply, listenAfter: false);
  }

  Future<void> _openInEditor() async {
    final dt = _draftDateTime ?? DateTime.now().add(const Duration(minutes: 10));
    var tzId = 'Africa/Cairo';
    try {
      tzId = await FlutterTimezone.getLocalTimezone();
    } catch (_) {}

    final draftAlarm = Alarm(
      id: const Uuid().v4(),
      ownerId: ref.read(currentUserIdProvider),
      title: _draftTitle ?? '',
      startAtUtc: dt.toUtc(),
      creatorTimezoneId: tzId,
      repeatRule: _draftRepeat,
      ringtoneUri: ref.read(defaultRingtoneUriProvider),
      type: _draftType,
      updatedAtUtc: DateTime.now().toUtc(),
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AlarmEditorScreen(existing: draftAlarm),
      ),
    );
  }

  Future<void> _executeNonCreateAction(VoiceAlarmIntent intent) async {
    final repo = ref.read(alarmRepositoryProvider);
    final alarms = ref.read(alarmsStreamProvider).valueOrNull ?? const [];

    switch (intent.action) {
      case VoiceIntentAction.enableAlarm:
      case VoiceIntentAction.disableAlarm:
      case VoiceIntentAction.deleteAlarm:
        final query = (intent.title ?? '').toLowerCase();
        final match = alarms
            .where((a) => query.isEmpty || a.title.toLowerCase().contains(query))
            .firstOrNull;
        if (match == null) {
          const reply = 'لم أجد منبه بهذا الاسم.';
          setState(() {
            _phase = _VoicePhase.idle;
            _statusMessage = reply;
          });
          await _speakAndMaybeListen(reply, listenAfter: false);
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
        setState(() {
          _phase = _VoicePhase.saved;
          _statusMessage = reply;
        });
        await _speakAndMaybeListen(reply, listenAfter: false);
        break;

      case VoiceIntentAction.snoozeAlarm:
        final active = alarms.where((a) => a.isEnabled).firstOrNull;
        if (active != null) {
          await repo.snoozeAlarm(active);
          final reply = 'تم تأجيل المنبه ${intent.snoozeMinutes ?? 5} دقائق';
          setState(() {
            _phase = _VoicePhase.saved;
            _statusMessage = reply;
          });
          await _speakAndMaybeListen(reply, listenAfter: false);
        }
        break;

      case VoiceIntentAction.markDone:
        final active = alarms.where((a) => a.isEnabled).firstOrNull;
        if (active != null) {
          await repo.markOccurrenceDone(active);
          const reply = 'تم تحديد المنبه كمكتمل';
          setState(() {
            _phase = _VoicePhase.saved;
            _statusMessage = reply;
          });
          await _speakAndMaybeListen(reply, listenAfter: false);
        }
        break;

      default:
        break;
    }
  }

  void _resetDraft() {
    _draftTitle = null;
    _draftDateTime = null;
    _draftRepeat = const RepeatRule();
    _draftType = AlarmType.personal;
    _waitingForPastTimeTomorrowConfirm = false;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewPadding.bottom;
    final cs = Theme.of(context).colorScheme;
    final isListening = _phase == _VoicePhase.listening;
    final liveText = _fullLiveTranscript;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 14, 20, 22 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (isListening)
                      FadeTransition(
                        opacity: _pulseCtrl,
                        child: Container(
                          width: 10,
                          height: 10,
                          margin: const EdgeInsetsDirectional.only(end: 8),
                          decoration: const BoxDecoration(
                            color: Color(0xFFDC2626),
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    Text(
                      context.tr('Voice Assistant', 'المساعد الصوتي'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ],
                ),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'ar-EG', label: Text('مصري')),
                    ButtonSegment(value: 'en-US', label: Text('EN')),
                  ],
                  selected: {_language},
                  onSelectionChanged: (s) => setState(() => _language = s.first),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Live transcript box
            if (liveText.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(0.35),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.primary.withOpacity(0.35)),
                ),
                child: Text(
                  '"$liveText"',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),

            const SizedBox(height: 10),

            // Parsed preview card during confirmation
            if (_phase == _VoicePhase.awaitingConfirmation &&
                _draftDateTime != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: cs.primary.withOpacity(0.45)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.16),
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.alarm_rounded, color: cs.primary, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _draftTitle ?? 'منبه صوتي',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${DateFormat('EEE, d MMM yyyy', 'ar').format(_draftDateTime!)} • ${VoiceAlarmParser.formatTimeArabic(_draftDateTime!)}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                    if (_draftRepeat.isRecurring) ...[
                      const SizedBox(height: 4),
                      Text(
                        context.trLabel(_draftRepeat.displayLabel),
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: [
                        FilledButton.icon(
                          onPressed: _saveConfirmedAlarm,
                          icon: const Icon(Icons.check, size: 18),
                          label: Text(context.tr('Save', 'حفظ')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openInEditor,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(context.tr('Edit', 'تعديل')),
                        ),
                        TextButton(
                          onPressed: () {
                            _resetDraft();
                            setState(() {
                              _phase = _VoicePhase.idle;
                              _statusMessage = 'تم الإلغاء. اضغط الميكروفون للبدء من جديد.';
                            });
                          },
                          child: Text(context.tr('Cancel', 'إلغاء')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],

            // Status / prompt message
            if (_phase == _VoicePhase.parsing)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: CircularProgressIndicator(),
              )
            else
              Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),

            const SizedBox(height: 16),

            // Mic permission button if denied
            if (_micPermissionDenied)
              FilledButton.icon(
                onPressed: () => _startListening(resetTranscript: true),
                icon: const Icon(Icons.mic),
                label: Text(
                  context.tr('Grant Mic Permission', 'منح صلاحية الميكروفون'),
                ),
              )
            else
              // Controls: Mic + Manual "Done / تم" button while listening
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isListening) ...[
                    FilledButton.icon(
                      onPressed: _finishSpeakingManually,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(context.tr('Done', 'تم')),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF059669),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 14),
                  ],
                  FloatingActionButton(
                    backgroundColor:
                        isListening ? const Color(0xFFDC2626) : cs.primary,
                    foregroundColor: Colors.white,
                    onPressed: isListening
                        ? () async {
                            await ref
                                .read(nativeVoiceChannelProvider)
                                .cancelListening();
                            if (mounted) {
                              setState(() {
                                _phase = _VoicePhase.idle;
                                _statusMessage = 'تم إيقاف الاستماع.';
                              });
                            }
                          }
                        : () => _startListening(resetTranscript: true),
                    child: Icon(isListening ? Icons.stop : Icons.mic),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
