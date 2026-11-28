import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import '../../data/platform/native_voice_channel.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/services/voice_alarm_parser.dart';
import '../../domain/services/voice_engine_selector.dart';
import '../../l10n/tr.dart';
import '../providers/app_providers.dart';
import '../screens/alarm_editor_screen.dart';

enum _VoicePhase {
  idle,
  listening,
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
  final TextEditingController _textFallbackCtrl = TextEditingController();

  _VoicePhase _phase = _VoicePhase.idle;
  String _language = 'ar-EG';

  // Engine state
  VoiceEngineChoice _activeEngine = VoiceEngineChoice.onlineAndroid;
  OfflineVoiceStatus _offlineStatus = const OfflineVoiceStatus();
  String? _engineNotice;
  bool _showTextFallback = false;

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
  bool _isSavingOrSaved = false;

  String get _fullLiveTranscript {
    final parts = [_accumulatedText.trim(), _currentPartial.trim()]
        .where((s) => s.isNotEmpty)
        .toList();
    return parts.join(' ').trim();
  }

  String _engineCode(VoiceEngineChoice choice) {
    switch (choice) {
      case VoiceEngineChoice.onDeviceAndroid:
        return 'on_device';
      case VoiceEngineChoice.voskOffline:
        return 'vosk';
      case VoiceEngineChoice.onlineAndroid:
      case VoiceEngineChoice.textFallback:
        return 'online';
    }
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
    _textFallbackCtrl.dispose();
    final voice = ref.read(nativeVoiceChannelProvider);
    voice.cancelListening();
    if (!_isSavingOrSaved) {
      voice.stopSpeaking();
    }
    super.dispose();
  }

  Future<bool> _checkHasInternet() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  Future<void> _speakAndMaybeListen(
    String text, {
    required bool listenAfter,
  }) async {
    final voice = ref.read(nativeVoiceChannelProvider);
    _ttsFallbackTimer?.cancel();
    final shouldListen =
        listenAfter && _activeEngine != VoiceEngineChoice.textFallback;
    _listenAfterTts = shouldListen;
    await voice.speak(text, language: _language);
    if (shouldListen) {
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
      await voice.requestRecordPermission();
      final recheck = await voice.hasRecordPermission();
      if (!recheck && mounted) {
        setState(() {
          _micPermissionDenied = true;
          _activeEngine = VoiceEngineChoice.textFallback;
          _showTextFallback = true;
          _phase = _VoicePhase.idle;
          _statusMessage =
              'صلاحية الميكروفون غير مفعلة. يمكنك منح الصلاحية أو كتابة المنبه مباشرة بالأسفل.';
        });
        return;
      }
    }

    final offlineModeOn = ref.read(offlineVoiceModeProvider);
    final hasInternet = await _checkHasInternet();
    final status = await voice.getOfflineStatus(language: _language);
    _offlineStatus = status;

    final selection = VoiceEngineSelector.select(
      offlineModeEnabled: offlineModeOn,
      hasInternet: hasInternet,
      hasMicPermission: true,
      isOnlineRecognizerAvailable: status.onlineAvailable,
      isOnDeviceAndroidReady: status.isOnDeviceReady,
      isVoskModelInstalled: status.voskInstalled,
    );

    if (!mounted) return;

    _activeEngine = selection.engine;
    _engineNotice = selection.arabicNotice;

    if (selection.engine == VoiceEngineChoice.textFallback) {
      setState(() {
        _micPermissionDenied = false;
        _showTextFallback = true;
        _phase = _VoicePhase.idle;
        _statusMessage = selection.arabicNotice ??
            'التعرف الصوتي غير متاح حالياً. اكتب المنبه بالأسفل.';
      });
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
      if (_draftTitle == null) {
        _statusMessage = _language == 'ar-EG'
            ? 'جاري الاستماع... اتكلم براحتك'
            : 'Listening...';
      }
    });

    await voice.startListening(
      language: _language,
      engine: _engineCode(_activeEngine),
    );
  }

  Future<void> _finishSpeakingManually() async {
    final voice = ref.read(nativeVoiceChannelProvider);
    _manualFinishRequested = true;
    await voice.stopListening();

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
          _statusMessage = 'لم أسمع كلاماً بعد. اضغط الميكروفون أو اكتب المنبه.';
        });
      }
    }
  }

  Future<bool> _tryFallbackOfflineEngineOnError() async {
    if (_activeEngine == VoiceEngineChoice.onlineAndroid) {
      if (_offlineStatus.isOnDeviceReady) {
        _activeEngine = VoiceEngineChoice.onDeviceAndroid;
        _engineNotice = 'تم التبديل تلقائياً إلى محرك أندرويد الأوفلاين';
        await ref.read(nativeVoiceChannelProvider).startListening(
              language: _language,
              engine: 'on_device',
            );
        return true;
      }
      if (_offlineStatus.voskInstalled) {
        _activeEngine = VoiceEngineChoice.voskOffline;
        _engineNotice = 'تم التبديل تلقائياً إلى نموذج Vosk الأوفلاين';
        await ref.read(nativeVoiceChannelProvider).startListening(
              language: _language,
              engine: 'vosk',
            );
        return true;
      }
    } else if (_activeEngine == VoiceEngineChoice.onDeviceAndroid &&
        _offlineStatus.voskInstalled) {
      _activeEngine = VoiceEngineChoice.voskOffline;
      _engineNotice = 'تم التبديل تلقائياً إلى نموذج Vosk الأوفلاين';
      await ref.read(nativeVoiceChannelProvider).startListening(
            language: _language,
            engine: 'vosk',
          );
      return true;
    }
    return false;
  }

  Future<void> _onVoiceEvent(VoiceEvent e) async {
    if (!mounted || _isSavingOrSaved) return;

    if (e.type == 'tts_done') {
      _ttsFallbackTimer?.cancel();
      if (_listenAfterTts) {
        _listenAfterTts = false;
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (mounted) await _startListening(resetTranscript: true);
      }
      return;
    }

    if (e.type == 'vosk_progress' || e.type == 'on_device_progress') {
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
          _showTextFallback = true;
          _phase = _VoicePhase.idle;
          _statusMessage =
              'مفيش صلاحية للميكروفون. اسمح بالصلاحية أو اكتب المنبه مباشرة بالأسفل.';
        });
        return;
      }

      // Preserve any partial text collected before an error
      if (_currentPartial.trim().isNotEmpty) {
        _accumulatedText = _accumulatedText.isEmpty
            ? _currentPartial.trim()
            : '$_accumulatedText ${_currentPartial.trim()}'.trim();
        _currentPartial = '';
      }

      if (e.isNetworkError || e.isLanguagePackError) {
        if (_accumulatedText.trim().isNotEmpty) {
          await _handleFinalTranscript(_accumulatedText.trim());
          return;
        }
        final switched = await _tryFallbackOfflineEngineOnError();
        if (switched) {
          setState(() {
            _phase = _VoicePhase.listening;
            _statusMessage = _engineNotice ?? 'جاري الاستماع أوفلاين...';
          });
          return;
        }
        setState(() {
          _showTextFallback = true;
          _phase = _VoicePhase.idle;
          _statusMessage =
              '${e.message ?? "تعذر التعرف الصوتي."}\nيمكنك كتابة المنبه مباشرة بالأسفل.';
        });
        return;
      }

      if (_manualFinishRequested) {
        final combined = _accumulatedText.trim();
        if (combined.isNotEmpty) {
          await _handleFinalTranscript(combined);
        } else {
          setState(() {
            _phase = _VoicePhase.idle;
            _statusMessage = 'لم أسمع كلاماً. اضغط الميكروفون أو اكتب المنبه.';
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
        _showTextFallback = true;
        _phase = _VoicePhase.idle;
        _statusMessage = e.message ?? 'حدث خطأ أثناء الاستماع، يمكنك كتابة المنبه بالأسفل.';
      });
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
              engine: _engineCode(_activeEngine),
            );
      }
      return;
    }

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

  Future<void> _submitTextFallback() async {
    final text = _textFallbackCtrl.text.trim();
    if (text.isEmpty) return;
    _textFallbackCtrl.clear();
    setState(() {
      _accumulatedText = text;
      _currentPartial = '';
    });
    await _handleFinalTranscript(text);
  }

  Future<void> _handleFinalTranscript(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;

    // 1. Confirmation reply handling ("أيوه / تمام / احفظ" | "لا / غيّر" | "خليها ٨")
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

    // 2. Past-time confirmation ("الساعة عدت، تحب أظبطه بكره؟")
    if (_waitingForPastTimeTomorrowConfirm && _draftDateTime != null) {
      final reply = VoiceAlarmParser.parseConfirmationReply(trimmed);
      if (reply.type == VoiceReplyType.confirm) {
        _waitingForPastTimeTomorrowConfirm = false;
        _draftDateTime = _draftDateTime!.add(const Duration(days: 1));
        await _saveConfirmedAlarm();
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
        await _saveConfirmedAlarm();
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

    // 3. Rule-based Egyptian Arabic parser (100% offline, zero API keys)
    final now = DateTime.now();
    final intent = VoiceAlarmParser.parse(trimmed, nowLocal: now);

    if (_draftTitle == null &&
        intent.action != VoiceIntentAction.createAlarm &&
        intent.action != VoiceIntentAction.unknown) {
      await _executeNonCreateAction(intent);
      return;
    }

    final structured = intent.structured;
    if (structured == null) {
      const msg = 'مفهمتش الأمر. جرب تقول: فكرني بكره الساعة ٧ الصبح اخد الدوا';
      setState(() {
        _phase = _VoicePhase.idle;
        _statusMessage = msg;
      });
      await _speakAndMaybeListen(msg, listenAfter: false);
      return;
    }

    // Merge with any pending draft (e.g. user said "فكرني اشتري عيش" then answered "بكره الساعة ٨")
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
    if (intent.alarmType != AlarmType.personal) {
      _draftType = intent.alarmType;
    }

    final parsedDt = structured.parsedLocalDateTime;
    if (parsedDt != null) {
      _draftDateTime = parsedDt;
    }

    // Ask ONE short question in Arabic if time is missing or ambiguous
    if (structured.needsClarification || _draftDateTime == null) {
      final isPastToday = _draftDateTime != null && !_draftDateTime!.isAfter(now);
      _waitingForPastTimeTomorrowConfirm = isPastToday;
      final question = structured.question?.trim().isNotEmpty == true
          ? structured.question!.trim()
          : 'تحب أفكرك امتى؟';
      setState(() {
        _phase = _VoicePhase.awaitingClarification;
        _statusMessage = question;
      });
      await _speakAndMaybeListen(question, listenAfter: true);
      return;
    }

    // Automatically create, save, and close as soon as the alarm is understood — no confirmation or Save tap needed!
    await _saveConfirmedAlarm();
  }

  Future<void> _presentConfirmation() async {
    await _saveConfirmedAlarm();
  }

  Future<void> _saveConfirmedAlarm() async {
    if (_isSavingOrSaved) return;
    final dt = _draftDateTime;
    if (dt == null) return;

    _isSavingOrSaved = true;
    _ttsFallbackTimer?.cancel();
    _listenAfterTts = false;

    final voice = ref.read(nativeVoiceChannelProvider);
    try {
      await voice.cancelListening();
    } catch (_) {}

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

    bool arabicTtsReady = false;
    try {
      arabicTtsReady = await voice.isArabicTtsAvailable();
      if (arabicTtsReady) {
        await voice.speak(reply, language: _language);
      }
    } catch (_) {}

    if (mounted) {
      final messenger = ScaffoldMessenger.maybeOf(context);
      Navigator.of(context).pop(alarm);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            arabicTtsReady
                ? reply
                : '$reply\n(صوت النطق العربي غير مثبّت على الهاتف)',
          ),
          duration: Duration(seconds: arabicTtsReady ? 3 : 6),
          action: arabicTtsReady
              ? null
              : SnackBarAction(
                  label: 'تثبيت الصوت العربي',
                  onPressed: () => voice.installArabicTtsVoice(),
                ),
        ),
      );
    }
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).viewPadding.bottom;
    final cs = Theme.of(context).colorScheme;
    final isListening = _phase == _VoicePhase.listening;
    final liveText = _fullLiveTranscript;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
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
                Row(
                  children: [
                    IconButton(
                      tooltip: context.tr('Type instead', 'كتابة الأمر'),
                      icon: Icon(
                        _showTextFallback
                            ? Icons.keyboard_hide_outlined
                            : Icons.keyboard_outlined,
                      ),
                      onPressed: () => setState(
                        () => _showTextFallback = !_showTextFallback,
                      ),
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'ar-EG', label: Text('مصري')),
                        ButtonSegment(value: 'en-US', label: Text('EN')),
                      ],
                      selected: {_language},
                      onSelectionChanged: (s) =>
                          setState(() => _language = s.first),
                    ),
                  ],
                ),
              ],
            ),

            if (_engineNotice != null && _engineNotice!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _engineNotice!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSecondaryContainer,
                  ),
                ),
              ),
            ],

            const SizedBox(height: 10),

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
                              _statusMessage =
                                  'تم الإلغاء. اضغط الميكروفون أو اكتب للبدء من جديد.';
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
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),

            // Text-input fallback (shown automatically when speech is unavailable or toggled manually)
            if (_showTextFallback) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textFallbackCtrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _submitTextFallback(),
                      decoration: InputDecoration(
                        hintText: context.tr(
                          'Type alarm (e.g. remind me tomorrow 7am medicine)',
                          'اكتب المنبه هنا (مثلاً: فكرني بكره ٧ الصبح الدوا)',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _submitTextFallback,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ],

            const SizedBox(height: 16),

            // Controls: Mic + Manual "Done / تم" button while listening
            if (_micPermissionDenied)
              FilledButton.icon(
                onPressed: () => _startListening(resetTranscript: true),
                icon: const Icon(Icons.mic),
                label: Text(
                  context.tr('Grant Mic Permission', 'منح صلاحية الميكروفون'),
                ),
              )
            else
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
