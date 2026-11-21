import 'package:flutter/services.dart';

class OfflineVoiceStatus {
  final int apiLevel;
  final bool onlineAvailable;
  final String onDeviceStatus; // 'ready' | 'downloading' | 'not_installed' | 'unsupported'
  final bool onDeviceSupported;
  final bool voskInstalled;
  final int voskSizeBytes;
  final bool voskDownloading;
  final int voskProgress;
  final int voskApproxDownloadMb;

  const OfflineVoiceStatus({
    this.apiLevel = 0,
    this.onlineAvailable = false,
    this.onDeviceStatus = 'unsupported',
    this.onDeviceSupported = false,
    this.voskInstalled = false,
    this.voskSizeBytes = 0,
    this.voskDownloading = false,
    this.voskProgress = 0,
    this.voskApproxDownloadMb = 318,
  });

  bool get isOnDeviceReady => onDeviceStatus == 'ready';
  bool get isAnyOfflineReady => isOnDeviceReady || voskInstalled;
  bool get isAnyDownloading =>
      onDeviceStatus == 'downloading' || voskDownloading;

  factory OfflineVoiceStatus.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) return const OfflineVoiceStatus();
    final vosk = (map['vosk'] as Map<dynamic, dynamic>?) ?? const {};
    return OfflineVoiceStatus(
      apiLevel: (map['apiLevel'] as num?)?.toInt() ?? 0,
      onlineAvailable: map['onlineAvailable'] == true,
      onDeviceStatus: map['onDeviceStatus']?.toString() ?? 'unsupported',
      onDeviceSupported: map['onDeviceSupported'] == true,
      voskInstalled: vosk['installed'] == true,
      voskSizeBytes: (vosk['sizeBytes'] as num?)?.toInt() ?? 0,
      voskDownloading: vosk['downloading'] == true,
      voskProgress: (vosk['progress'] as num?)?.toInt() ?? 0,
      voskApproxDownloadMb: (vosk['downloadSizeMb'] as num?)?.toInt() ?? 318,
    );
  }
}

class VoiceEvent {
  final String type; // ready, partial, result, error, end, tts_done, vosk_progress, on_device_progress
  final String? text;
  final String? message;
  final int? code;
  final String? phase;
  final int? percent;
  final int? downloadedBytes;
  final int? totalBytes;

  const VoiceEvent({
    required this.type,
    this.text,
    this.message,
    this.code,
    this.phase,
    this.percent,
    this.downloadedBytes,
    this.totalBytes,
  });

  // Android SpeechRecognizer error codes
  static const int errorNetworkTimeout = 1;
  static const int errorNetwork = 2;
  static const int errorAudio = 3;
  static const int errorSpeechTimeout = 6;
  static const int errorNoMatch = 7;
  static const int errorRecognizerBusy = 8;
  static const int errorInsufficientPermissions = 9;
  static const int errorServerDisconnected = 11;
  static const int errorLanguageNotSupported = 12;
  static const int errorLanguageUnavailable = 13;

  bool get isRecoverableSilenceError =>
      code == errorNoMatch || code == errorSpeechTimeout;

  bool get isNetworkError =>
      code == errorNetwork ||
      code == errorNetworkTimeout ||
      code == errorServerDisconnected;

  bool get isLanguagePackError =>
      code == errorLanguageNotSupported || code == errorLanguageUnavailable;

  bool get isPermissionError => code == errorInsufficientPermissions;

  factory VoiceEvent.fromMap(Map<dynamic, dynamic> map) {
    return VoiceEvent(
      type: map['type']?.toString() ?? 'unknown',
      text: map['text']?.toString(),
      message: map['message']?.toString(),
      code: (map['code'] as num?)?.toInt(),
      phase: map['phase']?.toString(),
      percent: (map['percent'] as num?)?.toInt(),
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt(),
      totalBytes: (map['totalBytes'] as num?)?.toInt(),
    );
  }
}

class NativeVoiceChannel {
  static const _method = MethodChannel('com.galarmenhanced/voice');
  static const _events = EventChannel('com.galarmenhanced/voice_events');

  Stream<VoiceEvent> get events => _events
      .receiveBroadcastStream()
      .map((e) => VoiceEvent.fromMap(e as Map<dynamic, dynamic>));

  Future<bool> isAvailable() async {
    return await _method.invokeMethod<bool>('isAvailable') ?? false;
  }

  Future<bool> hasRecordPermission() async {
    return await _method.invokeMethod<bool>('hasRecordPermission') ?? false;
  }

  Future<void> requestRecordPermission() async {
    await _method.invokeMethod('requestRecordPermission');
  }

  Future<OfflineVoiceStatus> getOfflineStatus({String language = 'ar-EG'}) async {
    try {
      final raw = await _method.invokeMethod<Map<dynamic, dynamic>>(
        'getOfflineStatus',
        {'language': language},
      );
      return OfflineVoiceStatus.fromMap(raw);
    } catch (_) {
      return const OfflineVoiceStatus();
    }
  }

  Future<String> downloadOnDevicePack({String language = 'ar-EG'}) async {
    try {
      return await _method.invokeMethod<String>(
            'downloadOnDevicePack',
            {'language': language},
          ) ??
          'opened_settings';
    } catch (_) {
      return 'error';
    }
  }

  Future<void> openSpeechSettings() async {
    try {
      await _method.invokeMethod('openSpeechSettings');
    } catch (_) {}
  }

  Future<void> downloadVoskModel({bool wifiOnly = true}) async {
    await _method.invokeMethod('downloadVoskModel', {'wifiOnly': wifiOnly});
  }

  Future<void> cancelVoskDownload() async {
    try {
      await _method.invokeMethod('cancelVoskDownload');
    } catch (_) {}
  }

  Future<bool> deleteVoskModel() async {
    try {
      return await _method.invokeMethod<bool>('deleteVoskModel') ?? false;
    } catch (_) {
      return false;
    }
  }

  /// [engine]: 'online' | 'on_device' | 'vosk'
  Future<void> startListening({
    String language = 'ar-EG',
    String engine = 'online',
  }) async {
    await _method.invokeMethod('startListening', {
      'language': language,
      'engine': engine,
    });
  }

  /// Gracefully stops listening so the active engine can finalize buffered speech.
  Future<void> stopListening() async {
    await _method.invokeMethod('stopListening');
  }

  /// Immediately cancels and stops the active recognizer.
  Future<void> cancelListening() async {
    await _method.invokeMethod('cancelListening');
  }

  Future<void> speak(String text, {String language = 'ar-EG'}) async {
    await _method.invokeMethod('speak', {'text': text, 'language': language});
  }

  Future<void> stopSpeaking() async {
    await _method.invokeMethod('stopSpeaking');
  }
}
