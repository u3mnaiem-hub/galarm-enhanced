package com.galarmenhanced.app.alarm

import android.app.Activity
import android.app.KeyguardManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.graphics.Color
import android.graphics.drawable.GradientDrawable
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
    private val closeReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            finish()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureLockScreenFlags()
        val filter = IntentFilter(AlarmRingingService.ACTION_CLOSE_ACTIVITY)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(closeReceiver, filter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            registerReceiver(closeReceiver, filter)
        }
        renderAlarmUi(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        if (intent != null) {
            setIntent(intent)
            renderAlarmUi(intent)
        }
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(closeReceiver)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    private fun configureLockScreenFlags() {
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            val km = getSystemService(Context.KEYGUARD_SERVICE) as? KeyguardManager
            km?.requestDismissKeyguard(this, null)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
    }

    private fun renderAlarmUi(currentIntent: Intent) {
        val payloadRaw = currentIntent.getStringExtra("payload") ?: "{}"
        val payload = JSONObject(payloadRaw)
        val title = payload.optString("title", "Alarm").ifBlank { "Alarm" }
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

        val appHeaderView = TextView(this).apply {
            text = "U3m Alarm"
            textSize = 16f
            setTextColor(Color.parseColor("#80CBC4"))
            gravity = Gravity.CENTER
            setPadding(0, 0, 0, 16)
        }

        val timeView = TextView(this).apply {
            text = currentTimeStr
            textSize = 52f
            setTextColor(Color.WHITE)
            gravity = Gravity.CENTER
        }

        val titleView = TextView(this).apply {
            text = title
            textSize = 28f
            setTextColor(Color.parseColor("#80CBC4"))
            gravity = Gravity.CENTER
            setPadding(0, 28, 0, 12)
        }

        val descriptionText = buildString {
            if (notes.isNotBlank()) {
                append(notes)
            }
            if (currentSnoozeCount > 0) {
                if (isNotEmpty()) append("\n\n")
                append("Original: $originalTimeStr • Snooze #$currentSnoozeCount")
            }
        }

        val notesView = TextView(this).apply {
            text = if (descriptionText.isNotBlank()) descriptionText else "Alarm is ringing"
            textSize = 18f
            setTextColor(Color.parseColor("#E0E0E0"))
            gravity = Gravity.CENTER
            setPadding(16, 8, 16, 56)
        }

        val lp = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT,
            LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply {
            setMargins(0, 16, 0, 16)
        }

        val doneBtn = Button(this).apply {
            text = "Stop / Done"
            textSize = 18f
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 32f
                setColor(Color.parseColor("#00897B"))
            }
            setPadding(32, 32, 32, 32)
            layoutParams = lp
            setOnClickListener {
                val doneIntent = Intent(this@AlarmActivity, AlarmRingingService::class.java).apply {
                    action = AlarmRingingService.ACTION_DONE
                    putExtra("payload", payloadRaw)
                }
                startService(doneIntent)
                finish()
            }
        }

        val snoozeBtn = Button(this).apply {
            text = "Snooze ($snoozeMinutes min)"
            textSize = 18f
            setTextColor(Color.WHITE)
            background = GradientDrawable().apply {
                shape = GradientDrawable.RECTANGLE
                cornerRadius = 32f
                setColor(Color.parseColor("#3949AB"))
            }
            setPadding(32, 32, 32, 32)
            layoutParams = lp
            setOnClickListener {
                val snoozeIntent = Intent(this@AlarmActivity, AlarmRingingService::class.java).apply {
                    action = AlarmRingingService.ACTION_SNOOZE
                    putExtra("payload", payloadRaw)
                }
                startService(snoozeIntent)
                finish()
            }
        }

        root.addView(appHeaderView)
        root.addView(timeView)
        root.addView(titleView)
        root.addView(notesView)
        root.addView(doneBtn)
        root.addView(snoozeBtn)

        setContentView(root)
    }
}
