package com.galarmenhanced.app.alarm

import android.content.Context
import com.galarmenhanced.app.MainActivity
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale
import java.util.TimeZone

object AlarmRepeatHelper {
    private const val PREFS_NAME = "galarm_native_store"
    private const val KEY_PENDING_HISTORY = "pending_history_events"

    fun recordHistoryEvent(
        context: Context,
        payload: JSONObject,
        state: String,
        acknowledgedAtMillis: Long?
    ) {
        val alarmId = payload.optString("alarmId", "")
        if (alarmId.isBlank()) return

        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING_HISTORY, "[]") ?: "[]"
        val arr = try {
            JSONArray(raw)
        } catch (_: Exception) {
            JSONArray()
        }

        val event = JSONObject().apply {
            put("alarmId", alarmId)
            put("occurrenceIndex", payload.optInt("occurrenceCount", 0) + 1)
            put("scheduledAtMillis", payload.optLong("triggerAtMillis", System.currentTimeMillis()))
            put("state", state)
            put("snoozeCount", payload.optInt("currentSnoozeCount", 0))
            if (acknowledgedAtMillis != null) {
                put("acknowledgedAtMillis", acknowledgedAtMillis)
            }
        }
        arr.put(event)
        prefs.edit().putString(KEY_PENDING_HISTORY, arr.toString()).apply()
    }

    fun consumeHistoryEvents(context: Context): String {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val raw = prefs.getString(KEY_PENDING_HISTORY, "[]") ?: "[]"
        prefs.edit().remove(KEY_PENDING_HISTORY).apply()
        return raw
    }

    fun scheduleNextRepeatIfNeeded(context: Context, payload: JSONObject): Boolean {
        val alarmId = payload.optString("alarmId", "")
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

        val repeatRaw = payload.optString("repeatRuleJson", "")
        if (repeatRaw.isBlank()) {
            if (alarmId.isNotBlank()) prefs.edit().remove("alarm_$alarmId").apply()
            return false
        }

        val rule = try {
            JSONObject(repeatRaw)
        } catch (_: Exception) {
            if (alarmId.isNotBlank()) prefs.edit().remove("alarm_$alarmId").apply()
            return false
        }

        val frequency = rule.optString("frequency", "none")
        if (frequency == "none" || frequency.isBlank()) {
            if (alarmId.isNotBlank()) prefs.edit().remove("alarm_$alarmId").apply()
            return false
        }

        val nextMillis = computeNextTriggerMillis(payload, rule)
        if (nextMillis == null) {
            if (alarmId.isNotBlank()) prefs.edit().remove("alarm_$alarmId").apply()
            return false
        }

        val updated = JSONObject(payload.toString()).apply {
            put("triggerAtMillis", nextMillis)
            put("currentSnoozeCount", 0)
            put("occurrenceCount", payload.optInt("occurrenceCount", 0) + 1)
        }
        if (alarmId.isNotBlank()) {
            prefs.edit().putString("alarm_$alarmId", updated.toString()).apply()
        }
        return MainActivity.scheduleWithAlarmManager(context, updated)
    }

    private fun computeNextTriggerMillis(payload: JSONObject, rule: JSONObject): Long? {
        val now = System.currentTimeMillis()
        val timezoneId = payload.optString("creatorTimezoneId", "UTC").ifBlank { "UTC" }
        val tz = TimeZone.getTimeZone(timezoneId)

        val startAtMillis = payload.optLong("startAtMillis", 0L)
        val triggerAtMillis = payload.optLong("triggerAtMillis", now)
        var candidateMillis = if (startAtMillis > 0L) startAtMillis else triggerAtMillis

        val frequency = rule.optString("frequency", "none")
        val interval = rule.optInt("interval", 1).coerceAtLeast(1)
        val customUnit = rule.optString("customUnit", "days")
        val customPreset = rule.optString("customPreset", "")
        val lastDayOfMonth = rule.optBoolean("lastDayOfMonth", false)
        val nthWeekday = if (rule.isNull("nthWeekday")) null else rule.optInt("nthWeekday")
        val dayOfMonth = if (rule.isNull("dayOfMonth")) null else rule.optInt("dayOfMonth")
        val maxOccurrences = if (rule.isNull("maxOccurrences")) null else rule.optInt("maxOccurrences")
        val endDateMillis = parseIsoUtcMillis(rule.optString("endDateUtc", ""))

        val weekdaysArr = rule.optJSONArray("weekdays")
        val weekdays = mutableListOf<Int>()
        if (weekdaysArr != null) {
            for (i in 0 until weekdaysArr.length()) {
                weekdays.add(weekdaysArr.optInt(i))
            }
            weekdays.sort()
        }

        var index = 0
        val maxIterations = 10000
        while (candidateMillis <= now && index < maxIterations) {
            index++
            if (maxOccurrences != null && index >= maxOccurrences) {
                return null
            }
            candidateMillis = stepOnce(
                currentMillis = candidateMillis,
                tz = tz,
                frequency = frequency,
                interval = interval,
                customUnit = customUnit,
                customPreset = customPreset,
                weekdays = weekdays,
                dayOfMonth = dayOfMonth,
                lastDayOfMonth = lastDayOfMonth,
                nthWeekday = nthWeekday
            )
            if (endDateMillis != null && candidateMillis > endDateMillis) {
                return null
            }
        }

        if (candidateMillis <= now) return null
        if (maxOccurrences != null && index >= maxOccurrences) return null
        if (endDateMillis != null && candidateMillis > endDateMillis) return null
        return candidateMillis
    }

    private fun stepOnce(
        currentMillis: Long,
        tz: TimeZone,
        frequency: String,
        interval: Int,
        customUnit: String,
        customPreset: String,
        weekdays: List<Int>,
        dayOfMonth: Int?,
        lastDayOfMonth: Boolean,
        nthWeekday: Int?
    ): Long {
        val cal = Calendar.getInstance(tz).apply { timeInMillis = currentMillis }
        when (frequency) {
            "hourly" -> cal.add(Calendar.HOUR_OF_DAY, interval)
            "daily" -> cal.add(Calendar.DAY_OF_YEAR, interval)
            "weekly" -> {
                if (weekdays.isEmpty()) {
                    cal.add(Calendar.DAY_OF_YEAR, 7 * interval)
                } else {
                    val currentIso = calendarToIsoWeekday(cal.get(Calendar.DAY_OF_WEEK))
                    val nextInWeek = weekdays.firstOrNull { it > currentIso }
                    if (nextInWeek != null) {
                        cal.add(Calendar.DAY_OF_YEAR, nextInWeek - currentIso)
                    } else {
                        val daysUntilMonday = 8 - currentIso
                        val extraWeeksDays = (interval - 1) * 7
                        val offsetFromMonday = weekdays.first() - 1
                        cal.add(Calendar.DAY_OF_YEAR, daysUntilMonday + extraWeeksDays + offsetFromMonday)
                    }
                }
            }
            "monthly" -> addMonths(cal, interval, dayOfMonth)
            "yearly" -> addMonths(cal, 12 * interval, null)
            "custom" -> {
                when {
                    lastDayOfMonth || customPreset == "last_day_of_month" -> {
                        cal.add(Calendar.MONTH, interval)
                        cal.set(Calendar.DAY_OF_MONTH, cal.getActualMaximum(Calendar.DAY_OF_MONTH))
                    }
                    (nthWeekday != null && weekdays.isNotEmpty()) || customPreset == "2nd_saturday_of_month" -> {
                        val nth = nthWeekday ?: 2
                        val targetIso = if (weekdays.isNotEmpty()) weekdays.first() else 6
                        cal.add(Calendar.MONTH, interval)
                        cal.set(Calendar.DAY_OF_MONTH, 1)
                        val firstIso = calendarToIsoWeekday(cal.get(Calendar.DAY_OF_WEEK))
                        val offset = (targetIso - firstIso + 7) % 7
                        val maxDay = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
                        val day = (1 + offset + (nth - 1) * 7).coerceIn(1, maxDay)
                        cal.set(Calendar.DAY_OF_MONTH, day)
                    }
                    customUnit == "hours" -> cal.add(Calendar.HOUR_OF_DAY, interval)
                    customUnit == "weeks" -> cal.add(Calendar.DAY_OF_YEAR, 7 * interval)
                    customUnit == "months" -> addMonths(cal, interval, null)
                    else -> cal.add(Calendar.DAY_OF_YEAR, interval)
                }
            }
        }
        return cal.timeInMillis
    }

    private fun addMonths(cal: Calendar, months: Int, preferredDay: Int?) {
        val currentDay = cal.get(Calendar.DAY_OF_MONTH)
        cal.set(Calendar.DAY_OF_MONTH, 1)
        cal.add(Calendar.MONTH, months)
        val maxDay = cal.getActualMaximum(Calendar.DAY_OF_MONTH)
        cal.set(Calendar.DAY_OF_MONTH, (preferredDay ?: currentDay).coerceIn(1, maxDay))
    }

    private fun calendarToIsoWeekday(calDay: Int): Int {
        return when (calDay) {
            Calendar.MONDAY -> 1
            Calendar.TUESDAY -> 2
            Calendar.WEDNESDAY -> 3
            Calendar.THURSDAY -> 4
            Calendar.FRIDAY -> 5
            Calendar.SATURDAY -> 6
            Calendar.SUNDAY -> 7
            else -> 1
        }
    }

    private fun parseIsoUtcMillis(raw: String): Long? {
        if (raw.isBlank() || raw == "null") return null
        val patterns = arrayOf(
            "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'",
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        )
        for (p in patterns) {
            try {
                val sdf = SimpleDateFormat(p, Locale.US).apply {
                    timeZone = TimeZone.getTimeZone("UTC")
                }
                val parsed = sdf.parse(raw)
                if (parsed != null) return parsed.time
            } catch (_: Exception) {
            }
        }
        return null
    }
}
