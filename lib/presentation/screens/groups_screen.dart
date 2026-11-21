import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/entities/buddy_group.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// Standalone screen exclusively for managing saved Groups (completely independent of Alarms & Buddies).
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  Future<void> _openGroupEditor({SavedGroup? existing}) async {
    final saved = await showModalBottomSheet<SavedGroup>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _StandaloneGroupEditorSheet(existing: existing),
    );

    if (saved != null && mounted) {
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
    final groupsAsync = ref.watch(groupsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.groups_rounded, size: 22),
            const SizedBox(width: 8),
            Text(context.tr('Groups', 'المجموعات')),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.groupTeal,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            onPressed: () => _openGroupEditor(),
            icon: const Icon(Icons.group_add_rounded, size: 20),
            label: Text(context.tr('New Group', 'مجموعة جديدة')),
          ),
          const SizedBox(height: 16),
          groupsAsync.when(
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
                          Icons.groups_outlined,
                          size: 48,
                          color: AppTheme.groupTeal.withOpacity(0.55),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          context.tr(
                            'No saved groups yet. Tap "New Group" and add members directly by name & phone or from contacts.',
                            'لا توجد مجموعات محفوظة بعد. اضغط «مجموعة جديدة» وأضف الأعضاء بالاسم والرقم أو من جهات الاتصال.',
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
                  final memberNames = group.members.map((m) => m.name).toList();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF16223A) : Colors.white,
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
                        backgroundColor: AppTheme.groupTeal.withOpacity(0.16),
                        child: const Icon(
                          Icons.groups_rounded,
                          color: AppTheme.groupTeal,
                        ),
                      ),
                      title: Text(
                        group.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
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
                            icon: Icon(Icons.edit_outlined, color: cs.primary),
                            onPressed: () => _openGroupEditor(existing: group),
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
    );
  }
}

class _StandaloneGroupEditorSheet extends ConsumerStatefulWidget {
  final SavedGroup? existing;

  const _StandaloneGroupEditorSheet({this.existing});

  @override
  ConsumerState<_StandaloneGroupEditorSheet> createState() =>
      _StandaloneGroupEditorSheetState();
}

class _StandaloneGroupEditorSheetState
    extends ConsumerState<_StandaloneGroupEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final List<GroupMember> _members;
  bool _saving = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _members = [...(widget.existing?.members ?? const <GroupMember>[])];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMemberManually() async {
    final mNameCtrl = TextEditingController();
    final mPhoneCtrl = TextEditingController();
    final added = await showDialog<GroupMember>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Add Group Member', 'إضافة عضو للمجموعة')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: mNameCtrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.tr('Name', 'الاسم'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: mPhoneCtrl,
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
              final n = mNameCtrl.text.trim();
              if (n.isEmpty) return;
              Navigator.of(ctx).pop(
                GroupMember(
                  id: const Uuid().v4(),
                  name: n,
                  phone: mPhoneCtrl.text.trim(),
                ),
              );
            },
            child: Text(context.tr('Add', 'إضافة')),
          ),
        ],
      ),
    );
    mNameCtrl.dispose();
    mPhoneCtrl.dispose();

    if (added != null && mounted) {
      setState(() {
        _members.add(added);
        if (_errorText != null) _errorText = null;
      });
    }
  }

  Future<void> _pickMemberFromContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        if (mounted) {
          setState(() {
            _errorText = context.tr(
              'Contacts permission is required to pick a member.',
              'مطلوب إذن جهات الاتصال لاختيار عضو من الهاتف.',
            );
          });
        }
        return;
      }

      final contact = await FlutterContacts.openExternalPick();
      if (contact == null) return;
      final full = await FlutterContacts.getContact(contact.id) ?? contact;
      final phone = full.phones.isNotEmpty ? full.phones.first.number.trim() : '';
      final name = full.displayName.trim().isNotEmpty
          ? full.displayName.trim()
          : (phone.isNotEmpty ? phone : context.tr('Member', 'عضو'));

      if (mounted) {
        setState(() {
          _members.add(
            GroupMember(
              id: const Uuid().v4(),
              name: name,
              phone: phone,
            ),
          );
          if (_errorText != null) _errorText = null;
        });
      }
    } catch (_) {
      await _addMemberManually();
    }
  }

  Future<void> _onSave() async {
    if (_saving) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() {
        _errorText = context.tr(
          'Please enter a group name.',
          'يرجى إدخال اسم المجموعة.',
        );
      });
      return;
    }
    if (_members.isEmpty) {
      setState(() {
        _errorText = context.tr(
          'Please add at least one member to this group.',
          'يرجى إضافة عضو واحد على الأقل لهذه المجموعة.',
        );
      });
      return;
    }

    setState(() {
      _saving = true;
      _errorText = null;
    });

    try {
      final group = SavedGroup(
        id: widget.existing?.id ?? const Uuid().v4(),
        name: name,
        members: List<GroupMember>.from(_members),
        createdAtUtc: widget.existing?.createdAtUtc ?? DateTime.now().toUtc(),
      );
      await ref.read(alarmRepositoryProvider).saveGroup(group);
      if (mounted) {
        Navigator.of(context).pop(group);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _errorText = context.tr(
            'Could not save group: $e',
            'تعذر حفظ المجموعة: $e',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom +
        MediaQuery.of(context).viewPadding.bottom;
    final maxHeight = MediaQuery.of(context).size.height * 0.85;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 16 + bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.existing == null
                      ? context.tr('New Group', 'مجموعة جديدة')
                      : context.tr('Edit Group', 'تعديل المجموعة'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                IconButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.done,
              onChanged: (_) {
                if (_errorText != null) setState(() => _errorText = null);
              },
              decoration: InputDecoration(
                labelText: context.tr('Group Name', 'اسم المجموعة'),
                prefixIcon: const Icon(Icons.groups_outlined),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: _saving ? null : _addMemberManually,
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text(context.tr('Add by Name', 'إضافة بالاسم')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _pickMemberFromContacts,
                    icon: const Icon(Icons.contacts_rounded, size: 18),
                    label: Text(context.tr('From Contacts', 'من جهات الاتصال')),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'Members (${_members.length})',
                'الأعضاء (${_members.length})',
              ),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
              ),
            ),
            const SizedBox(height: 6),
            Flexible(
              child: _members.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        context.tr(
                          'No members added yet. Add members by name & phone or pick from phone contacts.',
                          'لم تتم إضافة أعضاء بعد. أضف الأعضاء بالاسم والرقم أو من جهات الاتصال.',
                        ),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _members.length,
                      itemBuilder: (_, idx) {
                        final m = _members[idx];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor:
                                AppTheme.groupTeal.withOpacity(0.16),
                            child: Text(
                              m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: AppTheme.groupTeal,
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          title: Text(
                            m.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: m.phone.isNotEmpty
                              ? Text(m.phone, textDirection: TextDirection.ltr)
                              : null,
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: Colors.red, size: 20),
                            onPressed: _saving
                                ? null
                                : () => setState(() => _members.removeAt(idx)),
                          ),
                        );
                      },
                    ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.withOpacity(0.45)),
                ),
                child: Text(
                  _errorText!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(context.tr('Cancel', 'إلغاء')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.groupTeal,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: _saving ? null : _onSave,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: Text(
                      _saving
                          ? context.tr('Saving...', 'جاري الحفظ...')
                          : context.tr('Save Group', 'حفظ المجموعة'),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
