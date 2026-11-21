import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/buddy_group.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class ContactsGroupsTab extends ConsumerStatefulWidget {
  const ContactsGroupsTab({super.key});

  @override
  ConsumerState<ContactsGroupsTab> createState() => _ContactsGroupsTabState();
}

class _ContactsGroupsTabState extends ConsumerState<ContactsGroupsTab> {
  Future<void> _showBuddyDialog({SavedBuddy? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final saved = await showDialog<SavedBuddy>(
      context: context,
      builder: (ctx) => AlertDialog(
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
              if (name.isEmpty) return;
              Navigator.of(ctx).pop(
                SavedBuddy(
                  id: existing?.id ?? const Uuid().v4(),
                  name: name,
                  phone: phoneCtrl.text.trim(),
                  createdAtUtc: existing?.createdAtUtc ?? DateTime.now().toUtc(),
                ),
              );
            },
            child: Text(context.tr('Save', 'حفظ')),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    phoneCtrl.dispose();

    if (saved != null) {
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

  Future<void> _showGroupDialog(
    List<SavedBuddy> allBuddies, {
    SavedGroup? existing,
  }) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final selectedIds = <String>{...(existing?.memberIds ?? const <String>[])};

    final saved = await showDialog<SavedGroup>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            existing == null
                ? context.tr('Create Group', 'إنشاء مجموعة جديدة')
                : context.tr('Edit Group', 'تعديل المجموعة'),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: context.tr('Group Name', 'اسم المجموعة'),
                      prefixIcon: const Icon(Icons.groups_outlined),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.tr(
                      'Select Buddies (${selectedIds.length})',
                      'اختر الأصدقاء (${selectedIds.length})',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  if (allBuddies.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Text(
                        context.tr(
                          'No saved buddies yet. Add buddies first in the Buddies tab.',
                          'لا يوجد أصدقاء محفوظون بعد. أضف أصدقاء أولاً من تبويب الأصدقاء.',
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  else
                    ...allBuddies.map(
                      (b) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: selectedIds.contains(b.id),
                        title: Text(b.name),
                        subtitle: b.phone.isNotEmpty ? Text(b.phone) : null,
                        onChanged: (checked) {
                          setDialogState(() {
                            if (checked == true) {
                              selectedIds.add(b.id);
                            } else {
                              selectedIds.remove(b.id);
                            }
                          });
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(context.tr('Cancel', 'إلغاء')),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                Navigator.of(ctx).pop(
                  SavedGroup(
                    id: existing?.id ?? const Uuid().v4(),
                    name: name,
                    memberIds: selectedIds.toList(),
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

    if (saved != null) {
      await ref.read(alarmRepositoryProvider).saveGroup(saved);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Saved group "${saved.name}"',
                'تم حفظ المجموعة "${saved.name}"',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmDeleteGroup(SavedGroup group) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Delete Group', 'حذف المجموعة')),
        content: Text(
          context.tr(
            'Delete group "${group.name}"?',
            'هل تريد حذف المجموعة "${group.name}"؟',
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
      await ref.read(alarmRepositoryProvider).deleteGroup(group.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final buddiesAsync = ref.watch(buddiesStreamProvider);
    final groupsAsync = ref.watch(groupsStreamProvider);
    final buddies = buddiesAsync.valueOrNull ?? const <SavedBuddy>[];
    final buddyMap = {for (final b in buddies) b.id: b};
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('Buddies & Groups', 'الأصدقاء والمجموعات')),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(
                icon: const Icon(Icons.people_alt_rounded, size: 18),
                text: context.tr('Buddies (${buddies.length})', 'الأصدقاء (${buddies.length})'),
              ),
              Tab(
                icon: const Icon(Icons.groups_rounded, size: 18),
                text: context.tr(
                  'Groups (${groupsAsync.valueOrNull?.length ?? 0})',
                  'المجموعات (${groupsAsync.valueOrNull?.length ?? 0})',
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // TAB 1: Saved Buddies
            ListView(
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
                  error: (e, _) => Text('$e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Icon(
                                Icons.people_outline_rounded,
                                size: 46,
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
                                color: isDark
                                    ? const Color(0xFF16223A)
                                    : Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: AppTheme.buddyPurple
                                      .withOpacity(isDark ? 0.45 : 0.30),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: isDark
                                        ? Colors.black.withOpacity(0.75)
                                        : const Color(0xFF0F172A)
                                            .withOpacity(0.24),
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
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: buddy.phone.isNotEmpty
                                    ? Text(
                                        buddy.phone,
                                        textDirection: TextDirection.ltr,
                                      )
                                    : null,
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: context.tr('Edit', 'تعديل'),
                                      icon: Icon(Icons.edit_outlined,
                                          color: cs.primary),
                                      onPressed: () =>
                                          _showBuddyDialog(existing: buddy),
                                    ),
                                    IconButton(
                                      tooltip: context.tr('Delete', 'حذف'),
                                      icon: const Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      onPressed: () =>
                                          _confirmDeleteBuddy(buddy),
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

            // TAB 2: Saved Groups
            ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.groupTeal,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _showGroupDialog(buddies),
                  icon: const Icon(Icons.group_add_rounded, size: 20),
                  label: Text(context.tr('Create New Group', 'إنشاء مجموعة جديدة')),
                ),
                const SizedBox(height: 16),
                groupsAsync.when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('$e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Icon(
                                Icons.groups_outlined,
                                size: 46,
                                color: AppTheme.groupTeal.withOpacity(0.55),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                context.tr(
                                  'No saved groups yet. Create a group and add your saved buddies to it.',
                                  'لا توجد مجموعات محفوظة بعد. أنشئ مجموعة وأضف إليها أصدقاءك المحفوظين.',
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
                      children: list.map((group) {
                        final memberNames = group.memberIds
                            .map((id) => buddyMap[id]?.name)
                            .whereType<String>()
                            .toList();
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF16223A)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: AppTheme.groupTeal
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
                              vertical: 8,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppTheme.groupTeal.withOpacity(0.16),
                              child: const Icon(
                                Icons.groups_rounded,
                                color: AppTheme.groupTeal,
                              ),
                            ),
                            title: Text(
                              group.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            subtitle: Text(
                              memberNames.isNotEmpty
                                  ? '${memberNames.length} • ${memberNames.join('، ')}'
                                  : context.tr('No members yet', 'لا يوجد أعضاء بعد'),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: context.tr('Edit', 'تعديل'),
                                  icon: Icon(Icons.edit_outlined,
                                      color: cs.primary),
                                  onPressed: () => _showGroupDialog(
                                    buddies,
                                    existing: group,
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.tr('Delete', 'حذف'),
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red),
                                  onPressed: () => _confirmDeleteGroup(group),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
