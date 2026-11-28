package com.galarmenhanced.app.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager

class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val payload = intent.getStringExtra("payload") ?: return

        val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        val wakeLock = try {
            @Suppress("DEPRECATION")
            pm.newWakeLock(
                PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
                    PowerManager.ACQUIRE_CAUSES_WAKEUP or
                    PowerManager.ON_AFTER_RELEASE,
                "galarmenhanced:alarm_screen_wake"
            )
        } catch (_: Throwable) {
            pm.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "galarmenhanced:alarm_wake"
            )
        }
        wakeLock.acquire(15_000L)

        val serviceIntent = Intent(context, AlarmRingingService::class.java).apply {
            putExtra("payload", payload)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            context.startForegroundService(serviceIntent)
        } else {
            context.startService(serviceIntent)
        }
    }
}
