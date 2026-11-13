# G-Alarm Enhanced (PulseRing)

Production-structured Flutter + Kotlin Android social alarm clock and reminder app.

## Architecture
- `lib/domain/` — Pure Dart entities (`Alarm`, `RepeatRule`, `SnoozeConfig`, `AlarmParticipant`, `ChatMessage`) and `RecurrenceCalculator` (UTC storage + timezone conversion + missed-alarm non-blocking recurrence).
- `lib/data/` — Offline-first Drift SQLite database (`AppDatabase` + `SyncQueueTable`), `FirestoreService` (SHA-256 phone-hash contact matching, real-time chat, last-write-wins sync), and `NativeAlarmChannel`.
- `lib/presentation/` — Riverpod state, Material 3 light/dark theme, EN/AR RTL localization, 4-tab shell (`Alarms`, `Notifications`, `Groups & Contacts`, `Settings`), onboarding + permissions walkthrough, phone OTP auth, alarm editor, chat, and history.
- `android/app/src/main/kotlin/...` — Native `AlarmManager.setAlarmClock`, `AlarmRingingService` (`FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK` + `AudioAttributes.USAGE_ALARM`), lock-screen `AlarmActivity`, and `BootCompletedReceiver`.

## Firebase Setup
1. Create a Firebase project and enable **Authentication -> Phone**, **Cloud Firestore**, **Cloud Storage**, and **Cloud Messaging**.
2. Add an Android app with package name `com.galarmenhanced.app`.
3. Register your debug and release **SHA-1** and **SHA-256** fingerprints in Firebase Project Settings (required for Phone Auth OTP).
4. Download `google-services.json` and place it in `android/app/google-services.json`.
5. Deploy `firestore.rules` and `functions/`:
   ```bash
   firebase deploy --only firestore:rules,functions
   ```

## Build & Run (Cloud CI / Local)
```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter test
flutter build apk --release
```
*(A GitHub Actions workflow is included at `.github/workflows/flutter-ci.yml` for Cloud APK builds.)*

## Real-Device Reliability Checklist
- [ ] Grant **Notifications** (`POST_NOTIFICATIONS`) on Android 13+.
- [ ] Grant **Alarms & Reminders** (`SCHEDULE_EXACT_ALARM`) on Android 12+.
- [ ] Grant **Full-Screen Intent** (`USE_FULL_SCREEN_INTENT`) on Android 14+.
- [ ] Disable **Battery Optimization** (and enable Autostart on Xiaomi/Oppo/Samsung/Huawei).
- [ ] Test alarm firing with: app killed, screen locked, device on Vibrate/Silent, Doze active, and after device reboot.
