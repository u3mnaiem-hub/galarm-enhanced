package com.galarmenhanced.app

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import com.galarmenhanced.app.alarm.AlarmReceiver
import com.galarmenhanced.app.alarm.AlarmRingingService
import com.galarmenhanced.app.voice.VoiceAssistantChannel
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private val channelName = "com.galarmenhanced/alarm"
    private var voiceChannel: VoiceAssistantChannel? = null

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
                    else -> result.notImplemented()
                }
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

    companion object {
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
}
