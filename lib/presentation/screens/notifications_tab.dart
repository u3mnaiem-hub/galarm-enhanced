import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class NotificationsTab extends ConsumerWidget {
  const NotificationsTab({super.key});

  (IconData, Color) _styleForKind(String kind, ColorScheme cs) {
    switch (kind) {
      case 'buddy_sent':
      case 'buddy_received':
        return (Icons.people_alt_rounded, AppTheme.buddyPurple);
      case 'group_sent':
      case 'group_received':
      case 'group_change':
        return (Icons.groups_rounded, AppTheme.groupTeal);
      case 'buddy_done':
        return (Icons.check_circle_rounded, const Color(0xFF059669));
      case 'buddy_missed':
        return (Icons.error_rounded, const Color(0xFFDC2626));
      default:
        return (Icons.notifications_active_rounded, cs.primary);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifsAsync = ref.watch(notificationsStreamProvider);
    final db = ref.watch(appDatabaseProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Notifications', 'الإشعارات')),
        actions: [
          TextButton(
            onPressed: () => db.clearNotifications(),
            child: Text(
              context.tr('Clear all', 'مسح الكل'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: notifsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('${context.tr('Error', 'خطأ')}: $e')),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: Text(
                context.tr("You're all caught up!", 'لا توجد إشعارات جديدة.'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
            itemCount: items.length,
            itemBuilder: (context, i) {
              final n = items[i];
              final (icon, accent) = _styleForKind(n.kind, cs);
              return Card(
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(n.isRead ? 0.09 : 0.18),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      icon,
                      color: n.isRead ? accent.withOpacity(0.6) : accent,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    n.title,
                    style: TextStyle(
                      fontWeight: n.isRead ? FontWeight.w500 : FontWeight.w800,
                    ),
                  ),
                  subtitle: Text(
                    '${n.body}\n${context.df('d MMM, hh:mm a').format(n.createdAtUtc.toLocal())}',
                  ),
                  isThreeLine: true,
                  trailing: n.isRead
                      ? null
                      : Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                  onTap: () => db.markNotificationRead(n.id),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
