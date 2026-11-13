package com.galarmenhanced.app.voice

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class VoiceAssistantChannel(private val activity: Activity) : TextToSpeech.OnInitListener {
    private var speechRecognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var eventSink: EventChannel.EventSink? = null

    fun register(flutterEngine: FlutterEngine) {
        tts = TextToSpeech(activity, this)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, "com.galarmenhanced/voice_events")
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.galarmenhanced/voice")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> {
                        result.success(SpeechRecognizer.isRecognitionAvailable(activity))
                    }
                    "hasRecordPermission" -> {
                        val granted = ContextCompat.checkSelfPermission(
                            activity,
                            Manifest.permission.RECORD_AUDIO
                        ) == PackageManager.PERMISSION_GRANTED
                        result.success(granted)
                    }
                    "requestRecordPermission" -> {
                        ActivityCompat.requestPermissions(
                            activity,
                            arrayOf(Manifest.permission.RECORD_AUDIO),
                            REQ_RECORD_AUDIO
                        )
                        result.success(true)
                    }
                    "startListening" -> {
                        val lang = call.argument<String>("language") ?: "ar-EG"
                        startListening(lang)
                        result.success(true)
                    }
                    "stopListening" -> {
                        speechRecognizer?.stopListening()
                        result.success(true)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        val lang = call.argument<String>("language") ?: "ar-EG"
                        speak(text, lang)
                        result.success(true)
                    }
                    "stopSpeaking" -> {
                        tts?.stop()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
    }

    private fun speak(text: String, languageTag: String) {
        if (!ttsReady || text.isBlank()) return
        val locale = Locale.forLanguageTag(languageTag)
        tts?.language = locale
        tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "galarm_tts")
    }

    private fun startListening(languageCode: String) {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            eventSink?.success(mapOf("type" to "error", "message" to "RECORD_AUDIO permission required"))
            return
        }

        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(activity).apply {
            setRecognitionListener(object : RecognitionListener {
                override fun onReadyForSpeech(params: Bundle?) {
                    eventSink?.success(mapOf("type" to "ready"))
                }

                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {
                    eventSink?.success(mapOf("type" to "end"))
                }

                override fun onError(error: Int) {
                    eventSink?.success(mapOf("type" to "error", "code" to error))
                }

                override fun onResults(results: Bundle?) {
                    val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull() ?: ""
                    eventSink?.success(mapOf("type" to "result", "text" to text))
                }

                override fun onPartialResults(partialResults: Bundle?) {
                    val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                    val text = matches?.firstOrNull() ?: ""
                    if (text.isNotBlank()) {
                        eventSink?.success(mapOf("type" to "partial", "text" to text))
                    }
                }

                override fun onEvent(eventType: Int, params: Bundle?) {}
            })
        }

        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
            putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageCode)
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
        }
        speechRecognizer?.startListening(intent)
    }

    fun dispose() {
        speechRecognizer?.destroy()
        tts?.shutdown()
    }

    companion object {
        private const val REQ_RECORD_AUDIO = 4102
    }
}
