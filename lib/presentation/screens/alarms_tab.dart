import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/services/recurrence_calculator.dart';
import '../providers/app_providers.dart';
import 'alarm_editor_screen.dart';
import 'alarm_history_screen.dart';

class AlarmsTab extends ConsumerWidget {
  const AlarmsTab({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Alarm alarm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Delete Alarm', 'حذف المنبه')),
        content: Text(
          context.tr(
            'Are you sure you want to delete "${alarm.title}"?',
            'هل أنت متأكد من حذف المنبه "${alarm.title}"؟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('Cancel', 'إلغاء')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(alarmRepositoryProvider).deleteAlarm(alarm.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alarmsAsync = ref.watch(alarmsStreamProvider);
    final use24h = ref.watch(use24HourFormatProvider);

    return Scaffold(
      appBar: AppBar(title: Text(context.tr('U3m Alarm', 'منبه U3m'))),
      body: alarmsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(': $e')),
        data: (alarms) {
          if (alarms.isEmpty) {
            return Center(
              child: Text(
                context.tr(
                  'No alarms yet. Tap + to create one.',
                  'لا توجد منبهات بعد. اضغط + لإضافة منبه.',
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 110),
            itemCount: alarms.length,
            itemBuilder: (context, index) {
              final alarm = alarms[index];
              final nextUtc =
                  RecurrenceCalculator.computeNextFireUtc(alarm) ??
                      alarm.startAtUtc;
              final localTime = nextUtc.toLocal();
              final fmt = context.df(use24h ? 'HH:mm' : 'hh:mm a');
              final dateFmt = context.df('EEE, d MMM');
              final isMissed = alarm.state == AlarmState.missed;
              final cs = Theme.of(context).colorScheme;

              return Card(
                margin: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AlarmEditorScreen(existing: alarm),
                    ),
                  ),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: alarm.isEnabled
                                    ? cs.primaryContainer.withOpacity(0.75)
                                    : cs.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                fmt.format(localTime),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                  color: isMissed
                                      ? Colors.red
                                      : (alarm.isEnabled
                                          ? cs.onPrimaryContainer
                                          : cs.outline),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    alarm.title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 13.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    '${dateFmt.format(localTime)}${alarm.notes.isNotEmpty ? " • ${alarm.notes}" : ""}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(
                              height: 28,
                              child: Transform.scale(
                                scale: 0.78,
                                child: Switch(
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
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: cs.secondaryContainer.withOpacity(0.6),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                context.tr('PERSONAL', 'شخصي'),
                                style: TextStyle(
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSecondaryContainer,
                                ),
                              ),
                            ),
                            if (alarm.repeatRule.isRecurring) ...[
                              const SizedBox(width: 6),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: cs.tertiaryContainer.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    context.trLabel(
                                      alarm.repeatRule.displayLabel,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w600,
                                      color: cs.onTertiaryContainer,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            if (isMissed) ...[
                              const SizedBox(width: 6),
                              Text(
                                context.tr('MISSED', 'فائت'),
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                            const Spacer(),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AlarmEditorScreen(existing: alarm),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 14,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      context.tr('Edit', 'تعديل'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => _confirmDelete(context, ref, alarm),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.delete_outline,
                                      size: 14,
                                      color: Colors.red,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      context.tr('Delete', 'حذف'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      AlarmHistoryScreen(alarm: alarm),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.history,
                                      size: 14,
                                      color: cs.primary,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      context.tr('History', 'السجل'),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: cs.primary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () => ref
                                  .read(alarmRepositoryProvider)
                                  .markOccurrenceDone(alarm),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                child: Text(
                                  context.tr('Done', 'تم'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
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
