import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/tr.dart';
import '../providers/app_providers.dart';

class SettingsTab extends ConsumerStatefulWidget {
  const SettingsTab({super.key});

  @override
  ConsumerState<SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<SettingsTab> {
  final AudioPlayer _previewPlayer = AudioPlayer();
  bool _isPreviewing = false;

  @override
  void dispose() {
    _previewPlayer.dispose();
    super.dispose();
  }

  Future<void> _pickDefaultRingtone() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio);
    if (result != null && result.files.single.path != null) {
      final pickedPath = result.files.single.path!;
      final fileName = p.basename(pickedPath);
      String finalPath = pickedPath;
      try {
        final docsDir = await getApplicationDocumentsDirectory();
        final ringtonesDir = Directory(p.join(docsDir.path, 'ringtones'));
        if (!await ringtonesDir.exists()) {
          await ringtonesDir.create(recursive: true);
        }
        final destPath = p.join(ringtonesDir.path, fileName);
        if (pickedPath != destPath) {
          await File(pickedPath).copy(destPath);
        }
        finalPath = destPath;
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('default_ringtone_uri', finalPath);
      await prefs.setString('default_ringtone_name', fileName);

      ref.read(defaultRingtoneUriProvider.notifier).state = finalPath;
      ref.read(defaultRingtoneNameProvider.notifier).state = fileName;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Main default ringtone set to: $fileName',
                'تم تعيين نغمة المنبه الرئيسية: $fileName',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<void> _resetDefaultRingtone() async {
    if (_isPreviewing) {
      await _previewPlayer.stop();
      setState(() => _isPreviewing = false);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('default_ringtone_uri', 'default');
    await prefs.setString('default_ringtone_name', '');
    ref.read(defaultRingtoneUriProvider.notifier).state = 'default';
    ref.read(defaultRingtoneNameProvider.notifier).state = '';
  }

  Future<void> _togglePreview(String ringtoneUri) async {
    if (_isPreviewing) {
      await _previewPlayer.stop();
      setState(() => _isPreviewing = false);
      return;
    }
    if (ringtoneUri.startsWith('/')) {
      await _previewPlayer.setVolume(0.9);
      await _previewPlayer.play(DeviceFileSource(ringtoneUri));
      setState(() => _isPreviewing = true);
    }
  }

  String _generateBackupFileName() {
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    return 'u3m_alarms_backup_$stamp.json';
  }

  Future<void> _saveBackupToPhone() async {
    try {
      final repo = ref.read(alarmRepositoryProvider);
      final native = ref.read(nativeAlarmChannelProvider);
      final defaultUri = ref.read(defaultRingtoneUriProvider);
      final defaultName = ref.read(defaultRingtoneNameProvider);
      final jsonStr = await repo.exportAlarmsBackupJson(
        defaultRingtoneUri: defaultUri,
        defaultRingtoneName: defaultName,
      );
      final fileName = _generateBackupFileName();

      // Save directly to Downloads and also let user pick a folder if desired
      final savedInDownloads = await native.saveBackupToDownloads(
        fileName: fileName,
        content: jsonStr,
      );

      if (!mounted) return;
      if (savedInDownloads != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Backup saved to phone: $savedInDownloads',
                'تم حفظ النسخة الاحتياطية على الهاتف في: $savedInDownloads',
              ),
            ),
            action: SnackBarAction(
              label: context.tr('Choose Folder', 'اختيار مجلد آخر'),
              onPressed: () {
                native.saveBackupWithPicker(
                  fileName: fileName,
                  content: jsonStr,
                );
              },
            ),
          ),
        );
      } else {
        final ok = await native.saveBackupWithPicker(
          fileName: fileName,
          content: jsonStr,
        );
        if (mounted && ok) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.tr(
                  'Backup saved successfully!',
                  'تم حفظ النسخة الاحتياطية بنجاح!',
                ),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Backup error: $e', 'خطأ أثناء حفظ النسخة: $e'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _shareBackupOutsidePhone() async {
    try {
      final repo = ref.read(alarmRepositoryProvider);
      final native = ref.read(nativeAlarmChannelProvider);
      final defaultUri = ref.read(defaultRingtoneUriProvider);
      final defaultName = ref.read(defaultRingtoneNameProvider);
      final jsonStr = await repo.exportAlarmsBackupJson(
        defaultRingtoneUri: defaultUri,
        defaultRingtoneName: defaultName,
      );
      final fileName = _generateBackupFileName();
      await native.shareBackupFile(
        fileName: fileName,
        content: jsonStr,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Share error: $e', 'خطأ أثناء المشاركة: $e'),
            ),
          ),
        );
      }
    }
  }

  Future<void> _restoreBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      if (result == null || result.files.single.path == null) return;

      final file = File(result.files.single.path!);
      final rawJson = await file.readAsString();
      final repo = ref.read(alarmRepositoryProvider);
      final restoredCount = await repo.importAlarmsBackupJson(rawJson);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Successfully restored $restoredCount alarms!',
                'تم استعادة $restoredCount منبه بنجاح!',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr(
                'Invalid backup file or restore error: $e',
                'ملف النسخة الاحتياطية غير صالح أو حدث خطأ: $e',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final use24h = ref.watch(use24HourFormatProvider);
    final locale = ref.watch(localeProvider);
    final defaultRingtoneUri = ref.watch(defaultRingtoneUriProvider);
    final defaultRingtoneName = ref.watch(defaultRingtoneNameProvider);
    final native = ref.watch(nativeAlarmChannelProvider);

    final isCustomDefault =
        defaultRingtoneUri != 'default' && defaultRingtoneUri.isNotEmpty;
    final displayRingtoneName = isCustomDefault
        ? (defaultRingtoneName.isNotEmpty
            ? defaultRingtoneName
            : p.basename(defaultRingtoneUri))
        : context.tr('System Default Ringtone', 'نغمة النظام الافتراضية');

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
                DropdownMenuItem(
                  value: ThemeMode.system,
                  child: Text(context.tr('System', 'النظام')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.light,
                  child: Text(context.tr('Light', 'فاتح')),
                ),
                DropdownMenuItem(
                  value: ThemeMode.dark,
                  child: Text(context.tr('Dark', 'داكن')),
                ),
              ],
              onChanged: (v) async {
                if (v != null) {
                  ref.read(themeModeProvider.notifier).state = v;
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('theme_mode', v.name);
                }
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(context.tr('Language', 'اللغة')),
            trailing: DropdownButton<String>(
              value: locale?.languageCode ?? 'system',
              items: [
                DropdownMenuItem(
                  value: 'system',
                  child: Text(context.tr('System', 'النظام')),
                ),
                const DropdownMenuItem(value: 'en', child: Text('English')),
                const DropdownMenuItem(value: 'ar', child: Text('العربية')),
              ],
              onChanged: (v) async {
                final prefs = await SharedPreferences.getInstance();
                if (v == 'system') {
                  ref.read(localeProvider.notifier).state = null;
                  await prefs.remove('locale_code');
                } else if (v != null) {
                  ref.read(localeProvider.notifier).state = Locale(v);
                  await prefs.setString('locale_code', v);
                }
              },
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: Text(context.tr('24-Hour Time Format', 'نظام 24 ساعة')),
            value: use24h,
            onChanged: (v) async {
              ref.read(use24HourFormatProvider.notifier).state = v;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('use_24h_format', v);
            },
          ),
          const Divider(),

          // Main Default Ringtone Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              context.tr(
                'Main Default Alarm Ringtone',
                'نغمة المنبه الرئيسية (الافتراضية)',
              ),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.music_note),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayRingtoneName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              context.tr(
                                'Applied automatically to all new alarms',
                                'تُطبق تلقائياً كافتراضية لكل المنبهات الجديدة',
                              ),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (isCustomDefault && defaultRingtoneUri.startsWith('/'))
                        IconButton.filledTonal(
                          onPressed: () => _togglePreview(defaultRingtoneUri),
                          icon: Icon(
                            _isPreviewing ? Icons.stop : Icons.play_arrow,
                          ),
                          tooltip: context.tr('Preview', 'معاينة'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _pickDefaultRingtone,
                        icon: const Icon(Icons.library_music_outlined, size: 18),
                        label: Text(
                          context.tr(
                            'Choose Main Ringtone',
                            'اختيار نغمة رئيسية من الهاتف',
                          ),
                        ),
                      ),
                      if (isCustomDefault)
                        TextButton.icon(
                          onPressed: _resetDefaultRingtone,
                          icon: const Icon(Icons.restore, size: 18),
                          label: Text(
                            context.tr(
                              'Reset to System Tone',
                              'استعادة نغمة النظام',
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Divider(),

          // Backup & Restore Section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              context.tr(
                'Backup & Restore Alarms',
                'النسخ الاحتياطي واستعادة المنبهات',
              ),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: Text(
                    context.tr(
                      'Save Backup to Phone',
                      'حفظ نسخة احتياطية على الموبايل',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      'Store a backup file of all alarms in Downloads or a folder',
                      'تخزين ملف نسخة احتياطية لكل المنبهات على الهاتف',
                    ),
                  ),
                  onTap: _saveBackupToPhone,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: Text(
                    context.tr(
                      'Share / Send Backup Outside Phone',
                      'إرسال ومشاركة النسخة الاحتياطية خارج الموبايل',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      'Send backup via WhatsApp, Telegram, Drive, Email, or Bluetooth',
                      'مشاركة وإرسال النسخة عبر واتساب أو تيليجرام أو درايف أو بلوتوث',
                    ),
                  ),
                  onTap: _shareBackupOutsidePhone,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.settings_backup_restore),
                  title: Text(
                    context.tr(
                      'Restore Backup',
                      'استعادة النسخة الاحتياطية',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      'Import alarms from a saved backup file',
                      'استرجاع كل المنبهات من ملف نسخة احتياطية محفوظ',
                    ),
                  ),
                  onTap: _restoreBackup,
                ),
              ],
            ),
          ),
          const Divider(),

          ListTile(
            leading: const Icon(Icons.battery_saver),
            title: Text(
              context.tr(
                'Battery & OEM Autostart Help',
                'مساعدة البطارية والتشغيل التلقائي',
              ),
            ),
            subtitle: Text(
              context.tr(
                'Xiaomi, Oppo, Samsung & Huawei reliability guide',
                'دليل الاعتمادية لأجهزة شاومي وأوبو وسامسونج وهواوي',
              ),
            ),
            onTap: () => showDialog(
              context: context,
              builder: (_) => AlertDialog(
                title: Text(
                  context.tr(
                    'OEM Battery & Autostart Guide',
                    'دليل البطارية والتشغيل التلقائي',
                  ),
                ),
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
                    child: Text(
                      context.tr(
                        'Disable Battery Optimization',
                        'تعطيل تحسين البطارية',
                      ),
                    ),
                  ),
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
            leading: const Icon(Icons.info_outline),
            title: Text(context.tr('About', 'عن البرنامج')),
            subtitle: Text(
              context.tr(
                'Developer: yousry mahmoud naiem',
                'المطور: يسري محمود نعيم',
              ),
            ),
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
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      context.tr(
                        'Smart Personal Alarm Application',
                        'تطبيق منبه شخصي ذكي',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.tr(
                        'Developer: yousry mahmoud naiem',
                        'المطور: يسري محمود نعيم',
                      ),
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
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
