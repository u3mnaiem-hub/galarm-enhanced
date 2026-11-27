package com.galarmenhanced.app.alarm

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import com.galarmenhanced.app.MainActivity
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors

/**
 * Crash-free background receiver that periodically polls Firestore's REST API
 * for incoming buddy/group alarms using AlarmManager (no long-running ForegroundService,
 * so it never triggers Android 14/15 dataSync FGS crashes or timeouts).
 */
class SharedAlarmSyncReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val pendingResult = goAsync()
        val appContext = context.applicationContext
        executor.execute {
            try {
                pollSharedAlarmsSafe(appContext)
            } catch (_: Throwable) {
                // Never crash on network/parse issues
            } finally {
                try {
                    scheduleNextPoll(appContext, POLL_INTERVAL_MS)
                } catch (_: Throwable) {
                }
                try {
                    pendingResult.finish()
                } catch (_: Throwable) {
                }
            }
        }
    }

    private fun pollSharedAlarmsSafe(context: Context) {
        val prefs = context.getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
        val projectId = prefs.getString("sync_project_id", "") ?: ""
        val uid = prefs.getString("sync_uid", "") ?: ""
        val phone = prefs.getString("sync_phone", "") ?: ""
        val idToken = prefs.getString("sync_id_token", "") ?: ""

        if (projectId.isBlank() || (uid.isBlank() && phone.isBlank())) return

        val docs = mutableListOf<JSONObject>()
        if (phone.isNotBlank()) {
            docs.addAll(runFirestoreArrayContainsQuery(projectId, idToken, "participantPhones", phone))
        }
        if (uid.isNotBlank() && uid != "local_user") {
            docs.addAll(runFirestoreArrayContainsQuery(projectId, idToken, "participantUids", uid))
        }

        val now = System.currentTimeMillis()
        for (doc in docs) {
            processFirestoreAlarmDoc(context, doc, uid, now, prefs)
        }
    }

    private fun runFirestoreArrayContainsQuery(
        projectId: String,
        idToken: String,
        fieldPath: String,
        value: String
    ): List<JSONObject> {
        val url = URL(
            "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents:runQuery"
        )
        val body = JSONObject().apply {
            put("structuredQuery", JSONObject().apply {
                put("from", JSONArray().put(JSONObject().put("collectionId", "alarms")))
                put("where", JSONObject().apply {
                    put("fieldFilter", JSONObject().apply {
                        put("field", JSONObject().put("fieldPath", fieldPath))
                        put("op", "ARRAY_CONTAINS")
                        put("value", JSONObject().put("stringValue", value))
                    })
                })
            })
        }

        val response = postJson(url, body.toString(), idToken)
            ?: if (idToken.isNotBlank()) postJson(url, body.toString(), "") else null
            ?: return emptyList()

        val results = mutableListOf<JSONObject>()
        try {
            val arr = JSONArray(response)
            for (i in 0 until arr.length()) {
                val item = arr.optJSONObject(i) ?: continue
                val doc = item.optJSONObject("document") ?: continue
                results.add(doc)
            }
        } catch (_: Exception) {
        }
        return results
    }

    private fun postJson(url: URL, payload: String, bearerToken: String): String? {
        var conn: HttpURLConnection? = null
        return try {
            conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                connectTimeout = 6_000
                readTimeout = 6_000
                doOutput = true
                setRequestProperty("Content-Type", "application/json; charset=UTF-8")
                if (bearerToken.isNotBlank()) {
                    setRequestProperty("Authorization", "Bearer $bearerToken")
                }
            }
            OutputStreamWriter(conn.outputStream, Charsets.UTF_8).use { it.write(payload) }
            val code = conn.responseCode
            if (code in 200..299) {
                BufferedReader(InputStreamReader(conn.inputStream, Charsets.UTF_8)).use { it.readText() }
            } else {
                null
            }
        } catch (_: Exception) {
            null
        } finally {
            conn?.disconnect()
        }
    }

    private fun processFirestoreAlarmDoc(
        context: Context,
        doc: JSONObject,
        myUid: String,
        now: Long,
        prefs: android.content.SharedPreferences
    ) {
        val fields = doc.optJSONObject("fields") ?: return
        val docName = doc.optString("name", "")
        val alarmId = getStringField(fields, "id").ifBlank {
            docName.substringAfterLast('/')
        }
        if (alarmId.isBlank()) return

        val ownerId = getStringField(fields, "ownerId")
        if (ownerId.isNotBlank() && ownerId == myUid) return

        val isEnabled = getBoolField(fields, "isEnabled", true)
        if (!isEnabled) return

        val startAtMillis = getLongField(fields, "startAtMillis", 0L)
        if (startAtMillis <= 0L) return

        // Skip old past alarms (> 5 minutes in the past)
        if (startAtMillis < now - 300_000L) return

        // Avoid re-scheduling the exact same alarm occurrence repeatedly
        val lastScheduledStart = prefs.getLong("synced_shared_$alarmId", -1L)
        if (lastScheduledStart == startAtMillis) return

        val triggerAtMillis = if (startAtMillis <= now) now + 1_500L else startAtMillis
        val title = getStringField(fields, "title").ifBlank { "Shared Alarm" }
        val notes = getStringField(fields, "notes")
        val volume = getDoubleField(fields, "volume", 0.85)
        val gradualVolume = getBoolField(fields, "gradualVolume", true)
        val vibrate = getBoolField(fields, "vibrate", true)
        val ringOnVibrateSilent = getBoolField(fields, "ringOnVibrateSilent", true)
        val repeatRuleJson = getStringField(fields, "repeatRuleJson")
        val tz = getStringField(fields, "tz").ifBlank { "Africa/Cairo" }

        val snoozeFields = fields.optJSONObject("snoozeConfig")
            ?.optJSONObject("mapValue")
            ?.optJSONObject("fields")
        val snoozeDurationMinutes = if (snoozeFields != null) {
            getLongField(snoozeFields, "snoozeDurationMinutes", 5L).toInt()
        } else 5
        val maxSnoozeCount = if (snoozeFields != null) {
            getLongField(snoozeFields, "maxSnoozeCount", 3L).toInt()
        } else 3
        val ringDurationSeconds = if (snoozeFields != null) {
            getLongField(snoozeFields, "ringDurationSeconds", 0L).toInt()
        } else 0

        val requestCode = alarmId.hashCode()
        val payload = JSONObject().apply {
            put("requestCode", requestCode)
            put("alarmId", alarmId)
            put("title", title)
            put("notes", notes)
            put("triggerAtMillis", triggerAtMillis)
            put("ringtoneUri", "default")
            put("volume", volume)
            put("gradualVolume", gradualVolume)
            put("vibrate", vibrate)
            put("ringOnVibrateSilent", ringOnVibrateSilent)
            put("ringDurationSeconds", ringDurationSeconds)
            put("snoozeDurationMinutes", snoozeDurationMinutes)
            put("maxSnoozeCount", maxSnoozeCount)
            put("currentSnoozeCount", 0)
            put("repeatRuleJson", repeatRuleJson)
            put("creatorTimezoneId", tz)
            put("startAtMillis", startAtMillis)
            put("occurrenceCount", 0)
        }

        prefs.edit()
            .putString("alarm_$alarmId", payload.toString())
            .putLong("synced_shared_$alarmId", startAtMillis)
            .apply()

        if (triggerAtMillis <= System.currentTimeMillis() + 3_000L) {
            // Due right now (or just passed due to minor delay) — ring immediately!
            try {
                val ringIntent = Intent(context, AlarmRingingService::class.java).apply {
                    putExtra("payload", payload.toString())
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(ringIntent)
                } else {
                    context.startService(ringIntent)
                }
            } catch (_: Throwable) {
                MainActivity.scheduleWithAlarmManager(context, payload)
            }
        } else {
            MainActivity.scheduleWithAlarmManager(context, payload)
        }
    }

    private fun getStringField(fields: JSONObject, key: String): String {
        return fields.optJSONObject(key)?.optString("stringValue", "") ?: ""
    }

    private fun getBoolField(fields: JSONObject, key: String, defaultValue: Boolean): Boolean {
        val obj = fields.optJSONObject(key) ?: return defaultValue
        return if (obj.has("booleanValue")) obj.optBoolean("booleanValue", defaultValue) else defaultValue
    }

    private fun getLongField(fields: JSONObject, key: String, defaultValue: Long): Long {
        val obj = fields.optJSONObject(key) ?: return defaultValue
        if (obj.has("integerValue")) {
            return obj.optString("integerValue", "").toLongOrNull() ?: defaultValue
        }
        if (obj.has("doubleValue")) {
            return obj.optDouble("doubleValue", defaultValue.toDouble()).toLong()
        }
        return defaultValue
    }

    private fun getDoubleField(fields: JSONObject, key: String, defaultValue: Double): Double {
        val obj = fields.optJSONObject(key) ?: return defaultValue
        if (obj.has("doubleValue")) return obj.optDouble("doubleValue", defaultValue)
        if (obj.has("integerValue")) {
            return obj.optString("integerValue", "").toDoubleOrNull() ?: defaultValue
        }
        return defaultValue
    }

    companion object {
        private const val POLL_REQUEST_CODE = 42099
        private const val POLL_INTERVAL_MS = 15_000L
        private val executor = Executors.newSingleThreadExecutor()

        fun startPolling(context: Context) {
            val prefs = context.getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
            val projectId = prefs.getString("sync_project_id", "") ?: ""
            val uid = prefs.getString("sync_uid", "") ?: ""
            val phone = prefs.getString("sync_phone", "") ?: ""
            if (projectId.isBlank() || (uid.isBlank() && phone.isBlank())) return

            // Schedule first poll immediately (2s), then repeat every 15s using exact allow-while-idle
            scheduleNextPoll(context.applicationContext, 2_000L)
        }

        private fun scheduleNextPoll(context: Context, delayMs: Long) {
            val prefs = context.getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
            val projectId = prefs.getString("sync_project_id", "") ?: ""
            val uid = prefs.getString("sync_uid", "") ?: ""
            val phone = prefs.getString("sync_phone", "") ?: ""
            if (projectId.isBlank() || (uid.isBlank() && phone.isBlank())) return

            val am = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
            val intent = Intent(context, SharedAlarmSyncReceiver::class.java)
            val pi = PendingIntent.getBroadcast(
                context,
                POLL_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            val triggerAt = System.currentTimeMillis() + delayMs
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                } else {
                    am.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                }
            } catch (_: SecurityException) {
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                    } else {
                        am.set(AlarmManager.RTC_WAKEUP, triggerAt, pi)
                    }
                } catch (_: Throwable) {
                }
            } catch (_: Throwable) {
            }
        }
    }
}
