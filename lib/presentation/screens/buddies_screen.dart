import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/buddy_group.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// Standalone screen exclusively for managing saved Buddies (completely separate from Alarms & Groups).
class BuddiesScreen extends ConsumerStatefulWidget {
  const BuddiesScreen({super.key});

  @override
  ConsumerState<BuddiesScreen> createState() => _BuddiesScreenState();
}

class _BuddiesScreenState extends ConsumerState<BuddiesScreen> {
  Future<void> _showBuddyDialog({SavedBuddy? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    String? errorText;

    final saved = await showDialog<SavedBuddy>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? context.tr('Add Buddy', 'إضافة صديق جديد')
                : context.tr('Edit Buddy', 'تعديل بيانات الصديق'),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                onChanged: (_) {
                  if (errorText != null) setDialogState(() => errorText = null);
                },
                decoration: InputDecoration(
                  labelText: context.tr('Name', 'الاسم'),
                  prefixIcon: const Icon(Icons.person_outline),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: context.tr('Phone Number', 'رقم الهاتف'),
                  prefixIcon: const Icon(Icons.phone_outlined),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.tr('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) {
                  setDialogState(() {
                    errorText = context.tr(
                      'Please enter a name.',
                      'يرجى إدخال الاسم.',
                    );
                  });
                  return;
                }
                Navigator.of(ctx).pop(
                  SavedBuddy(
                    id: existing?.id ?? const Uuid().v4(),
                    name: name,
                    phone: phoneCtrl.text.trim(),
                    createdAtUtc:
                        existing?.createdAtUtc ?? DateTime.now().toUtc(),
                  ),
                );
              },
              child: Text(context.tr('Save', 'حفظ')),
            ),
          ],
        ),
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();

    if (saved != null) {
      try {
        await ref.read(alarmRepositoryProvider).saveBuddy(saved);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'Saved buddy "${saved.name}"',
                  'تم حفظ الصديق "${saved.name}"',
                ),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.red,
              content: Text(
                context.tr('Error saving buddy: $e', 'تعذر حفظ الصديق: $e'),
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _pickBuddyFromContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'Contacts permission is required to pick a buddy.',
                  'مطلوب إذن جهات الاتصال لاختيار صديق من الهاتف.',
                ),
              ),
            ),
          );
        }
        return;
      }

      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      final full = await FlutterContacts.getContact(contact.id) ?? contact;
      final phone = full.phones.isNotEmpty ? full.phones.first.number.trim() : '';
      final name = full.displayName.trim().isNotEmpty
          ? full.displayName.trim()
          : (phone.isNotEmpty ? phone : context.tr('Buddy', 'صديق'));

      final buddy = SavedBuddy(
        id: const Uuid().v4(),
        name: name,
        phone: phone,
        createdAtUtc: DateTime.now().toUtc(),
      );
      await ref.read(alarmRepositoryProvider).saveBuddy(buddy);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Added "${buddy.name}" to Buddies',
                'تمت إضافة "${buddy.name}" إلى قائمة الأصدقاء',
              ),
            ),
          ),
        );
      }
    } catch (_) {
      await _showBuddyDialog();
    }
  }

  Future<void> _confirmDeleteBuddy(SavedBuddy buddy) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Delete Buddy', 'حذف الصديق')),
        content: Text(
          context.tr(
            'Delete "${buddy.name}" from saved buddies?',
            'هل تريد حذف "${buddy.name}" من قائمة الأصدقاء؟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('Cancel', 'إلغاء')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(alarmRepositoryProvider).deleteBuddy(buddy.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buddiesAsync = ref.watch(buddiesStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.people_alt_rounded, size: 22),
            const SizedBox(width: 8),
            Text(context.tr('Buddies', 'الأصدقاء')),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.buddyPurple,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _showBuddyDialog(),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: Text(context.tr('Add Buddy', 'إضافة صديق')),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: _pickBuddyFromContacts,
                  icon: const Icon(Icons.contacts_rounded, size: 18),
                  label: Text(context.tr('From Contacts', 'من جهات الاتصال')),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          buddiesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
            data: (list) {
              if (list.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      children: [
                        Icon(
                          Icons.people_outline_rounded,
                          size: 48,
                          color: AppTheme.buddyPurple.withOpacity(0.55),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            'No saved buddies yet. Add a buddy by name & phone or pick from contacts.',
                            'لا يوجد أصدقاء محفوظون بعد. أضف صديقاً بالاسم والرقم أو من جهات الاتصال.',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: list
                    .map(
                      (buddy) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color:
                              isDark ? const Color(0xFF16223A) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.buddyPurple
                                .withOpacity(isDark ? 0.45 : 0.30),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isDark
                                  ? Colors.black.withOpacity(0.75)
                                  : const Color(0xFF0F172A).withOpacity(0.24),
                              blurRadius: 14,
                              spreadRadius: 1,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          leading: CircleAvatar(
                            backgroundColor:
                                AppTheme.buddyPurple.withOpacity(0.16),
                            child: Text(
                              buddy.name.isNotEmpty
                                  ? buddy.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                color: AppTheme.buddyPurple,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          title: Text(
                            buddy.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: buddy.phone.isNotEmpty
                              ? Text(buddy.phone, textDirection: TextDirection.ltr)
                              : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: context.tr('Edit', 'تعديل'),
                                icon:
                                    Icon(Icons.edit_outlined, color: cs.primary),
                                onPressed: () =>
                                    _showBuddyDialog(existing: buddy),
                              ),
                              IconButton(
                                tooltip: context.tr('Delete', 'حذف'),
                                icon: const Icon(Icons.delete_outline,
                                    color: Colors.red),
                                onPressed: () => _confirmDeleteBuddy(buddy),
                              ),
                            ],
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
