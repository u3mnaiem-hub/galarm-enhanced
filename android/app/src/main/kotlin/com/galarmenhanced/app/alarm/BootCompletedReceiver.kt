package com.galarmenhanced.app.alarm

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import com.galarmenhanced.app.MainActivity
import org.json.JSONObject

class BootCompletedReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action == Intent.ACTION_BOOT_COMPLETED ||
            action == Intent.ACTION_LOCKED_BOOT_COMPLETED ||
            action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            action == Intent.ACTION_TIMEZONE_CHANGED ||
            action == Intent.ACTION_TIME_SET
        ) {
            val prefs = context.getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
            val now = System.currentTimeMillis()
            for ((key, value) in prefs.all) {
                if (!key.startsWith("alarm_") || value !is String) continue
                try {
                    val payload = JSONObject(value)
                    val triggerAt = payload.optLong("triggerAtMillis", 0L)
                    if (triggerAt > now) {
                        MainActivity.scheduleWithAlarmManager(context, payload)
                    }
                } catch (_: Exception) {
                    // Skip malformed entry
                }
            }
        }
    }
}
