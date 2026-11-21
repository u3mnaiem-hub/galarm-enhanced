enum VoiceEngineChoice {
  onlineAndroid,
  onDeviceAndroid,
  voskOffline,
  textFallback,
}

class VoiceEngineSelection {
  final VoiceEngineChoice engine;
  final String? arabicNotice;

  const VoiceEngineSelection({
    required this.engine,
    this.arabicNotice,
  });
}

/// Pure, testable engine selection logic for U3m Alarm voice recognition:
/// - Offline mode ON  -> Engine A (Android On-Device), then Engine B (Vosk), else Text Fallback.
/// - Offline mode OFF -> Online Android recognizer when online & available;
///                       if no internet and an offline engine is installed, auto-switches to it;
///                       otherwise falls back to Text Input.
class VoiceEngineSelector {
  static VoiceEngineSelection select({
    required bool offlineModeEnabled,
    required bool hasInternet,
    required bool hasMicPermission,
    required bool isOnlineRecognizerAvailable,
    required bool isOnDeviceAndroidReady,
    required bool isVoskModelInstalled,
  }) {
    if (!hasMicPermission) {
      return const VoiceEngineSelection(
        engine: VoiceEngineChoice.textFallback,
        arabicNotice:
            'صلاحية الميكروفون غير مفعلة. يمكنك منح الصلاحية أو كتابة المنبه مباشرة بالأسفل.',
      );
    }

    if (offlineModeEnabled) {
      if (isOnDeviceAndroidReady) {
        return const VoiceEngineSelection(
          engine: VoiceEngineChoice.onDeviceAndroid,
          arabicNotice: 'الوضع الأوفلاين نشط (محرك أندرويد المدمج)',
        );
      }
      if (isVoskModelInstalled) {
        return const VoiceEngineSelection(
          engine: VoiceEngineChoice.voskOffline,
          arabicNotice: 'الوضع الأوفلاين نشط (نموذج Vosk المحلي)',
        );
      }
      return const VoiceEngineSelection(
        engine: VoiceEngineChoice.textFallback,
        arabicNotice:
            'الوضع الأوفلاين مفعّل لكن لا توجد حزمة صوت مثبّتة. قم بتحميلها من الإعدادات أو اكتب المنبه بالأسفل.',
      );
    }

    // Offline mode OFF: prefer normal online SpeechRecognizer when internet is available
    if (hasInternet && isOnlineRecognizerAvailable) {
      return const VoiceEngineSelection(
        engine: VoiceEngineChoice.onlineAndroid,
      );
    }

    // No internet (or online recognizer unavailable): auto-switch to installed offline engine
    if (isOnDeviceAndroidReady) {
      return VoiceEngineSelection(
        engine: VoiceEngineChoice.onDeviceAndroid,
        arabicNotice: hasInternet
            ? 'تم التبديل تلقائياً إلى محرك أندرويد الأوفلاين'
            : 'لا يوجد إنترنت — تم التبديل تلقائياً للوضع الأوفلاين (محرك أندرويد)',
      );
    }
    if (isVoskModelInstalled) {
      return VoiceEngineSelection(
        engine: VoiceEngineChoice.voskOffline,
        arabicNotice: hasInternet
            ? 'تم التبديل تلقائياً إلى نموذج Vosk الأوفلاين'
            : 'لا يوجد إنترنت — تم التبديل تلقائياً للوضع الأوفلاين (Vosk)',
      );
    }

    return VoiceEngineSelection(
      engine: VoiceEngineChoice.textFallback,
      arabicNotice: hasInternet
          ? 'التعرف الصوتي غير متاح على هذا الجهاز. يمكنك كتابة المنبه مباشرة بالأسفل.'
          : 'لا يوجد اتصال بالإنترنت ولا توجد حزمة أوفلاين مثبّتة. يمكنك كتابة المنبه مباشرة بالأسفل.',
    );
  }
}
