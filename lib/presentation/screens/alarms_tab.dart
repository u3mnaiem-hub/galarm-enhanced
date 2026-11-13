import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/services/recurrence_calculator.dart';
import '../providers/app_providers.dart';
import 'alarm_chat_screen.dart';
import 'alarm_editor_screen.dart';
import 'alarm_history_screen.dart';

class AlarmsTab extends ConsumerWidget {
  const AlarmsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmsStreamProvider);
    final use24h = ref.watch(use24HourFormatProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Alarms')),
      body: alarmsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (alarms) {
          if (alarms.isEmpty) {
            return const Center(
              child: Text('No alarms yet. Tap + to create one.'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: alarms.length,
            itemBuilder: (context, index) {
              final alarm = alarms[index];
              final nextUtc =
                  RecurrenceCalculator.computeNextFireUtc(alarm) ?? alarm.startAtUtc;
              final localTime = nextUtc.toLocal();
              final fmt = DateFormat(use24h ? 'HH:mm' : 'hh:mm a');
              final dateFmt = DateFormat('EEE, d MMM');
              final isMissed = alarm.state == AlarmState.missed;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AlarmEditorScreen(existing: alarm),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    fmt.format(localTime),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          color: isMissed ? Colors.red : null,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                  Text(
                                    '${alarm.title} • ${dateFmt.format(localTime)}',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Switch(
                            value: alarm.isEnabled,
                            onChanged: (val) {
                              ref.read(alarmRepositoryProvider).saveAlarm(
                                    alarm.copyWith(
                                      isEnabled: val,
                                      state: val
                                          ? AlarmState.upcoming
                                          : AlarmState.archived,
                                    ),
                                  );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Chip(
                            label: Text(alarm.type.name.toUpperCase()),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (alarm.repeatRule.isRecurring)
                            Chip(
                              label: Text(alarm.repeatRule.frequency.name),
                              visualDensity: VisualDensity.compact,
                            ),
                          if (isMissed)
                            const Chip(
                              label: Text(
                                'MISSED',
                                style: TextStyle(color: Colors.red),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AlarmHistoryScreen(alarm: alarm),
                              ),
                            ),
                            icon: const Icon(Icons.history, size: 18),
                            label: const Text('History'),
                          ),
                          if (alarm.type != AlarmType.personal)
                            TextButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => AlarmChatScreen(alarm: alarm),
                                ),
                              ),
                              icon: const Icon(Icons.chat_bubble_outline, size: 18),
                              label: const Text('Chat'),
                            ),
                          TextButton(
                            onPressed: () => ref
                                .read(alarmRepositoryProvider)
                                .markOccurrenceDone(alarm),
                            child: const Text('Done'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
