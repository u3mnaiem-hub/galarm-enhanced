import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../data/remote/firestore_service.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';

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
            (p) => !matchedHashes.contains(FirestoreService.hashPhoneNumber(p.number)),
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
    final phone = c.phones.first.number;
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: {
        'body': 'Join me on G-Alarm Enhanced so we can share alarms & reminders!',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Groups & Contacts'),
        actions: [
          IconButton(
            onPressed: _loadContacts,
            icon: const Icon(Icons.sync),
            tooltip: 'Match Phone Contacts',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _permissionDenied
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Contacts permission is only used to match phone numbers (hashed) with friends and send SMS invites.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadContacts,
                          child: const Text('Grant Contacts Access'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_matchedUsers.isEmpty && _inviteContacts.isEmpty)
                      Center(
                        child: FilledButton.icon(
                          onPressed: _loadContacts,
                          icon: const Icon(Icons.contacts),
                          label: const Text('Find Friends from Contacts'),
                        ),
                      ),
                    if (_matchedUsers.isNotEmpty) ...[
                      Text('On G-Alarm Enhanced',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ..._matchedUsers.map((u) => ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person)),
                            title: Text(u.displayName),
                            subtitle: Text('Timezone: ${u.timezoneId}'),
                          )),
                      const Divider(height: 24),
                    ],
                    if (_inviteContacts.isNotEmpty) ...[
                      Text('Invite via SMS',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 8),
                      ..._inviteContacts.take(30).map((c) => ListTile(
                            leading: const CircleAvatar(child: Icon(Icons.person_add)),
                            title: Text(c.displayName),
                            subtitle: Text(c.phones.first.number),
                            trailing: OutlinedButton(
                              onPressed: () => _sendSmsInvite(c),
                              child: const Text('Invite'),
                            ),
                          )),
                    ],
                  ],
                ),
    );
  }
}
