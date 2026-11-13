package com.galarmenhanced.app.alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
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

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        if (action == ACTION_DISMISS || action == ACTION_DONE) {
            stopSelf()
            return START_NOT_STICKY
        }

        val payloadRaw = intent?.getStringExtra("payload") ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        val payload = JSONObject(payloadRaw)
        val title = payload.optString("title", "Alarm")
        val ringtoneUri = payload.optString("ringtoneUri", "default")
        val targetVolume = payload.optDouble("volume", 0.85).toFloat().coerceIn(0.05f, 1.0f)
        val gradualVolume = payload.optBoolean("gradualVolume", true)
        val vibrate = payload.optBoolean("vibrate", true)
        val ringOnVibrateSilent = payload.optBoolean("ringOnVibrateSilent", true)
        val ringDurationSeconds = payload.optInt("ringDurationSeconds", 0)
        val snoozeDurationMinutes = payload.optInt("snoozeDurationMinutes", 5)

        startForegroundWithNotification(title, payloadRaw)
        startAlarmAudio(ringtoneUri, targetVolume, gradualVolume, ringOnVibrateSilent)
        if (vibrate) startVibration()

        // Launch full-screen lock-screen AlarmActivity
        val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            putExtra("payload", payloadRaw)
        }
        startActivity(fullScreenIntent)

        // Optional ring duration auto-snooze
        if (ringDurationSeconds > 0) {
            handler.postDelayed({
                val snoozedNext = System.currentTimeMillis() + (snoozeDurationMinutes * 60_000L)
                payload.put("triggerAtMillis", snoozedNext)
                payload.put("currentSnoozeCount", payload.optInt("currentSnoozeCount", 0) + 1)
                MainActivity.scheduleWithAlarmManager(this, payload)
                stopSelf()
            }, ringDurationSeconds * 1000L)
        }

        return START_NOT_STICKY
    }

    private fun startForegroundWithNotification(title: String, payloadRaw: String) {
        val channelId = "galarm_ringing_channel"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Active Alarms",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setSound(null, null)
                enableVibration(false)
            }
            nm.createNotificationChannel(channel)
        }

        val fullScreenIntent = Intent(this, AlarmActivity::class.java).apply {
            putExtra("payload", payloadRaw)
        }
        val fullScreenPi = PendingIntent.getActivity(
            this,
            9001,
            fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val dismissIntent = Intent(this, AlarmRingingService::class.java).apply {
            action = ACTION_DISMISS
        }
        val dismissPi = PendingIntent.getService(
            this,
            9002,
            dismissIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle(title)
            .setContentText("Tap to open alarm")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setOngoing(true)
            .setFullScreenIntent(fullScreenPi, true)
            .addAction(0, "Dismiss", dismissPi)
            .build()

        startForeground(1001, notification)
    }

    private fun startAlarmAudio(
        ringtoneUri: String,
        targetVolume: Float,
        gradual: Boolean,
        ringOnVibrateSilent: Boolean
    ) {
        try {
            val uri: Uri = when (ringtoneUri) {
                "default", "chime", "radar", "" ->
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)
                        ?: RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                else -> Uri.parse(ringtoneUri)
            }

            val usage = if (ringOnVibrateSilent) {
                AudioAttributes.USAGE_ALARM
            } else {
                AudioAttributes.USAGE_NOTIFICATION_RINGTONE
            }

            mediaPlayer = MediaPlayer().apply {
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
        } catch (_: Exception) {
            // Fallback: ensure service continues even if custom URI is unavailable
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
    }
}
