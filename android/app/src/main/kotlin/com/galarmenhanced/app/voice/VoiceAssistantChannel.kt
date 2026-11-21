package com.galarmenhanced.app.voice

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.speech.ModelDownloadListener
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

/**
 * Native voice & TTS helper for U3m Alarm:
 * - Online Android SpeechRecognizer (default when offline mode is OFF)
 * - Engine A: Android On-Device SpeechRecognizer (API 31+, checkRecognitionSupport & triggerModelDownload on API 33+)
 * - Engine B: Optional Vosk on-device Arabic model downloaded strictly on demand
 * - Handles errors 11, 12, 13 and all standard speech errors with Arabic messages
 */
class VoiceAssistantChannel(private val activity: Activity) : TextToSpeech.OnInitListener {
    private val appContext = activity.applicationContext
    private val mainHandler = Handler(Looper.getMainLooper())
    private var speechRecognizer: SpeechRecognizer? = null
    private var activeEngine: String = "online"
    private var tts: TextToSpeech? = null
    private var ttsReady = false
    private var eventSink: EventChannel.EventSink? = null

    private val voskEngine: VoskOfflineEngine by lazy {
        VoskOfflineEngine(appContext) { payload -> emitEvent(payload) }
    }

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
                    "getOfflineStatus" -> {
                        val lang = call.argument<String>("language") ?: DEFAULT_LOCALE
                        queryOfflineStatus(lang, result)
                    }
                    "downloadOnDevicePack" -> {
                        val lang = call.argument<String>("language") ?: DEFAULT_LOCALE
                        triggerOnDevicePackDownload(lang, result)
                    }
                    "openSpeechSettings" -> {
                        openSpeechSettings()
                        result.success(true)
                    }
                    "downloadVoskModel" -> {
                        val wifiOnly = call.argument<Boolean>("wifiOnly") ?: true
                        voskEngine.downloadModel(wifiOnly = wifiOnly)
                        result.success(true)
                    }
                    "cancelVoskDownload" -> {
                        voskEngine.cancelDownload()
                        result.success(true)
                    }
                    "deleteVoskModel" -> {
                        val ok = voskEngine.deleteModel()
                        result.success(ok)
                    }
                    "startListening" -> {
                        val lang = call.argument<String>("language") ?: DEFAULT_LOCALE
                        val engine = call.argument<String>("engine") ?: "online"
                        startListening(lang, engine)
                        result.success(true)
                    }
                    "stopListening" -> {
                        mainHandler.post {
                            if (activeEngine == "vosk") {
                                voskEngine.stopListening(emitFinalResult = true)
                            } else {
                                try {
                                    speechRecognizer?.stopListening()
                                } catch (_: Throwable) {
                                    destroyRecognizer()
                                }
                            }
                        }
                        result.success(true)
                    }
                    "cancelListening" -> {
                        mainHandler.post {
                            if (activeEngine == "vosk") {
                                voskEngine.stopListening(emitFinalResult = false)
                            }
                            destroyRecognizer()
                        }
                        result.success(true)
                    }
                    "speak" -> {
                        val text = call.argument<String>("text") ?: ""
                        val lang = call.argument<String>("language") ?: DEFAULT_LOCALE
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

    private fun queryOfflineStatus(languageCode: String, result: MethodChannel.Result) {
        val voskMap = voskEngine.getStatusMap()
        val apiLevel = Build.VERSION.SDK_INT
        val onlineAvailable = try {
            SpeechRecognizer.isRecognitionAvailable(appContext)
        } catch (_: Throwable) {
            false
        }

        if (apiLevel >= Build.VERSION_CODES.TIRAMISU) {
            mainHandler.post {
                try {
                    if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(appContext)) {
                        result.success(
                            mapOf(
                                "apiLevel" to apiLevel,
                                "onlineAvailable" to onlineAvailable,
                                "onDeviceStatus" to "unsupported",
                                "onDeviceSupported" to false,
                                "vosk" to voskMap
                            )
                        )
                        return@post
                    }
                    val tempRecognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(appContext)
                    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                        putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageCode.ifBlank { DEFAULT_LOCALE })
                    }
                    tempRecognizer.checkRecognitionSupport(
                        intent,
                        ContextCompat.getMainExecutor(appContext),
                        object : RecognitionSupportCallback {
                            override fun onSupportResult(recognitionSupport: RecognitionSupport) {
                                try { tempRecognizer.destroy() } catch (_: Throwable) {}
                                val installed = recognitionSupport.installedOnDeviceLanguages
                                val supported = recognitionSupport.supportedOnDeviceLanguages
                                val pending = recognitionSupport.pendingOnDeviceLanguages

                                val hasArabicInstalled = installed.any {
                                    it.equals(DEFAULT_LOCALE, ignoreCase = true) ||
                                        it.startsWith("ar", ignoreCase = true)
                                }
                                val hasArabicPending = pending.any {
                                    it.equals(DEFAULT_LOCALE, ignoreCase = true) ||
                                        it.startsWith("ar", ignoreCase = true)
                                }
                                val hasArabicSupported = supported.any {
                                    it.equals(DEFAULT_LOCALE, ignoreCase = true) ||
                                        it.startsWith("ar", ignoreCase = true)
                                }

                                val status = when {
                                    hasArabicInstalled -> "ready"
                                    hasArabicPending -> "downloading"
                                    hasArabicSupported -> "not_installed"
                                    else -> "unsupported"
                                }
                                result.success(
                                    mapOf(
                                        "apiLevel" to apiLevel,
                                        "onlineAvailable" to onlineAvailable,
                                        "onDeviceStatus" to status,
                                        "onDeviceSupported" to (status != "unsupported"),
                                        "vosk" to voskMap
                                    )
                                )
                            }

                            override fun onError(error: Int) {
                                try { tempRecognizer.destroy() } catch (_: Throwable) {}
                                result.success(
                                    mapOf(
                                        "apiLevel" to apiLevel,
                                        "onlineAvailable" to onlineAvailable,
                                        "onDeviceStatus" to "unsupported",
                                        "onDeviceSupported" to false,
                                        "vosk" to voskMap
                                    )
                                )
                            }
                        }
                    )
                } catch (_: Throwable) {
                    result.success(
                        mapOf(
                            "apiLevel" to apiLevel,
                            "onlineAvailable" to onlineAvailable,
                            "onDeviceStatus" to "unsupported",
                            "onDeviceSupported" to false,
                            "vosk" to voskMap
                        )
                    )
                }
            }
        } else if (apiLevel >= Build.VERSION_CODES.S) {
            val available = try {
                SpeechRecognizer.isOnDeviceRecognitionAvailable(appContext)
            } catch (_: Throwable) {
                false
            }
            result.success(
                mapOf(
                    "apiLevel" to apiLevel,
                    "onlineAvailable" to onlineAvailable,
                    "onDeviceStatus" to if (available) "ready" else "unsupported",
                    "onDeviceSupported" to available,
                    "vosk" to voskMap
                )
            )
        } else {
            result.success(
                mapOf(
                    "apiLevel" to apiLevel,
                    "onlineAvailable" to onlineAvailable,
                    "onDeviceStatus" to "unsupported",
                    "onDeviceSupported" to false,
                    "vosk" to voskMap
                )
            )
        }
    }

    private fun triggerOnDevicePackDownload(languageCode: String, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            openSpeechSettings()
            result.success("opened_settings")
            return
        }

        mainHandler.post {
            try {
                if (!SpeechRecognizer.isOnDeviceRecognitionAvailable(appContext)) {
                    openSpeechSettings()
                    result.success("opened_settings")
                    return@post
                }
                val tempRecognizer = SpeechRecognizer.createOnDeviceSpeechRecognizer(appContext)
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, languageCode.ifBlank { DEFAULT_LOCALE })
                }

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                    tempRecognizer.triggerModelDownload(
                        intent,
                        ContextCompat.getMainExecutor(appContext),
                        object : ModelDownloadListener {
                            override fun onProgress(completedPercent: Int) {
                                emitEvent(
                                    mapOf(
                                        "type" to "on_device_progress",
                                        "phase" to "downloading",
                                        "percent" to completedPercent,
                                        "message" to "جاري تحميل حزمة العربية... $completedPercent%"
                                    )
                                )
                            }

                            override fun onSuccess() {
                                try { tempRecognizer.destroy() } catch (_: Throwable) {}
                                emitEvent(
                                    mapOf(
                                        "type" to "on_device_progress",
                                        "phase" to "ready",
                                        "percent" to 100,
                                        "message" to "حزمة العربية جاهزة للعمل بدون إنترنت"
                                    )
                                )
                            }

                            override fun onScheduled() {
                                emitEvent(
                                    mapOf(
                                        "type" to "on_device_progress",
                                        "phase" to "downloading",
                                        "percent" to 0,
                                        "message" to "تم جدولة تحميل حزمة العربية في الخلفية"
                                    )
                                )
                            }

                            override fun onError(error: Int) {
                                try { tempRecognizer.destroy() } catch (_: Throwable) {}
                                emitEvent(
                                    mapOf(
                                        "type" to "on_device_progress",
                                        "phase" to "error",
                                        "percent" to 0,
                                        "message" to mapSpeechErrorToArabic(error)
                                    )
                                )
                            }
                        }
                    )
                    result.success("started")
                } else {
                    tempRecognizer.triggerModelDownload(intent)
                    mainHandler.postDelayed({
                        try { tempRecognizer.destroy() } catch (_: Throwable) {}
                    }, 3000L)
                    emitEvent(
                        mapOf(
                            "type" to "on_device_progress",
                            "phase" to "downloading",
                            "percent" to 0,
                            "message" to "بدأ تحميل حزمة العربية في الخلفية"
                        )
                    )
                    result.success("scheduled")
                }
            } catch (_: Throwable) {
                openSpeechSettings()
                result.success("opened_settings")
            }
        }
    }

    private fun openSpeechSettings() {
        mainHandler.post {
            try {
                val intent = Intent("android.settings.VOICE_INPUT_SETTINGS").apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivity(intent)
            } catch (_: Throwable) {
                try {
                    val fallback = Intent(Settings.ACTION_SETTINGS).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    activity.startActivity(fallback)
                } catch (_: Throwable) {}
            }
        }
    }

    override fun onInit(status: Int) {
        ttsReady = status == TextToSpeech.SUCCESS
        if (ttsReady) {
            tts?.setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) {}
                override fun onDone(utteranceId: String?) {
                    emitEvent(mapOf("type" to "tts_done"))
                }

                @Deprecated("Deprecated in Java")
                override fun onError(utteranceId: String?) {
                    emitEvent(mapOf("type" to "tts_done"))
                }

                override fun onError(utteranceId: String?, errorCode: Int) {
                    emitEvent(mapOf("type" to "tts_done"))
                }
            })
        }
    }

    private fun emitEvent(payload: Map<String, Any>) {
        mainHandler.post {
            try {
                eventSink?.success(payload)
            } catch (_: Throwable) {}
        }
    }

    private fun resolveTtsLocale(languageTag: String): Locale {
        val primary = Locale.forLanguageTag(languageTag.ifBlank { DEFAULT_LOCALE })
        val res = tts?.isLanguageAvailable(primary) ?: TextToSpeech.LANG_NOT_SUPPORTED
        if (res >= TextToSpeech.LANG_AVAILABLE) {
            return primary
        }
        if (languageTag.startsWith("ar", ignoreCase = true)) {
            val fallback = Locale(FALLBACK_LOCALE)
            val fbRes = tts?.isLanguageAvailable(fallback) ?: TextToSpeech.LANG_NOT_SUPPORTED
            if (fbRes >= TextToSpeech.LANG_AVAILABLE) {
                return fallback
            }
        }
        return primary
    }

    private fun speak(text: String, languageTag: String) {
        if (!ttsReady || text.isBlank()) {
            emitEvent(mapOf("type" to "tts_done"))
            return
        }
        try {
            tts?.stop()
            val locale = resolveTtsLocale(languageTag)
            tts?.language = locale
            tts?.setSpeechRate(0.95f)
            tts?.setPitch(1.0f)
            val params = Bundle()
            val result = tts?.speak(text, TextToSpeech.QUEUE_FLUSH, params, "u3m_tts_${System.currentTimeMillis()}")
            if (result != TextToSpeech.SUCCESS) {
                emitEvent(mapOf("type" to "tts_done"))
            }
        } catch (_: Throwable) {
            emitEvent(mapOf("type" to "tts_done"))
        }
    }

    private fun mapSpeechErrorToArabic(error: Int): String {
        return when (error) {
            SpeechRecognizer.ERROR_NETWORK_TIMEOUT,
            SpeechRecognizer.ERROR_NETWORK -> "لا يوجد اتصال بالإنترنت للتعرف الصوتي"
            SpeechRecognizer.ERROR_AUDIO -> "خطأ في تسجيل الصوت من الميكروفون"
            SpeechRecognizer.ERROR_SERVER -> "حدث خطأ في خادم التعرف الصوتي، حاول مرة أخرى"
            SpeechRecognizer.ERROR_CLIENT -> "تعذر تشغيل محرك التعرف الصوتي"
            SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "انتهى وقت الانتظار دون صوت"
            SpeechRecognizer.ERROR_NO_MATCH -> "لم أسمع كلاماً واضحاً، حاول مرة أخرى"
            SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> "الميكروفون مشغول حالياً، حاول مرة أخرى"
            SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "يرجى منح صلاحية الميكروفون"
            11 -> "انقطع الاتصال بخدمة التعرف الصوتي، حاول مرة أخرى"
            12 -> "اللغة العربية غير مدعومة في هذا المحرك، جرب تحميل حزمة الأوفلاين"
            13 -> "حزمة اللغة العربية غير مثبّتة للعمل بدون إنترنت، يرجى تحميلها من الإعدادات"
            else -> "تعذر التعرف على الصوت (رمز $error)"
        }
    }

    private fun startListening(languageCode: String, engine: String) {
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO)
            != PackageManager.PERMISSION_GRANTED
        ) {
            emitEvent(
                mapOf(
                    "type" to "error",
                    "code" to SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS,
                    "message" to "يرجى منح صلاحية الميكروفون لاستخدام المساعد الصوتي"
                )
            )
            return
        }

        activeEngine = engine

        if (engine == "vosk") {
            mainHandler.post { destroyRecognizer() }
            voskEngine.startListening(COMPLETE_SILENCE_LENGTH_MILLIS)
            return
        }

        mainHandler.post {
            try {
                voskEngine.stopListening(emitFinalResult = false)
                destroyRecognizer()

                val recognizer: SpeechRecognizer = if (engine == "on_device" &&
                    Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                    SpeechRecognizer.isOnDeviceRecognitionAvailable(appContext)
                ) {
                    SpeechRecognizer.createOnDeviceSpeechRecognizer(appContext)
                } else {
                    if (!SpeechRecognizer.isRecognitionAvailable(appContext)) {
                        emitEvent(
                            mapOf(
                                "type" to "error",
                                "code" to SpeechRecognizer.ERROR_CLIENT,
                                "message" to "التعرف الصوتي غير متاح على هذا الجهاز"
                            )
                        )
                        return@post
                    }
                    SpeechRecognizer.createSpeechRecognizer(appContext)
                }

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
                        emitEvent(
                            mapOf(
                                "type" to "error",
                                "code" to error,
                                "message" to mapSpeechErrorToArabic(error)
                            )
                        )
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
                                    "message" to "لم يتم اكتشاف كلمات واضحة"
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

                val lang = languageCode.ifBlank { DEFAULT_LOCALE }
                val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, lang)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, lang)
                    putExtra(RecognizerIntent.EXTRA_ONLY_RETURN_LANGUAGE_PREFERENCE, false)
                    putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
                    putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 3)
                    if (engine == "on_device") {
                        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
                    }
                    putExtra(
                        RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
                        COMPLETE_SILENCE_LENGTH_MILLIS
                    )
                    putExtra(
                        RecognizerIntent.EXTRA_SPEECH_INPUT_POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS,
                        POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS
                    )
                    putExtra(
                        RecognizerIntent.EXTRA_SPEECH_INPUT_MINIMUM_LENGTH_MILLIS,
                        MINIMUM_SPEECH_LENGTH_MILLIS
                    )
                }
                recognizer.startListening(intent)
            } catch (e: Throwable) {
                emitEvent(
                    mapOf(
                        "type" to "error",
                        "code" to SpeechRecognizer.ERROR_CLIENT,
                        "message" to (e.message ?: "تعذر بدء التعرف الصوتي")
                    )
                )
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
        voskEngine.dispose()
        try {
            tts?.stop()
            tts?.shutdown()
        } catch (_: Throwable) {}
    }

    companion object {
        private const val REQ_RECORD_AUDIO = 4102

        // Speech recognition & TTS tuning constants (edit in one place)
        const val DEFAULT_LOCALE = "ar-EG"
        const val FALLBACK_LOCALE = "ar"
        const val COMPLETE_SILENCE_LENGTH_MILLIS = 3500L
        const val POSSIBLY_COMPLETE_SILENCE_LENGTH_MILLIS = 3000L
        const val MINIMUM_SPEECH_LENGTH_MILLIS = 5000L
    }
}
