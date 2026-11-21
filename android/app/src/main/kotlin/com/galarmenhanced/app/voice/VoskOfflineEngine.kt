package com.galarmenhanced.app.voice

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer
import org.vosk.android.RecognitionListener
import org.vosk.android.SpeechService
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipInputStream

/**
 * Optional Engine B: Free, open-source (Apache-2.0) Vosk on-device Arabic speech recognizer.
 * - Zero models are bundled in the APK.
 * - Downloads vosk-model-ar-mgb2-0.4 (~318 MB) strictly on demand into app-private storage.
 * - Supports Wi-Fi check, free storage check, HTTP Range resume, progress callbacks, and deletion.
 */
class VoskOfflineEngine(
    private val appContext: Context,
    private val emitEvent: (Map<String, Any>) -> Unit
) {
    private val ioExecutor = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var voskModel: Model? = null
    private var speechService: SpeechService? = null

    private val isDownloading = AtomicBoolean(false)
    private val cancelDownloadFlag = AtomicBoolean(false)
    @Volatile
    private var lastProgressPercent = 0

    private val accumulatedSpeech = StringBuilder()
    private var lastPartialText = ""
    private var silenceFinalizeRunnable: Runnable? = null

    private val modelsRootDir: File
        get() = File(appContext.filesDir, "vosk_models")

    private val modelDir: File
        get() = File(modelsRootDir, MODEL_NAME)

    private val partialZipFile: File
        get() = File(modelsRootDir, "$MODEL_NAME.zip.part")

    fun isModelInstalled(): Boolean {
        val dir = modelDir
        if (!dir.exists() || !dir.isDirectory) return false
        val readyMarker = File(dir, ".ready")
        val confDir = File(dir, "conf")
        return readyMarker.exists() || (confDir.exists() && confDir.isDirectory)
    }

    fun getInstalledSizeBytes(): Long {
        if (!modelDir.exists()) return 0L
        return computeDirSize(modelDir)
    }

    fun getStatusMap(): Map<String, Any> {
        return mapOf(
            "installed" to isModelInstalled(),
            "sizeBytes" to getInstalledSizeBytes(),
            "downloading" to isDownloading.get(),
            "progress" to lastProgressPercent,
            "modelName" to MODEL_NAME,
            "downloadSizeMb" to APPROX_DOWNLOAD_SIZE_MB
        )
    }

    private fun computeDirSize(file: File): Long {
        if (!file.exists()) return 0L
        if (file.isFile) return file.length()
        var total = 0L
        file.listFiles()?.forEach { child ->
            total += computeDirSize(child)
        }
        return total
    }

    private fun isOnWifi(): Boolean {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)
    }

    private fun hasInternet(): Boolean {
        val cm = appContext.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return false
        val network = cm.activeNetwork ?: return false
        val caps = cm.getNetworkCapabilities(network) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun getAvailableStorageBytes(): Long {
        val stat = StatFs(appContext.filesDir.absolutePath)
        return stat.availableBytes
    }

    fun cancelDownload() {
        cancelDownloadFlag.set(true)
    }

    fun downloadModel(wifiOnly: Boolean = true) {
        if (isModelInstalled()) {
            emitProgress("ready", 100, getInstalledSizeBytes(), getInstalledSizeBytes(), "النموذج جاهز بالفعل")
            return
        }
        if (!isDownloading.compareAndSet(false, true)) {
            return
        }
        cancelDownloadFlag.set(false)
        lastProgressPercent = 0

        ioExecutor.execute {
            var connection: HttpURLConnection? = null
            try {
                if (!hasInternet()) {
                    emitProgress("error", 0, 0L, 0L, "لا يوجد اتصال بالإنترنت لتحميل النموذج")
                    return@execute
                }
                if (wifiOnly && !isOnWifi()) {
                    emitProgress("error", 0, 0L, 0L, "يرجى الاتصال بشبكة Wi-Fi لتحميل النموذج (أو السماح ببيانات الهاتف)")
                    return@execute
                }

                val availBytes = getAvailableStorageBytes()
                if (availBytes < MIN_REQUIRED_FREE_BYTES) {
                    val neededMb = MIN_REQUIRED_FREE_BYTES / (1024 * 1024)
                    val availMb = availBytes / (1024 * 1024)
                    emitProgress(
                        "error",
                        0,
                        0L,
                        0L,
                        "المساحة التخزينية غير كافية (المتاح $availMb ميجابايت، المطلوب على الأقل $neededMb ميجابايت)"
                    )
                    return@execute
                }

                if (!modelsRootDir.exists()) {
                    modelsRootDir.mkdirs()
                }

                val partFile = partialZipFile
                val existingBytes = if (partFile.exists()) partFile.length() else 0L

                val url = URL(MODEL_URL)
                connection = (url.openConnection() as HttpURLConnection).apply {
                    connectTimeout = 15000
                    readTimeout = 30000
                    instanceFollowRedirects = true
                    if (existingBytes > 0L) {
                        setRequestProperty("Range", "bytes=$existingBytes-")
                    }
                }
                connection.connect()

                val code = connection.responseCode
                val isResuming = code == HttpURLConnection.HTTP_PARTIAL && existingBytes > 0L
                if (code != HttpURLConnection.HTTP_OK && !isResuming) {
                    emitProgress("error", 0, 0L, 0L, "تعذر تحميل النموذج من الخادم (رمز $code)")
                    return@execute
                }

                val contentLength = connection.contentLengthLong
                val totalBytes = if (contentLength > 0L) {
                    if (isResuming) existingBytes + contentLength else contentLength
                } else {
                    APPROX_DOWNLOAD_SIZE_MB * 1024L * 1024L
                }

                var downloaded = if (isResuming) existingBytes else 0L
                val outStream = FileOutputStream(partFile, isResuming)
                val inStream = BufferedInputStream(connection.inputStream)

                inStream.use { input ->
                    outStream.use { output ->
                        val buffer = ByteArray(16 * 1024)
                        var lastEmitTime = 0L
                        while (true) {
                            if (cancelDownloadFlag.get()) {
                                emitProgress("cancelled", lastProgressPercent, downloaded, totalBytes, "تم إيقاف التحميل مؤقتاً (يمكنك الاستكمال لاحقاً)")
                                return@execute
                            }
                            val read = input.read(buffer)
                            if (read == -1) break
                            output.write(buffer, 0, read)
                            downloaded += read

                            val now = System.currentTimeMillis()
                            if (now - lastEmitTime >= 350L || downloaded >= totalBytes) {
                                lastEmitTime = now
                                val pct = ((downloaded * 90L) / totalBytes.coerceAtLeast(1L)).toInt().coerceIn(0, 90)
                                lastProgressPercent = pct
                                emitProgress("downloading", pct, downloaded, totalBytes, "جاري التحميل... $pct%")
                            }
                        }
                    }
                }

                if (cancelDownloadFlag.get()) {
                    emitProgress("cancelled", lastProgressPercent, downloaded, totalBytes, "تم إلغاء التحميل")
                    return@execute
                }

                // Extract ZIP safely into modelsRootDir
                emitProgress("extracting", 92, downloaded, totalBytes, "جاري فك ضغط النموذج...")
                if (modelDir.exists()) {
                    modelDir.deleteRecursively()
                }

                val canonicalRoot = modelsRootDir.canonicalPath
                ZipInputStream(BufferedInputStream(FileInputStream(partFile))).use { zis ->
                    val buffer = ByteArray(16 * 1024)
                    var entry = zis.nextEntry
                    while (entry != null) {
                        if (cancelDownloadFlag.get()) {
                            modelDir.deleteRecursively()
                            emitProgress("cancelled", 0, 0L, 0L, "تم إلغاء التثبيت")
                            return@execute
                        }
                        val outFile = File(modelsRootDir, entry.name)
                        if (!outFile.canonicalPath.startsWith(canonicalRoot)) {
                            throw SecurityException("Invalid zip entry path")
                        }
                        if (entry.isDirectory) {
                            outFile.mkdirs()
                        } else {
                            outFile.parentFile?.mkdirs()
                            FileOutputStream(outFile).use { fos ->
                                var len: Int
                                while (zis.read(buffer).also { len = it } != -1) {
                                    fos.write(buffer, 0, len)
                                }
                            }
                        }
                        zis.closeEntry()
                        entry = zis.nextEntry
                    }
                }

                // Mark ready & delete zip archive to free space
                if (modelDir.exists()) {
                    File(modelDir, ".ready").writeText("ok")
                }
                partFile.delete()

                lastProgressPercent = 100
                val finalSize = getInstalledSizeBytes()
                emitProgress("ready", 100, finalSize, finalSize, "تم تثبيت النموذج الأوفلاين بنجاح")
            } catch (e: Throwable) {
                emitProgress("error", lastProgressPercent, 0L, 0L, "تعذر تحميل النموذج: ${e.message ?: "خطأ غير متوقع"}")
            } finally {
                connection?.disconnect()
                isDownloading.set(false)
            }
        }
    }

    fun deleteModel(): Boolean {
        cancelDownloadFlag.set(true)
        stopListening(emitFinalResult = false)
        try {
            voskModel?.close()
        } catch (_: Throwable) {}
        voskModel = null
        val d1 = if (modelDir.exists()) modelDir.deleteRecursively() else true
        val d2 = if (partialZipFile.exists()) partialZipFile.delete() else true
        lastProgressPercent = 0
        emitProgress("deleted", 0, 0L, 0L, "تم حذف النموذج وتفريغ المساحة")
        return d1 && d2
    }

    fun startListening(silenceTimeoutMs: Long = VoiceAssistantChannel.COMPLETE_SILENCE_LENGTH_MILLIS) {
        if (!isModelInstalled()) {
            emitEvent(
                mapOf(
                    "type" to "error",
                    "code" to 13,
                    "message" to "نموذج الأوفلاين (Vosk) غير مثبّت. يرجى تحميله من الإعدادات."
                )
            )
            return
        }

        stopListening(emitFinalResult = false)
        accumulatedSpeech.clear()
        lastPartialText = ""

        ioExecutor.execute {
            try {
                val model = voskModel ?: Model(modelDir.absolutePath).also { voskModel = it }
                val recognizer = Recognizer(model, 16000.0f)
                val service = SpeechService(recognizer, 16000.0f)
                speechService = service

                emitEvent(mapOf("type" to "ready"))

                service.startListening(object : RecognitionListener {
                    override fun onPartialResult(hypothesis: String?) {
                        val partial = extractJsonField(hypothesis, "partial")
                        if (partial.isNotBlank()) {
                            lastPartialText = partial
                            val combined = buildCombinedText(partial)
                            emitEvent(mapOf("type" to "partial", "text" to combined))
                            resetSilenceTimer(silenceTimeoutMs)
                        }
                    }

                    override fun onResult(hypothesis: String?) {
                        val text = extractJsonField(hypothesis, "text")
                        if (text.isNotBlank()) {
                            if (accumulatedSpeech.isNotEmpty()) accumulatedSpeech.append(' ')
                            accumulatedSpeech.append(text)
                            lastPartialText = ""
                            emitEvent(mapOf("type" to "partial", "text" to accumulatedSpeech.toString().trim()))
                            resetSilenceTimer(silenceTimeoutMs)
                        }
                    }

                    override fun onFinalResult(hypothesis: String?) {
                        val text = extractJsonField(hypothesis, "text")
                        if (text.isNotBlank()) {
                            if (accumulatedSpeech.isNotEmpty()) accumulatedSpeech.append(' ')
                            accumulatedSpeech.append(text)
                        }
                        lastPartialText = ""
                    }

                    override fun onError(exception: Exception?) {
                        cancelSilenceTimer()
                        emitEvent(
                            mapOf(
                                "type" to "error",
                                "code" to 3,
                                "message" to "خطأ في محرك Vosk الأوفلاين: ${exception?.message ?: ""}"
                            )
                        )
                    }

                    override fun onTimeout() {
                        finishWithAccumulated()
                    }
                })
            } catch (e: Throwable) {
                emitEvent(
                    mapOf(
                        "type" to "error",
                        "code" to 5,
                        "message" to "تعذر تشغيل محرك Vosk الأوفلاين: ${e.message ?: ""}"
                    )
                )
            }
        }
    }

    fun stopListening(emitFinalResult: Boolean) {
        cancelSilenceTimer()
        val service = speechService
        speechService = null
        if (service != null) {
            try {
                service.stop()
                service.shutdown()
            } catch (_: Throwable) {}
        }
        if (emitFinalResult) {
            finishWithAccumulated()
        }
    }

    private fun resetSilenceTimer(timeoutMs: Long) {
        cancelSilenceTimer()
        val r = Runnable {
            stopListening(emitFinalResult = true)
        }
        silenceFinalizeRunnable = r
        mainHandler.postDelayed(r, timeoutMs)
    }

    private fun cancelSilenceTimer() {
        silenceFinalizeRunnable?.let { mainHandler.removeCallbacks(it) }
        silenceFinalizeRunnable = null
    }

    private fun buildCombinedText(partial: String): String {
        val base = accumulatedSpeech.toString().trim()
        return if (base.isEmpty()) partial.trim() else "$base ${partial.trim()}".trim()
    }

    private fun finishWithAccumulated() {
        val finalStr = buildCombinedText(lastPartialText).trim()
        accumulatedSpeech.clear()
        lastPartialText = ""
        emitEvent(mapOf("type" to "end"))
        if (finalStr.isNotEmpty()) {
            emitEvent(mapOf("type" to "result", "text" to finalStr))
        } else {
            emitEvent(
                mapOf(
                    "type" to "error",
                    "code" to 7,
                    "message" to "لم أسمع كلاماً واضحاً، حاول مرة أخرى"
                )
            )
        }
    }

    private fun extractJsonField(json: String?, key: String): String {
        if (json.isNullOrBlank()) return ""
        return try {
            JSONObject(json).optString(key, "").trim()
        } catch (_: Throwable) {
            ""
        }
    }

    private fun emitProgress(
        phase: String,
        percent: Int,
        downloadedBytes: Long,
        totalBytes: Long,
        message: String
    ) {
        emitEvent(
            mapOf(
                "type" to "vosk_progress",
                "phase" to phase,
                "percent" to percent,
                "downloadedBytes" to downloadedBytes,
                "totalBytes" to totalBytes,
                "message" to message
            )
        )
    }

    fun dispose() {
        cancelDownloadFlag.set(true)
        stopListening(emitFinalResult = false)
        try {
            voskModel?.close()
        } catch (_: Throwable) {}
        voskModel = null
        ioExecutor.shutdownNow()
    }

    companion object {
        const val MODEL_NAME = "vosk-model-ar-mgb2-0.4"
        const val MODEL_URL = "https://alphacephei.com/vosk/models/vosk-model-ar-mgb2-0.4.zip"
        const val APPROX_DOWNLOAD_SIZE_MB = 318
        // Require at least 850 MB free (zip + extracted files safely)
        private const val MIN_REQUIRED_FREE_BYTES = 850L * 1024L * 1024L
    }
}
