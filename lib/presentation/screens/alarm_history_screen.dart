import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../data/local/app_database.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';

class AlarmHistoryScreen extends ConsumerWidget {
  final Alarm alarm;
  const AlarmHistoryScreen({super.key, required this.alarm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: Text('${alarm.title} • History')),
      body: FutureBuilder<List<AlarmOccurrencesTableData>>(
        future: db.getOccurrencesForAlarm(alarm.id),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data!;
          final total = items.length;
          final missed = items.where((e) => e.state == 'missed').length;
          final done = items.where((e) => e.state == 'done').length;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Done: $done • Missed: $missed of $total occurrences',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                const Center(child: Text('No occurrence history recorded yet.')),
              ...items.map((occ) {
                final isMissed = occ.state == 'missed';
                return ListTile(
                  leading: Icon(
                    isMissed ? Icons.cancel : Icons.check_circle,
                    color: isMissed ? Colors.red : Colors.green,
                  ),
                  title: Text(
                    DateFormat('EEE, d MMM yyyy • hh:mm a')
                        .format(occ.scheduledAtUtc.toLocal()),
                  ),
                  subtitle: Text(
                    'Status: ${occ.state.toUpperCase()} • Snoozes: ${occ.snoozeCount}',
                  ),
                );
              }),
            ],
          );
        },
      ),
    );
  }
}
