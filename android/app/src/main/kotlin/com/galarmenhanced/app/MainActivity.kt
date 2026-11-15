package com.galarmenhanced.app

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import androidx.core.content.FileProvider
import com.galarmenhanced.app.alarm.AlarmReceiver
import com.galarmenhanced.app.alarm.AlarmRepeatHelper
import com.galarmenhanced.app.alarm.AlarmRingingService
import com.galarmenhanced.app.voice.VoiceAssistantChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File

class MainActivity : FlutterActivity() {
    private val channelName = "com.galarmenhanced/alarm"
    private var voiceChannel: VoiceAssistantChannel? = null
    private var pendingBackupContent: String? = null
    private var pendingBackupResult: MethodChannel.Result? = null

    companion object {
        private const val REQ_SAVE_BACKUP = 2005

        fun scheduleWithAlarmManager(context: Context, payload: JSONObject): Boolean {
            val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && !am.canScheduleExactAlarms()) {
                return false
            }
            val requestCode = payload.getInt("requestCode")
            val triggerAtMillis = payload.getLong("triggerAtMillis")

            val intent = Intent(context, AlarmReceiver::class.java).apply {
                putExtra("payload", payload.toString())
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                requestCode,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val showIntent = Intent(context, MainActivity::class.java)
            val showPendingIntent = PendingIntent.getActivity(
                context,
                requestCode,
                showIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val info = AlarmManager.AlarmClockInfo(triggerAtMillis, showPendingIntent)
            am.setAlarmClock(info, pendingIntent)
            return true
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            if (ContextCompat.checkSelfPermission(
                    this,
                    Manifest.permission.POST_NOTIFICATIONS
                ) != PackageManager.PERMISSION_GRANTED
            ) {
                ActivityCompat.requestPermissions(
                    this,
                    arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                    1001
                )
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        voiceChannel = VoiceAssistantChannel(this).also { it.register(flutterEngine) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "scheduleExactAlarm" -> {
                        val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                        val ok = scheduleExactAlarm(args)
                        result.success(ok)
                    }
                    "cancelAlarm" -> {
                        val requestCode = (call.argument<Number>("requestCode"))?.toInt() ?: 0
                        val alarmId = call.argument<String>("alarmId") ?: ""
                        cancelAlarm(requestCode, alarmId)
                        result.success(true)
                    }
                    "stopRinging" -> {
                        stopService(Intent(this, AlarmRingingService::class.java))
                        result.success(true)
                    }
                    "consumeHistoryEvents" -> {
                        result.success(AlarmRepeatHelper.consumeHistoryEvents(this))
                    }
                    "canScheduleExactAlarms" -> {
                        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            am.canScheduleExactAlarms()
                        } else true
                        result.success(allowed)
                    }
                    "openExactAlarmSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            startActivity(
                                Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                            )
                        }
                        result.success(true)
                    }
                    "canUseFullScreenIntent" -> {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        val allowed = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            nm.canUseFullScreenIntent()
                        } else true
                        result.success(allowed)
                    }
                    "openFullScreenIntentSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            startActivity(
                                Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT).apply {
                                    data = Uri.parse("package:$packageName")
                                }
                            )
                        }
                        result.success(true)
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                        result.success(pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        startActivity(
                            Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                                data = Uri.parse("package:$packageName")
                            }
                        )
                        result.success(true)
                    }
                    "openAppNotificationSettings" -> {
                        startActivity(
                            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                                putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
                            }
                        )
                        result.success(true)
                    }
                    "isNotificationPolicyAccessGranted" -> {
                        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        result.success(nm.isNotificationPolicyAccessGranted)
                    }
                    "openNotificationPolicySettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                        result.success(true)
                    }
                    "saveBackupToDownloads" -> {
                        val fileName = call.argument<String>("fileName") ?: "u3m_alarms_backup.json"
                        val content = call.argument<String>("content") ?: ""
                        val savedPath = saveBackupToDownloads(fileName, content)
                        result.success(savedPath)
                    }
                    "saveBackupWithPicker" -> {
                        val fileName = call.argument<String>("fileName") ?: "u3m_alarms_backup.json"
                        val content = call.argument<String>("content") ?: ""
                        pendingBackupContent = content
                        pendingBackupResult = result
                        val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                            addCategory(Intent.CATEGORY_OPENABLE)
                            type = "application/json"
                            putExtra(Intent.EXTRA_TITLE, fileName)
                        }
                        try {
                            startActivityForResult(intent, REQ_SAVE_BACKUP)
                        } catch (_: Exception) {
                            pendingBackupContent = null
                            pendingBackupResult = null
                            result.success(false)
                        }
                    }
                    "shareBackupFile" -> {
                        val fileName = call.argument<String>("fileName") ?: "u3m_alarms_backup.json"
                        val content = call.argument<String>("content") ?: ""
                        val ok = shareBackupFile(fileName, content)
                        result.success(ok)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == REQ_SAVE_BACKUP) {
            val res = pendingBackupResult
            val content = pendingBackupContent
            pendingBackupResult = null
            pendingBackupContent = null
            if (resultCode == Activity.RESULT_OK && data?.data != null && content != null) {
                try {
                    contentResolver.openOutputStream(data.data!!)?.use { out ->
                        out.write(content.toByteArray(Charsets.UTF_8))
                    }
                    res?.success(true)
                } catch (_: Exception) {
                    res?.success(false)
                }
            } else {
                res?.success(false)
            }
        }
    }

    private fun saveBackupToDownloads(fileName: String, content: String): String? {
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val values = ContentValues().apply {
                    put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                    put(MediaStore.Downloads.MIME_TYPE, "application/json")
                    put(MediaStore.Downloads.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
                }
                val uri = contentResolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                    ?: return null
                contentResolver.openOutputStream(uri)?.use { out ->
                    out.write(content.toByteArray(Charsets.UTF_8))
                }
                "Download/$fileName"
            } else {
                @Suppress("DEPRECATION")
                val dir = Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS)
                if (!dir.exists()) dir.mkdirs()
                val file = File(dir, fileName)
                file.writeText(content, Charsets.UTF_8)
                file.absolutePath
            }
        } catch (_: Exception) {
            null
        }
    }

    private fun shareBackupFile(fileName: String, content: String): Boolean {
        return try {
            val backupDir = File(cacheDir, "backups").apply { mkdirs() }
            val file = File(backupDir, fileName)
            file.writeText(content, Charsets.UTF_8)
            val uri = FileProvider.getUriForFile(
                this,
                "$packageName.fileprovider",
                file
            )
            val shareIntent = Intent(Intent.ACTION_SEND).apply {
                type = "application/json"
                putExtra(Intent.EXTRA_STREAM, uri)
                putExtra(Intent.EXTRA_SUBJECT, "U3m Alarm Backup")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            }
            startActivity(Intent.createChooser(shareIntent, "Share Backup"))
            true
        } catch (_: Exception) {
            false
        }
    }

    override fun onDestroy() {
        voiceChannel?.dispose()
        voiceChannel = null
        super.onDestroy()
    }

    private fun scheduleExactAlarm(args: Map<*, *>): Boolean {
        val requestCode = (args["requestCode"] as? Number)?.toInt() ?: return false
        val alarmId = args["alarmId"] as? String ?: return false
        val title = args["title"] as? String ?: "Alarm"
        val notes = args["notes"] as? String ?: ""
        val triggerAtMillis = (args["triggerAtMillis"] as? Number)?.toLong() ?: return false
        val ringtoneUri = args["ringtoneUri"] as? String ?: "default"
        val volume = (args["volume"] as? Number)?.toFloat() ?: 0.85f
        val gradualVolume = args["gradualVolume"] as? Boolean ?: true
        val vibrate = args["vibrate"] as? Boolean ?: true
        val ringOnVibrateSilent = args["ringOnVibrateSilent"] as? Boolean ?: true
        val ringDurationSeconds = (args["ringDurationSeconds"] as? Number)?.toInt() ?: 0
        val snoozeDurationMinutes = (args["snoozeDurationMinutes"] as? Number)?.toInt() ?: 5
        val maxSnoozeCount = (args["maxSnoozeCount"] as? Number)?.toInt() ?: 3
        val currentSnoozeCount = (args["currentSnoozeCount"] as? Number)?.toInt() ?: 0
        val repeatRuleJson = args["repeatRuleJson"] as? String ?: ""
        val creatorTimezoneId = args["creatorTimezoneId"] as? String ?: "UTC"
        val startAtMillis = (args["startAtMillis"] as? Number)?.toLong() ?: triggerAtMillis
        val occurrenceCount = (args["occurrenceCount"] as? Number)?.toInt() ?: 0

        // Persist alarm metadata so BootCompletedReceiver can reschedule after reboot/timezone change
        val prefs = getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
        val payload = JSONObject().apply {
            put("requestCode", requestCode)
            put("alarmId", alarmId)
            put("title", title)
            put("notes", notes)
            put("triggerAtMillis", triggerAtMillis)
            put("ringtoneUri", ringtoneUri)
            put("volume", volume.toDouble())
            put("gradualVolume", gradualVolume)
            put("vibrate", vibrate)
            put("ringOnVibrateSilent", ringOnVibrateSilent)
            put("ringDurationSeconds", ringDurationSeconds)
            put("snoozeDurationMinutes", snoozeDurationMinutes)
            put("maxSnoozeCount", maxSnoozeCount)
            put("currentSnoozeCount", currentSnoozeCount)
            put("repeatRuleJson", repeatRuleJson)
            put("creatorTimezoneId", creatorTimezoneId)
            put("startAtMillis", startAtMillis)
            put("occurrenceCount", occurrenceCount)
        }
        prefs.edit().putString("alarm_$alarmId", payload.toString()).apply()

        return scheduleWithAlarmManager(this, payload)
    }

    private fun cancelAlarm(requestCode: Int, alarmId: String) {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val intent = Intent(this, AlarmReceiver::class.java)
        val pi = PendingIntent.getBroadcast(
            this,
            requestCode,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        am.cancel(pi)
        getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
            .edit()
            .remove("alarm_$alarmId")
            .apply()
    }
}
