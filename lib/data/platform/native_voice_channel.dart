import 'package:flutter/services.dart';

class VoiceEvent {
  final String type; // ready, partial, result, error, end
  final String? text;
  final String? message;
  final int? code;

  const VoiceEvent({
    required this.type,
    this.text,
    this.message,
    this.code,
  });

  factory VoiceEvent.fromMap(Map<dynamic, dynamic> map) {
    return VoiceEvent(
      type: map['type']?.toString() ?? 'unknown',
      text: map['text']?.toString(),
      message: map['message']?.toString(),
      code: (map['code'] as num?)?.toInt(),
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

  Future<void> startListening({String language = 'ar-EG'}) async {
    await _method.invokeMethod('startListening', {'language': language});
  }

  Future<void> stopListening() async {
    await _method.invokeMethod('stopListening');
  }

  Future<void> speak(String text, {String language = 'ar-EG'}) async {
    await _method.invokeMethod('speak', {'text': text, 'language': language});
  }

  Future<void> stopSpeaking() async {
    await _method.invokeMethod('stopSpeaking');
  }
}
