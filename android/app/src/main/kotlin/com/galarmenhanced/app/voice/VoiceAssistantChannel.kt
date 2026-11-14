package com.galarmenhanced.app.voice

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

/**
 * Native voice & sound helper modeled on Masrofy's proven VoiceInputModule:
 * runs SpeechRecognizer strictly on the main thread with applicationContext,
 * generous silence timeouts, Arabic error mapping, and safe TextToSpeech.
 */
class VoiceAssistantChannel(private val activity: Activity) : TextToSpeech.OnInitListener {
    private val appContext = activity.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var eventSink: EventChannel.EventSink? = null

    fun register(flutterEngine: FlutterEngine) {
        try {
            tts = TextToSpeech(appContext, this)
        } catch (_: Throwable) {
            ttsReady = false
        }

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
                        mainHandler.post {
                            try {
                                result.success(SpeechRecognizer.isRecognitionAvailable(appContext))
                            } catch (_: Throwable) {
                                result.success(false)
                            }
                        }
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
                        mainHandler.post { destroyRecognizer() }
                        result.success(true)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        val lang = call.argument<String>("language") ?: "ar-EG"
                        speak(text, lang)
                        result.success(true)
                    }
                    "stopSpeaking" -> {
                        try {
                            tts?.stop()
                        } catch (_: Throwable) {}
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
    }

    private fun emitEvent(payload: Map<String, Any>) {
        mainHandler.post {
            try {
                eventSink?.success(payload)
            } catch (_: Throwable) {}
        }
    }

    private fun speak(text: String, languageTag: String) {
        if (!ttsReady || text.isBlank()) return
        try {
            tts?.stop()
            val locale = Locale.forLanguageTag(languageTag.ifBlank { "ar-EG" })
            tts?.language = locale
            tts?.setSpeechRate(0.95f)
            tts?.setPitch(1.0f)
            tts?.speak(text, TextToSpeech.QUEUE_FLUSH, null, "galarm_tts")
        } catch (_: Throwable) {
            // Ignore speech synthesis failures on devices without TTS engine
        }
    }

    private fun startListening(languageCode: String) {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            emitEvent(mapOf("type" to "error", "message" to "يرجى منح صلاحية الميكروفون"))
            return
        }

        mainHandler.post {
            try {
                if (!SpeechRecognizer.isRecognitionAvailable(appContext)) {
                    emitEvent(mapOf("type" to "error", "message" to "التعرف الصوتي غير متاح على هذا الجهاز"))
                    return@post
                }

                destroyRecognizer()

                val recognizer = SpeechRecognizer.createSpeechRecognizer(appContext)
                speechRecognizer = recognizer

                recognizer.setRecognitionListener(object : RecognitionListener {
                    override fun onReadyForSpeech(params: Bundle?) {
                        emitEvent(mapOf("type" to "ready"))
                    }

                    override fun onBeginningOfSpeech() {}
                    override fun onRmsChanged(rmsdB: Float) {}
                    override fun onBufferReceived(buffer: ByteArray?) {}

                    override fun onEndOfSpeech() {
                        emitEvent(mapOf("type" to "end"))
                    }

                    override fun onError(error: Int) {
                        val message = when (error) {
                            SpeechRecognizer.ERROR_NO_MATCH -> "لم يتم التعرف على كلام واضح، حاول مرة أخرى"
                            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "انتهت مهلة الانتظار دون صوت"
                            SpeechRecognizer.ERROR_AUDIO -> "خطأ في تسجيل الصوت"
                            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "يرجى منح صلاحية الميكروفون"
                            SpeechRecognizer.ERROR_NETWORK -> "خطأ في الشبكة أثناء التعرف الصوتي"
                            else -> "خطأ في التعرف الصوتي ($error)"
                        }
                        emitEvent(mapOf("type" to "error", "code" to error, "message" to message))
                    }

                    override fun onResults(results: Bundle?) {
                        val matches = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull()?.trim() ?: ""
                        if (text.isNotEmpty()) {
                            emitEvent(mapOf("type" to "result", "text" to text))
                        } else {
                            emitEvent(
                                mapOf(
                                    "type" to "error",
                                    "code" to SpeechRecognizer.ERROR_NO_MATCH,
                                    "message" to "لم يتم اكتشاف كلمات"
                                )
                            )
                        }
                    }

                    override fun onPartialResults(partialResults: Bundle?) {
                        val matches = partialResults?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        val text = matches?.firstOrNull()?.trim() ?: ""
                        if (text.isNotBlank()) {
                            emitEvent(mapOf("type" to "partial", "text" to text))
                        }
                    }

                    override fun onEvent(eventType: Int, params: Bundle?) {}
                })

                val lang = languageCode.ifBlank { "ar-EG" }
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, lang)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS, 7000L)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS, 5000L)
                    putExtra(RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS, 8000L)
                }
                recognizer.startListening(intent)
            } catch (e: Throwable) {
                emitEvent(mapOf("type" to "error", "message" to (e.message ?: "تعذر بدء التعرف الصوتي")))
            }
        }
    }

    private fun destroyRecognizer() {
        try {
            speechRecognizer?.stopListening()
            speechRecognizer?.destroy()
        } catch (_: Throwable) {
        } finally {
            speechRecognizer = null
        }
    }

    fun dispose() {
        mainHandler.post { destroyRecognizer() }
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Throwable) {}
    }

    companion object {
        private const val REQ_RECORD_AUDIO = 4102
    }
}
