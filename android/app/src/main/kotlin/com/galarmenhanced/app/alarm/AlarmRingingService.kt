package com.galarmenhanced.app.alarm

import android.app.ActivityOptions
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import androidx.core.app.NotificationCompat
import com.galarmenhanced.app.MainActivity
import org.json.JSONObject

class AlarmRingingService : Service() {
    private var mediaPlayer: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private val handler = Handler(Looper.getMainLooper())
    private var volumeStep = 0.1f
    private var currentPayloadRaw: String? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_DISMISS || action == ACTION_DONE) {
            val raw = intent.getStringExtra("payload") ?: currentPayloadRaw
            if (raw != null) {
                try {
                    val p = JSONObject(raw)
                    AlarmRepeatHelper.recordHistoryEvent(
                        this,
                        p,
                        "done",
                        System.currentTimeMillis()
                    )
                    AlarmRepeatHelper.scheduleNextRepeatIfNeeded(this, p)
                } catch (_: Exception) {}
            }
            sendBroadcast(Intent(ACTION_CLOSE_ACTIVITY).setPackage(packageName))
            stopSelf()
            return START_NOT_STICKY
        }
        if (action == ACTION_SNOOZE) {
            val raw = intent.getStringExtra("payload") ?: currentPayloadRaw
            if (raw != null) {
                try {
                    val p = JSONObject(raw)
                    val nextSnoozeCount = p.optInt("currentSnoozeCount", 0) + 1
                    val maxSnoozeCount = p.optInt("maxSnoozeCount", 3)
                    if (nextSnoozeCount > maxSnoozeCount) {
                        AlarmRepeatHelper.recordHistoryEvent(this, p, "missed", null)
                        AlarmRepeatHelper.scheduleNextRepeatIfNeeded(this, p)
                    } else {
                        val snoozeMin = p.optInt("snoozeDurationMinutes", 5)
                        val nextTrigger = System.currentTimeMillis() + (snoozeMin * 60_000L)
                        p.put("triggerAtMillis", nextTrigger)
                        p.put("currentSnoozeCount", nextSnoozeCount)
                        val alarmId = p.optString("alarmId", "")
                        if (alarmId.isNotBlank()) {
                            getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
                                .edit()
                                .putString("alarm_$alarmId", p.toString())
                                .apply()
                        }
                        MainActivity.scheduleWithAlarmManager(this, p)
                    }
                } catch (_: Exception) {}
            }
            sendBroadcast(Intent(ACTION_CLOSE_ACTIVITY).setPackage(packageName))
            stopSelf()
            return START_NOT_STICKY
        }

        val payloadRaw = intent?.getStringExtra("payload") ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        currentPayloadRaw = payloadRaw
        val payload = JSONObject(payloadRaw)
        val title = payload.optString("title", "Alarm").ifBlank { "Alarm" }
        val notes = payload.optString("notes", "")
        val ringtoneUri = payload.optString("ringtoneUri", "default")
        val targetVolume = payload.optDouble("volume", 0.85).toFloat().coerceIn(0.05f, 1.0f)
        val gradualVolume = payload.optBoolean("gradualVolume", true)
        val vibrate = payload.optBoolean("vibrate", true)
        val ringOnVibrateSilent = payload.optBoolean("ringOnVibrateSilent", true)
        val ringDurationSeconds = payload.optInt("ringDurationSeconds", 0)
        val snoozeDurationMinutes = payload.optInt("snoozeDurationMinutes", 5)

        startForegroundWithNotification(title, notes, snoozeDurationMinutes, payloadRaw)
        startAlarmAudio(ringtoneUri, targetVolume, gradualVolume, ringOnVibrateSilent)
        if (vibrate) startVibration()

        // Launch full-screen lock-screen AlarmActivity
        try {
            val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
                putExtra("payload", payloadRaw)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                val opts = ActivityOptions.makeBasic()
                    .setPendingIntentBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED
                    )
                    .toBundle()
                val reqCode = payload.optString("alarmId", "alarm").hashCode()
                val pi = PendingIntent.getActivity(
                    this,
                    reqCode,
                    fullScreenIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                pi.send(this, 0, null, null, null, null, opts)
            } else {
                startActivity(fullScreenIntent)
            }
        } catch (_: Throwable) {
            try {
                val fallbackIntent = Intent(this, AlarmActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                    putExtra("payload", payloadRaw)
                }
                startActivity(fallbackIntent)
            } catch (_: Throwable) {
                // System will display the high-priority heads-up / fullScreenIntent notification
            }
        }

        // Optional ring duration auto-snooze
        if (ringDurationSeconds > 0) {
            handler.postDelayed({
                val nextSnoozeCount = payload.optInt("currentSnoozeCount", 0) + 1
                val maxSnoozeCount = payload.optInt("maxSnoozeCount", 3)
                if (nextSnoozeCount > maxSnoozeCount) {
                    AlarmRepeatHelper.recordHistoryEvent(this, payload, "missed", null)
                    AlarmRepeatHelper.scheduleNextRepeatIfNeeded(this, payload)
                } else {
                    val snoozedNext = System.currentTimeMillis() + (snoozeDurationMinutes * 60_000L)
                    payload.put("triggerAtMillis", snoozedNext)
                    payload.put("currentSnoozeCount", nextSnoozeCount)
                    val alarmId = payload.optString("alarmId", "")
                    if (alarmId.isNotBlank()) {
                        getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
                            .edit()
                            .putString("alarm_$alarmId", payload.toString())
                            .apply()
                    }
                    MainActivity.scheduleWithAlarmManager(this, payload)
                }
                sendBroadcast(Intent(ACTION_CLOSE_ACTIVITY).setPackage(packageName))
                stopSelf()
            }, ringDurationSeconds * 1000L)
        }

        return START_NOT_STICKY
    }

    private fun startForegroundWithNotification(
        title: String,
        notes: String,
        snoozeMinutes: Int,
        payloadRaw: String
    ) {
        val channelId = "u3m_alarm_ringing_channel_v2"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "U3m Alarm Alerts",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Full-screen and heads-up alarm ringing notifications"
                setSound(null, null)
                enableVibration(false)
                setBypassDnd(true)
                lockscreenVisibility = android.app.Notification.VISIBILITY_PUBLIC
            }
            nm.createNotificationChannel(channel)
        }

        val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("payload", payloadRaw)
        }
        val fullScreenPi = PendingIntent.getActivity(
            this,
            9001,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val doneIntent = Intent(this, AlarmRingingService::class.java).apply {
            action = ACTION_DONE
            putExtra("payload", payloadRaw)
        }
        val donePi = PendingIntent.getService(
            this,
            9002,
            doneIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val snoozeIntent = Intent(this, AlarmRingingService::class.java).apply {
            action = ACTION_SNOOZE
            putExtra("payload", payloadRaw)
        }
        val snoozePi = PendingIntent.getService(
            this,
            9003,
            snoozeIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val bodyText = if (notes.isNotBlank()) notes else "Alarm is ringing — tap Stop/Done or Snooze"

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText(bodyText)
            .setStyle(
                NotificationCompat.BigTextStyle()
                    .setBigContentTitle(title)
                    .bigText(bodyText)
            )
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setDefaults(NotificationCompat.DEFAULT_LIGHTS)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(fullScreenPi)
            .setFullScreenIntent(fullScreenPi, true)
            .addAction(android.R.drawable.ic_media_pause, "Stop / Done", donePi)
            .addAction(android.R.drawable.ic_popup_reminder, "Snooze (${snoozeMinutes}m)", snoozePi)
            .build()

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    1001,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK
                )
            } else {
                startForeground(1001, notification)
            }
        } catch (_: Throwable) {
            try {
                startForeground(1001, notification)
            } catch (_: Throwable) {
            }
        }
    }

    private fun startAlarmAudio(
        ringtoneUri: String,
        targetVolume: Float,
        gradual: Boolean,
        ringOnVibrateSilent: Boolean
    ) {
        val candidates = mutableListOf<Uri>()
        val alarmUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
        val ringtoneDefaultUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE)
        val notifUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)

        if (ringtoneUri.isNotBlank() &&
            ringtoneUri != "default" &&
            ringtoneUri != "chime" &&
            ringtoneUri != "radar"
        ) {
            if (ringtoneUri.startsWith("/")) {
                val f = java.io.File(ringtoneUri)
                if (f.exists()) candidates.add(Uri.fromFile(f))
            } else {
                try {
                    candidates.add(Uri.parse(ringtoneUri))
                } catch (_: Exception) {
                }
            }
        }
        if (alarmUri != null) candidates.add(alarmUri)
        if (ringtoneDefaultUri != null) candidates.add(ringtoneDefaultUri)
        if (notifUri != null) candidates.add(notifUri)

        val usage = if (ringOnVibrateSilent) {
            AudioAttributes.USAGE_ALARM
        } else {
            AudioAttributes.USAGE_NOTIFICATION_RINGTONE
        }

        for (uri in candidates) {
            var player: MediaPlayer? = null
            try {
                player = MediaPlayer().apply {
                    setAudioAttributes(
                        AudioAttributes.Builder()
                            .setUsage(usage)
                            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                            .build()
                    )
                    setDataSource(this@AlarmRingingService, uri)
                    isLooping = true
                    prepare()
                    val initialVol = if (gradual) 0.1f else targetVolume
                    setVolume(initialVol, initialVol)
                    start()
                }
                mediaPlayer = player
                if (gradual) {
                    volumeStep = 0.1f
                    val rampRunnable = object : Runnable {
                        override fun run() {
                            volumeStep = (volumeStep + 0.1f).coerceAtMost(targetVolume)
                            mediaPlayer?.setVolume(volumeStep, volumeStep)
                            if (volumeStep < targetVolume) {
                                handler.postDelayed(this, 1500L)
                            }
                        }
                    }
                    handler.postDelayed(rampRunnable, 1500L)
                }
                return
            } catch (_: Exception) {
                try {
                    player?.release()
                } catch (_: Exception) {
                }
            }
        }
    }

    private fun startVibration() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vm = getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vm.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        val pattern = longArrayOf(0, 600, 400, 600, 400)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            vibrator?.vibrate(VibrationEffect.createWaveform(pattern, 0))
        } else {
            @Suppress("DEPRECATION")
            vibrator?.vibrate(pattern, 0)
        }
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        mediaPlayer?.stop()
        mediaPlayer?.release()
        mediaPlayer = null
        vibrator?.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        const val ACTION_DISMISS = "com.galarmenhanced.app.ACTION_DISMISS"
        const val ACTION_DONE = "com.galarmenhanced.app.ACTION_DONE"
        const val ACTION_SNOOZE = "com.galarmenhanced.app.ACTION_SNOOZE"
        const val ACTION_CLOSE_ACTIVITY = "com.galarmenhanced.app.ACTION_CLOSE_ACTIVITY"
    }
}
