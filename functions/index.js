const { onDocumentCreated, onDocumentWritten } = require("firebase-functions/v2/firestore");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const { getMessaging } = require("firebase-admin/messaging");

initializeApp();
const db = getFirestore();

async function notifyUser(uid, title, body, kind, alarmId) {
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
    await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title, body },
      data: { kind, alarmId: alarmId || "" },
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

    if (!event.data.before.exists) {
      await notifyUser(
        uid,
        `New ${alarm.type} alarm: ${alarm.title}`,
        "You were added as a participant.",
        "participant_added",
        alarmId
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
