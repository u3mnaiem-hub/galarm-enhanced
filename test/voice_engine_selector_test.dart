import 'package:flutter_test/flutter_test.dart';
import 'package:galarm_enhanced/domain/services/voice_engine_selector.dart';

void main() {
  group('VoiceEngineSelector', () {
    test('Offline mode OFF + internet + online recognizer -> onlineAndroid', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: false,
        hasInternet: true,
        hasMicPermission: true,
        isOnlineRecognizerAvailable: true,
        isOnDeviceAndroidReady: true,
        isVoskModelInstalled: true,
      );
      expect(res.engine, VoiceEngineChoice.onlineAndroid);
    });

    test('Offline mode ON -> prefers Engine A (onDeviceAndroid) over Engine B (Vosk)', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: true,
        hasInternet: true,
        hasMicPermission: true,
        isOnlineRecognizerAvailable: true,
        isOnDeviceAndroidReady: true,
        isVoskModelInstalled: true,
      );
      expect(res.engine, VoiceEngineChoice.onDeviceAndroid);
    });

    test('Offline mode ON + Engine A unavailable + Vosk installed -> voskOffline', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: true,
        hasInternet: true,
        hasMicPermission: true,
        isOnlineRecognizerAvailable: true,
        isOnDeviceAndroidReady: false,
        isVoskModelInstalled: true,
      );
      expect(res.engine, VoiceEngineChoice.voskOffline);
    });

    test('Offline mode ON + neither offline engine installed -> textFallback', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: true,
        hasInternet: true,
        hasMicPermission: true,
        isOnlineRecognizerAvailable: true,
        isOnDeviceAndroidReady: false,
        isVoskModelInstalled: false,
      );
      expect(res.engine, VoiceEngineChoice.textFallback);
      expect(res.arabicNotice, isNotEmpty);
    });

    test('Offline mode OFF + NO internet + Engine A installed -> auto-switch onDeviceAndroid', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: false,
        hasInternet: false,
        hasMicPermission: true,
        isOnlineRecognizerAvailable: true,
        isOnDeviceAndroidReady: true,
        isVoskModelInstalled: false,
      );
      expect(res.engine, VoiceEngineChoice.onDeviceAndroid);
      expect(res.arabicNotice, contains('أوفلاين'));
    });

    test('Offline mode OFF + NO internet + only Vosk installed -> auto-switch voskOffline', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: false,
        hasInternet: false,
        hasMicPermission: true,
        isOnlineRecognizerAvailable: true,
        isOnDeviceAndroidReady: false,
        isVoskModelInstalled: true,
      );
      expect(res.engine, VoiceEngineChoice.voskOffline);
      expect(res.arabicNotice, contains('Vosk'));
    });

    test('Offline mode OFF + NO internet + NO offline engine -> textFallback', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: false,
        hasInternet: false,
        hasMicPermission: true,
        isOnlineRecognizerAvailable: true,
        isOnDeviceAndroidReady: false,
        isVoskModelInstalled: false,
      );
      expect(res.engine, VoiceEngineChoice.textFallback);
      expect(res.arabicNotice, isNotEmpty);
    });

    test('No Google/online speech services + Vosk installed -> voskOffline', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: false,
        hasInternet: true,
        hasMicPermission: true,
        isOnlineRecognizerAvailable: false,
        isOnDeviceAndroidReady: false,
        isVoskModelInstalled: true,
      );
      expect(res.engine, VoiceEngineChoice.voskOffline);
    });

    test('No mic permission -> always textFallback with Arabic message', () {
      final res = VoiceEngineSelector.select(
        offlineModeEnabled: false,
        hasInternet: true,
        hasMicPermission: false,
        isOnlineRecognizerAvailable: true,
        isOnDeviceAndroidReady: true,
        isVoskModelInstalled: true,
      );
      expect(res.engine, VoiceEngineChoice.textFallback);
      expect(res.arabicNotice, contains('الميكروفون'));
    });
  });
}
