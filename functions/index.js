const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

async function notifyUser(uid, title, body, kind, alarmId, extraData = {}) {
  await db.collection("users").doc(uid).collection("notifications").add({
    title,
    body,
    kind,
    alarmId,
    isRead: false,
    createdAtUtc: FieldValue.serverTimestamp(),
  });

  const userDoc = await db.collection("users").doc(uid).get();
  const tokens = userDoc.data()?.fcmTokens || [];
  if (tokens.length > 0) {
    const dataPayload = {
      kind: String(kind || ""),
      alarmId: String(alarmId || ""),
    };
    for (const [k, v] of Object.entries(extraData)) {
      if (v !== undefined && v !== null) {
        dataPayload[k] = String(v);
      }
    }
    await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: dataPayload,
      android: {
        priority: "high",
        notification: {
          channelId: "u3m_alarm_channel",
          priority: "max",
        },
      },
    });
  }
}

exports.onParticipantChanged = onDocumentWritten(
  "alarms/{alarmId}/participants/{uid}",
  async (event) => {
    const after = event.data?.after?.data();
    if (!after) return;
    const { alarmId, uid } = event.params;
    const alarmDoc = await db.collection("alarms").doc(alarmId).get();
    const alarm = alarmDoc.data();
    if (!alarm) return;

    // Never push back to the creator
    if (uid === alarm.ownerId && !event.data.before.exists) return;

    if (!event.data.before.exists) {
      const startAtMillis = alarm.startAtMillis ||
        (alarm.startAtUtc && typeof alarm.startAtUtc.toMillis === "function"
          ? alarm.startAtUtc.toMillis()
          : Date.now());

      await notifyUser(
        uid,
        `منبه مشترك (${alarm.type === "group" ? "مجموعة" : "صديق"}): ${alarm.title}`,
        alarm.notes || "تمت إضافتك لهذا المنبه وسيرن تلقائياً في موعده.",
        "shared_alarm",
        alarmId,
        {
          ownerId: alarm.ownerId || "",
          title: alarm.title || "Shared Alarm",
          notes: alarm.notes || "",
          startAtMillis,
          repeatRuleJson: alarm.repeatRuleJson || "{}",
          creatorTimezoneId: alarm.tz || "Africa/Cairo",
          type: alarm.type || "buddy",
          volume: alarm.volume ?? 0.9,
          gradualVolume: alarm.gradualVolume ?? true,
          vibrate: alarm.vibrate ?? true,
          ringOnVibrateSilent: alarm.ringOnVibrateSilent ?? true,
          isEnabled: alarm.isEnabled ?? true,
        }
      );
    } else if (after.status === "done" || after.status === "missed") {
      await notifyUser(
        alarm.ownerId,
        `${after.displayName} marked ${after.status}`,
        `Alarm: ${alarm.title}`,
        after.status === "done" ? "buddy_done" : "buddy_missed",
        alarmId
      );
    } else {
      await notifyUser(
        alarm.ownerId,
        `${after.displayName} ${after.status}`,
        `Group alarm: ${alarm.title}`,
        "group_change",
        alarmId
      );
    }
  }
);

exports.onChatMessageCreated = onDocumentCreated(
  "alarms/{alarmId}/messages/{msgId}",
  async (event) => {
    const msg = event.data?.data();
    if (!msg) return;
    const { alarmId } = event.params;
    const alarmDoc = await db.collection("alarms").doc(alarmId).get();
    const uids = alarmDoc.data()?.participantUids || [];

    for (const uid of uids) {
      if (uid === msg.senderId) continue;
      await notifyUser(
        uid,
        `${msg.senderName} (${alarmDoc.data()?.title || "Alarm"})`,
        msg.text,
        "chat",
        alarmId
      );
    }
  }
);
