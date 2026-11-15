import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';

class AlarmHistoryScreen extends ConsumerStatefulWidget {
  final Alarm alarm;
  const AlarmHistoryScreen({super.key, required this.alarm});

  @override
  ConsumerState<AlarmHistoryScreen> createState() => _AlarmHistoryScreenState();
}

class _AlarmHistoryScreenState extends ConsumerState<AlarmHistoryScreen> {
  late Future<List<AlarmOccurrencesTableData>> _historyFuture;

  @override
  void initState() {
    super.initState();
    _historyFuture = _loadHistory();
  }

  Future<List<AlarmOccurrencesTableData>> _loadHistory() async {
    await ref.read(alarmRepositoryProvider).syncNativeEvents();
    return ref.read(appDatabaseProvider).getOccurrencesForAlarm(widget.alarm.id);
  }

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;

    return Scaffold(
      appBar: AppBar(title: Text('${alarm.title} • ${context.tr('History', 'السجل')}')),
      body: FutureBuilder<List<AlarmOccurrencesTableData>>(
        future: _historyFuture,
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
                    context.tr('Done: $done • Missed: $missed of $total occurrences', 'تم: $done • فائت: $missed من $total'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                    child: Text(
                      context.tr(
                        'No occurrence history recorded yet.',
                        'لا يوجد سجل تنبيهات بعد.',
                      ),
                    ),
                  ),
                ),
              ...items.map((occ) {
                final isMissed = occ.state == 'missed';
                return ListTile(
                  leading: Icon(
                    isMissed ? Icons.cancel : Icons.check_circle,
                    color: isMissed ? Colors.red : Colors.green,
                  ),
                  title: Text(
                    context.df('EEE, d MMM yyyy • hh:mm a')
                        .format(occ.scheduledAtUtc.toLocal()),
                  ),
                  subtitle: Text(
                    context.tr(
                      'Status: ${occ.state.toUpperCase()} • Snoozes: ${occ.snoozeCount}',
                      'الحالة: ${occ.state == 'missed' ? 'فائت' : 'تم'} • الغفوات: ${occ.snoozeCount}',
                    ),
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
