import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

class SettingsTab extends ConsumerWidget {
  const SettingsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final use24h = ref.watch(use24HourFormatProvider);
    final locale = ref.watch(localeProvider);
    final blockedAsync = ref.watch(blockedUsersStreamProvider);
    final native = ref.watch(nativeAlarmChannelProvider);
    final db = ref.watch(appDatabaseProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: const Text('Theme'),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              items: const [
                DropdownMenuItem(value: ThemeMode.system, child: Text('System')),
                DropdownMenuItem(value: ThemeMode.light, child: Text('Light')),
                DropdownMenuItem(value: ThemeMode.dark, child: Text('Dark')),
              ],
              onChanged: (v) {
                if (v != null) ref.read(themeModeProvider.notifier).state = v;
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: const Text('Language'),
            trailing: DropdownButton<String>(
              value: locale?.languageCode ?? 'system',
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System')),
                DropdownMenuItem(value: 'en', child: Text('English')),
                DropdownMenuItem(value: 'ar', child: Text('العربية')),
              ],
              onChanged: (v) {
                if (v == 'system') {
                  ref.read(localeProvider.notifier).state = null;
                } else if (v != null) {
                  ref.read(localeProvider.notifier).state = Locale(v);
                }
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: const Text('24-Hour Time Format'),
            value: use24h,
            onChanged: (v) => ref.read(use24HourFormatProvider.notifier).state = v,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.battery_saver),
            title: const Text('Battery & OEM Autostart Help'),
            subtitle: const Text('Xiaomi, Oppo, Samsung & Huawei reliability guide'),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('OEM Battery & Autostart Guide'),
                content: const SingleChildScrollView(
                  child: Text(
                    '• Xiaomi (MIUI/HyperOS): Enable Autostart + set Battery Saver to "No restrictions".\n'
                    '• Samsung: Add U3m Alarm to "Never sleeping apps" in Device Care.\n'
                    '• Oppo/Realme: Allow Background Activity & Auto-launch in App Info.\n'
                    '• Huawei: Disable "Manage automatically" in App Launch and enable Auto-launch + Run in background.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => native.requestIgnoreBatteryOptimizations(),
                    child: const Text('Disable Battery Optimization'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: const Text('Blocked Users'),
            subtitle: Text(
              '${blockedAsync.valueOrNull?.length ?? 0} blocked',
            ),
            onTap: () {
              final list = blockedAsync.valueOrNull ?? const [];
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Blocked Users'),
                  content: list.isEmpty
                      ? const Text('No blocked users.')
                      : SizedBox(
                          width: double.maxFinite,
                          child: ListView(
                            shrinkWrap: true,
                            children: list
                                .map((u) => ListTile(
                                      title: Text(u.displayName),
                                      trailing: TextButton(
                                        onPressed: () => db.unblockUser(u.uid),
                                        child: const Text('Unblock'),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About / عن البرنامج'),
            subtitle: const Text('Developer: yousry mahmoud naiem | يسري محمود نعيم'),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: const Text('About U3m Alarm'),
                content: const Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'U3m Alarm',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('Smart Personal & Social Alarm Application'),
                    SizedBox(height: 12),
                    Text(
                      'Developer: yousry mahmoud naiem\nالمطور: يسري محمود نعيم',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign Out'),
            onTap: () async {
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text(
              'Delete Account & Data',
              style: TextStyle(color: Colors.red),
            ),
            onTap: () async {
              try {
                await FirebaseAuth.instance.currentUser?.delete();
              } catch (_) {}
            },
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
