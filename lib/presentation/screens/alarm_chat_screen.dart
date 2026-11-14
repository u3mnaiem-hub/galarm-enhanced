import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';

class AlarmChatScreen extends ConsumerStatefulWidget {
  final Alarm alarm;
  const AlarmChatScreen({super.key, required this.alarm});

  @override
  ConsumerState<AlarmChatScreen> createState() => _AlarmChatScreenState();
}

class _AlarmChatScreenState extends ConsumerState<AlarmChatScreen> {
  final _msgCtrl = TextEditingController();

  @override
  void dispose() {
    _msgCtrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) return;
    _msgCtrl.clear();
    final fs = ref.read(firestoreServiceProvider);
    if (fs == null) return;

    final uid = ref.read(currentUserIdProvider);
    final name = ref.read(currentUserNameProvider);
    await fs.sendChatMessage(
      ChatMessage(
        id: const Uuid().v4(),
        alarmId: widget.alarm.id,
        senderId: uid,
        senderName: name,
        text: text,
        sentAtUtc: DateTime.now().toUtc(),
        readBy: [uid],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final fs = ref.watch(firestoreServiceProvider);
    final uid = ref.watch(currentUserIdProvider);

    return Scaffold(
      appBar: AppBar(title: Text('${widget.alarm.title} • ${context.tr('Chat', 'محادثة')}')),
      body: Column(
        children: [
          Expanded(
            child: fs == null
                ? Center(child: Text(context.tr('Connect Firebase to enable live chat.', 'اربط فايربيز لتفعيل المحادثة المباشرة.')))
                : StreamBuilder<List<ChatMessage>>(
                    stream: fs.watchChatMessages(widget.alarm.id),
                    builder: (context, snap) {
                      final msgs = snap.data ?? const [];
                      if (msgs.isEmpty) {
                        return Center(child: Text(context.tr('No messages yet.', 'لا توجد رسائل بعد.')));
                      }
                      return ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: msgs.length,
                        itemBuilder: (context, i) {
                          final m = msgs[i];
                          final isMe = m.senderId == uid;
                          return Align(
                            alignment: isMe
                                ? AlignmentDirectional.centerEnd
                                : AlignmentDirectional.centerStart,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: isMe
                                    ? Theme.of(context).colorScheme.primaryContainer
                                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    m.senderName,
                                    style: Theme.of(context).textTheme.labelSmall,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(m.text),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _msgCtrl,
                      decoration: InputDecoration(
                        hintText: context.tr('Message participants...', 'اكتب رسالة للمشاركين...'),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _send,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
