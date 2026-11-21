import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/remote/firestore_service.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'alarm_chat_screen.dart';
import 'alarm_editor_screen.dart';

class ContactsGroupsTab extends ConsumerStatefulWidget {
  const ContactsGroupsTab({super.key});

  @override
  ConsumerState<ContactsGroupsTab> createState() => _ContactsGroupsTabState();
}

class _ContactsGroupsTabState extends ConsumerState<ContactsGroupsTab> {
  bool _loading = false;
  bool _permissionDenied = false;
  List<UserProfile> _matchedUsers = [];
  List<Contact> _inviteContacts = [];

  Future<void> _loadContacts() async {
    setState(() {
      _loading = true;
      _permissionDenied = false;
    });
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      setState(() {
        _loading = false;
        _permissionDenied = true;
      });
      return;
    }

    final contacts = await FlutterContacts.getContacts(withProperties: true);
    final hashToContact = <String, Contact>{};
    for (final c in contacts) {
      for (final p in c.phones) {
        final h = FirestoreService.hashPhoneNumber(p.number);
        hashToContact[h] = c;
      }
    }

    final fs = ref.read(firestoreServiceProvider);
    final matched = fs != null
        ? await fs.matchPhoneHashes(hashToContact.keys.toList())
        : <UserProfile>[];
    final matchedHashes = matched.map((u) => u.phoneHash).toSet();

    final nonUsers = contacts.where((c) {
      return c.phones.isNotEmpty &&
          c.phones.every(
            (p) => !matchedHashes
                .contains(FirestoreService.hashPhoneNumber(p.number)),
          );
    }).toList();

    if (mounted) {
      setState(() {
        _matchedUsers = matched;
        _inviteContacts = nonUsers;
        _loading = false;
      });
    }
  }

  Future<void> _sendSmsInvite(Contact c) async {
    final bodyText = context.tr(
      'Join me on U3m Alarm so we can share group & buddy alarms!',
      'انضم إلي على منبه U3m لنتشارك منبهات المجموعات والأصدقاء!',
    );
    final phone = c.phones.first.number;
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {'body': bodyText},
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alarmsAsync = ref.watch(alarmsStreamProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Groups & Buddy', 'المجموعات والأصدقاء')),
        actions: [
          IconButton(
            onPressed: _loadContacts,
            icon: const Icon(Icons.sync),
            tooltip: context.tr('Match Phone Contacts', 'مطابقة جهات الاتصال'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
        children: [
          // Quick Create Group / Buddy Cards
          Row(
            children: [
              Expanded(
                child: _QuickSocialCard(
                  icon: Icons.groups_rounded,
                  title: context.tr('New Group', 'مجموعة جديدة'),
                  subtitle: context.tr('Shared alarm', 'منبه مشترك'),
                  color: AppTheme.groupTeal,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const AlarmEditorScreen(initialType: AlarmType.group),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _QuickSocialCard(
                  icon: Icons.people_alt_rounded,
                  title: context.tr('New Buddy', 'صديق جديد'),
                  subtitle: context.tr('Accountability', 'متابعة صديق'),
                  color: AppTheme.buddyPurple,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const AlarmEditorScreen(initialType: AlarmType.buddy),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Active Group & Buddy Alarms
          Text(
            context.tr('Active Group & Buddy Alarms', 'منبهات المجموعات والأصدقاء'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          alarmsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e'),
            data: (alarms) {
              final social = alarms
                  .where((a) =>
                      a.type == AlarmType.group || a.type == AlarmType.buddy)
                  .toList();
              if (social.isEmpty) {
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      context.tr(
                        'No group or buddy alarms yet. Use the buttons above to create one!',
                        'لا توجد منبهات مجموعات أو أصدقاء بعد. استخدم الأزرار بالأعلى لإنشاء منبه!',
                      ),
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                  ),
                );
              }
              return Column(
                children: social.map((alarm) {
                  final isBuddy = alarm.type == AlarmType.buddy;
                  final accent =
                      isBuddy ? AppTheme.buddyPurple : AppTheme.groupTeal;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF16223A) : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: accent.withOpacity(isDark ? 0.45 : 0.30),
                        width: 1.1,
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
                        backgroundColor: accent.withOpacity(0.16),
                        child: Icon(
                          isBuddy
                              ? Icons.people_alt_rounded
                              : Icons.groups_rounded,
                          color: accent,
                        ),
                      ),
                      title: Text(
                        alarm.title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        alarm.participants.isNotEmpty
                            ? alarm.participants
                                .map((p) => p.displayName)
                                .join(' • ')
                            : (isBuddy
                                ? context.tr('Buddy Alarm', 'منبه صديق')
                                : context.tr('Group Alarm', 'منبه مجموعة')),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: context.tr('Chat', 'محادثة'),
                            icon: Icon(Icons.chat_bubble_outline, color: accent),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => AlarmChatScreen(alarm: alarm),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: context.tr('Edit', 'تعديل'),
                            icon: Icon(Icons.edit_outlined, color: cs.primary),
                            onPressed: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    AlarmEditorScreen(existing: alarm),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const Divider(height: 28),

          // Contacts & Invites Section
          Text(
            context.tr('Contacts & Invites', 'جهات الاتصال والدعوات'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_permissionDenied)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      context.tr(
                        'Contacts permission is only used to match phone numbers (hashed) with friends and send SMS invites.',
                        'يُستخدم إذن جهات الاتصال فقط لمطابقة أرقام الهواتف (مشفرة) مع الأصدقاء وإرسال دعوات SMS.',
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _loadContacts,
                      child: Text(
                        context.tr(
                          'Grant Contacts Access',
                          'السماح بالوصول لجهات الاتصال',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else ...[
            if (_matchedUsers.isEmpty && _inviteContacts.isEmpty)
              Center(
                child: FilledButton.icon(
                  onPressed: _loadContacts,
                  icon: const Icon(Icons.contacts),
                  label: Text(
                    context.tr(
                      'Find Friends from Contacts',
                      'ابحث عن الأصدقاء من جهات الاتصال',
                    ),
                  ),
                ),
              ),
            if (_matchedUsers.isNotEmpty) ...[
              Text(
                context.tr('On U3m Alarm', 'على منبه U3m'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ..._matchedUsers.map(
                (u) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(u.displayName),
                    subtitle: Text(
                      '${context.tr('Timezone', 'المنطقة الزمنية')}: ${u.timezoneId}',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_inviteContacts.isNotEmpty) ...[
              Text(
                context.tr('Invite via SMS', 'دعوة عبر SMS'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              ..._inviteContacts.take(30).map(
                    (c) => Card(
                      child: ListTile(
                        leading:
                            const CircleAvatar(child: Icon(Icons.person_add)),
                        title: Text(c.displayName),
                        subtitle: Text(c.phones.first.number),
                        trailing: OutlinedButton(
                          onPressed: () => _sendSmsInvite(c),
                          child: Text(context.tr('Invite', 'دعوة')),
                        ),
                      ),
                    ),
                  ),
            ],
          ],
        ],
      ),
    );
  }
}

class _QuickSocialCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _QuickSocialCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withOpacity(0.80)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.45),
            blurRadius: 14,
            spreadRadius: 1,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.20),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: Colors.white, size: 22),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.88),
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
