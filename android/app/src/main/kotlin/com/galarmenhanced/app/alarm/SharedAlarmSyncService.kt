package com.galarmenhanced.app.alarm

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.galarmenhanced.app.MainActivity
import org.json.JSONArray
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URL
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.TimeUnit

/**
 * Lightweight background foreground-service that polls Firestore's REST API every 15 seconds
 * for incoming buddy/group alarms and schedules them directly with Android AlarmManager.
 *
 * This guarantees shared alarms ring reliably on the recipient's phone even when the app is
 * closed, the screen is locked, and Firebase is on the free Spark plan (no Cloud Functions).
 */
class SharedAlarmSyncService : Service() {
    private var executor: ScheduledExecutorService? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForegroundSilent()

        val prefs = getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
        val projectId = prefs.getString("sync_project_id", "") ?: ""
        val uid = prefs.getString("sync_uid", "") ?: ""
        val phone = prefs.getString("sync_phone", "") ?: ""

        if (projectId.isBlank() || (uid.isBlank() && phone.isBlank())) {
            stopSelf()
            return START_NOT_STICKY
        }

        if (executor == null || executor!!.isShutdown) {
            executor = Executors.newSingleThreadScheduledExecutor()
            executor?.scheduleWithFixedDelay(
                { pollSharedAlarmsSafe() },
                0L,
                15L,
                TimeUnit.SECONDS
            )
        } else {
            executor?.execute { pollSharedAlarmsSafe() }
        }

        return START_STICKY
    }

    private fun startForegroundSilent() {
        val channelId = "u3m_shared_alarm_sync_channel"
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "Buddy & Group Alarm Sync",
                NotificationManager.IMPORTANCE_MIN
            ).apply {
                description = "Keeps buddy and group alarms synced while the screen is locked"
                setSound(null, null)
                enableVibration(false)
                setShowBadge(false)
            }
            nm.createNotificationChannel(channel)
        }

        val openIntent = Intent(this, MainActivity::class.java)
        val openPi = PendingIntent.getActivity(
            this,
            2002,
            openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(android.R.drawable.ic_lock_idle_alarm)
            .setContentTitle("U3m Alarm")
            .setContentText("Ready to receive buddy & group alarms")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(openPi)
            .build()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                2002,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            )
        } else {
            startForeground(2002, notification)
        }
    }

    private fun pollSharedAlarmsSafe() {
        try {
            val prefs = getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
            val projectId = prefs.getString("sync_project_id", "") ?: ""
            val uid = prefs.getString("sync_uid", "") ?: ""
            val phone = prefs.getString("sync_phone", "") ?: ""
            val idToken = prefs.getString("sync_id_token", "") ?: ""

            if (projectId.isBlank()) return

            val docs = mutableListOf<JSONObject>()
            if (phone.isNotBlank()) {
                docs.addAll(runFirestoreArrayContainsQuery(projectId, idToken, "participantPhones", phone))
            }
            if (uid.isNotBlank() && uid != "local_user") {
                docs.addAll(runFirestoreArrayContainsQuery(projectId, idToken, "participantUids", uid))
            }

            val now = System.currentTimeMillis()
            for (doc in docs) {
                processFirestoreAlarmDoc(doc, uid, now, prefs)
            }
        } catch (_: Exception) {
            // Network offline or transient error — will retry in 15 seconds
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
                connectTimeout = 8_000
                readTimeout = 8_000
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

        // Skip old past alarms (> 2 minutes in the past)
        if (startAtMillis < now - 120_000L) return

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

        if (triggerAtMillis <= System.currentTimeMillis() + 2_500L) {
            // Due right now (or within 2.5s) — ring immediately!
            val ringIntent = Intent(this, AlarmRingingService::class.java).apply {
                putExtra("payload", payload.toString())
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                startForegroundService(ringIntent)
            } else {
                startService(ringIntent)
            }
        } else {
            MainActivity.scheduleWithAlarmManager(this, payload)
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

    override fun onDestroy() {
        executor?.shutdownNow()
        executor = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    companion object {
        fun startIfConfigured(context: Context) {
            val prefs = context.getSharedPreferences("galarm_native_store", Context.MODE_PRIVATE)
            val projectId = prefs.getString("sync_project_id", "") ?: ""
            val uid = prefs.getString("sync_uid", "") ?: ""
            val phone = prefs.getString("sync_phone", "") ?: ""
            if (projectId.isBlank() || (uid.isBlank() && phone.isBlank())) return

            val intent = Intent(context, SharedAlarmSyncService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (_: Exception) {
            }
        }
    }
}
