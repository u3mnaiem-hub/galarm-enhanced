import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/tr.dart';
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
      appBar: AppBar(title: Text(context.tr('Settings', 'الإعدادات'))),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: Text(context.tr('Theme', 'المظهر')),
            trailing: DropdownButton<ThemeMode>(
              value: themeMode,
              items: [
                DropdownMenuItem(value: ThemeMode.system, child: Text(context.tr('System', 'النظام'))),
                DropdownMenuItem(value: ThemeMode.light, child: Text(context.tr('Light', 'فاتح'))),
                DropdownMenuItem(value: ThemeMode.dark, child: Text(context.tr('Dark', 'داكن'))),
              ],
              onChanged: (v) {
                if (v != null) ref.read(themeModeProvider.notifier).state = v;
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(context.tr('Language', 'اللغة')),
            trailing: DropdownButton<String>(
              value: locale?.languageCode ?? 'system',
              items: [
                DropdownMenuItem(value: 'system', child: Text(context.tr('System', 'النظام'))),
                const DropdownMenuItem(value: 'en', child: Text('English')),
                const DropdownMenuItem(value: 'ar', child: Text('العربية')),
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
            title: Text(context.tr('24-Hour Time Format', 'نظام 24 ساعة')),
            value: use24h,
            onChanged: (v) => ref.read(use24HourFormatProvider.notifier).state = v,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.battery_saver),
            title: Text(context.tr('Battery & OEM Autostart Help', 'مساعدة البطارية والتشغيل التلقائي')),
            subtitle: Text(context.tr('Xiaomi, Oppo, Samsung & Huawei reliability guide', 'دليل الاعتمادية لأجهزة شاومي وأوبو وسامسونج وهواوي')),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(context.tr('OEM Battery & Autostart Guide', 'دليل البطارية والتشغيل التلقائي')),
                content: SingleChildScrollView(
                  child: Text(
                    context.isAr
                        ? '• شاومي (MIUI/HyperOS): فعّل التشغيل التلقائي واضبط توفير البطارية على "بدون قيود".\n• سامسونج: أضف منبه U3m إلى "التطبيقات التي لا تنام أبداً" في العناية بالجهاز.\n• أوبو/ريلمي: اسمح بالنشاط في الخلفية والتشغيل التلقائي من معلومات التطبيق.\n• هواوي: عطّل "الإدارة التلقائية" في تشغيل التطبيقات وفعّل التشغيل التلقائي والعمل في الخلفية.'
                        : '• Xiaomi (MIUI/HyperOS): Enable Autostart + set Battery Saver to "No restrictions".\n'
                            '• Samsung: Add U3m Alarm to "Never sleeping apps" in Device Care.\n'
                            '• Oppo/Realme: Allow Background Activity & Auto-launch in App Info.\n'
                            '• Huawei: Disable "Manage automatically" in App Launch and enable Auto-launch + Run in background.',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => native.requestIgnoreBatteryOptimizations(),
                    child: Text(context.tr('Disable Battery Optimization', 'تعطيل تحسين البطارية')),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr('Close', 'إغلاق')),
                  ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.block),
            title: Text(context.tr('Blocked Users', 'المستخدمون المحظورون')),
            subtitle: Text(
              '${blockedAsync.valueOrNull?.length ?? 0} ${context.tr('blocked', 'محظور')}',
            ),
            onTap: () {
              final list = blockedAsync.valueOrNull ?? const [];
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(context.tr('Blocked Users', 'المستخدمون المحظورون')),
                  content: list.isEmpty
                      ? Text(context.tr('No blocked users.', 'لا يوجد مستخدمون محظورون.'))
                      : SizedBox(
                          width: double.maxFinite,
                          child: ListView(
                            shrinkWrap: true,
                            children: list
                                .map((u) => ListTile(
                                      title: Text(u.displayName),
                                      trailing: TextButton(
                                        onPressed: () => db.unblockUser(u.uid),
                                        child: Text(context.tr('Unblock', 'إلغاء الحظر')),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(context.tr('Close', 'إغلاق')),
                    ),
                  ],
                ),
              );
            },
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(context.tr('About', 'عن البرنامج')),
            subtitle: Text(context.tr('Developer: yousry mahmoud naiem', 'المطور: يسري محمود نعيم')),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(context.tr('About U3m Alarm', 'عن منبه U3m')),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('U3m Alarm', 'منبه U3m'),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(context.tr('Smart Personal & Social Alarm Application', 'تطبيق منبه ذكي شخصي واجتماعي')),
                    const SizedBox(height: 12),
                    Text(
                      context.tr('Developer: yousry mahmoud naiem', 'المطور: يسري محمود نعيم'),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(context.tr('Close', 'إغلاق')),
                  ),
                ],
              ),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout),
            title: Text(context.tr('Sign Out', 'تسجيل الخروج')),
            onTap: () async {
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: Text(
              context.tr('Delete Account & Data', 'حذف الحساب والبيانات'),
              style: const TextStyle(color: Colors.red),
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
