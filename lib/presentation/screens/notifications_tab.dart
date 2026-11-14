import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../providers/app_providers.dart';

class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsStreamProvider);
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Notifications', 'الإشعارات')),
        actions: [
          TextButton(
            onPressed: () => db.clearNotifications(),
            child: Text(context.tr('Clear all', 'مسح الكل')),
          ),
        ],
      ),
      body: notifsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${context.tr('Error', 'خطأ')}: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(child: Text(context.tr("You're all caught up!", 'لا توجد إشعارات جديدة.')));
          }
          return ListView.builder(
            itemCount: items.length,
            itemBuilder: (context, i) {
              final n = items[i];
              return ListTile(
                leading: Icon(
                  n.isRead ? Icons.notifications_none : Icons.notifications_active,
                  color: n.isRead
                      ? null
                      : Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  n.title,
                  style: TextStyle(
                    fontWeight: n.isRead ? FontWeight.normal : FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  '${n.body}\n${context.df('d MMM, hh:mm a').format(n.createdAtUtc.toLocal())}',
                ),
                isThreeLine: true,
                onTap: () => db.markNotificationRead(n.id),
              );
            },
          );
        },
      ),
    );
  }
}
