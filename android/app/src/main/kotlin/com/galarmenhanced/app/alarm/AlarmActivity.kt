package com.galarmenhanced.app.alarm

import android.app.Activity
import android.content.Intent
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.WindowManager
import android.widget.Button
import android.widget.LinearLayout
import android.widget.TextView
import com.galarmenhanced.app.MainActivity
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class AlarmActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

        val payloadRaw = intent.getStringExtra("payload") ?: "{}"
        val payload = JSONObject(payloadRaw)
        val title = payload.optString("title", "Alarm")
        val notes = payload.optString("notes", "")
        val snoozeMinutes = payload.optInt("snoozeDurationMinutes", 5)
        val currentSnoozeCount = payload.optInt("currentSnoozeCount", 0)
        val triggerMillis = payload.optLong("triggerAtMillis", System.currentTimeMillis())

        val timeFmt = SimpleDateFormat("hh:mm a", Locale.getDefault())
        val currentTimeStr = timeFmt.format(Date())
        val originalTimeStr = timeFmt.format(Date(triggerMillis))

        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            gravity = Gravity.CENTER
            setBackgroundColor(Color.parseColor("#11131A"))
            setPadding(64, 96, 64, 96)
        }

        val timeView = TextView(this).apply {
            text = currentTimeStr
            textSize = 48f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }

        val titleView = TextView(this).apply {
            text = title
            textSize = 28f
            setTextColor(Color.parseColor("#80CBC4"))
            gravity = Gravity.CENTER
            setPadding(0, 24, 0, 12)
        }

        val notesView = TextView(this).apply {
            text = if (currentSnoozeCount > 0) {
                "Original: $originalTimeStr • Snooze #$currentSnoozeCount\n$notes"
            } else {
                notes
            }
            textSize = 16f
            setTextColor(Color.LTGRAY)
            gravity = Gravity.CENTER
            setPadding(0, 8, 0, 48)
        }

        val doneBtn = Button(this).apply {
            text = "Done"
            textSize = 18f
            setOnClickListener {
                stopService(Intent(this@AlarmActivity, AlarmRingingService::class.java))
                finish()
            }
        }

        val snoozeBtn = Button(this).apply {
            text = "Snooze ($snoozeMinutes min)"
            textSize = 18f
            setOnClickListener {
                val nextTrigger = System.currentTimeMillis() + (snoozeMinutes * 60_000L)
                payload.put("triggerAtMillis", nextTrigger)
                payload.put("currentSnoozeCount", currentSnoozeCount + 1)
                MainActivity.scheduleWithAlarmManager(this@AlarmActivity, payload)
                stopService(Intent(this@AlarmActivity, AlarmRingingService::class.java))
                finish()
            }
        }

        val dismissBtn = Button(this).apply {
            text = "Dismiss"
            textSize = 18f
            setOnClickListener {
                stopService(Intent(this@AlarmActivity, AlarmRingingService::class.java))
                finish()
            }
        }

        root.addView(timeView)
        root.addView(titleView)
        root.addView(notesView)
        root.addView(doneBtn)
        root.addView(snoozeBtn)
        root.addView(dismissBtn)

        setContentView(root)
    }
}
