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
    final skipVoiceConfirm = ref.watch(skipVoiceConfirmationProvider);
    final geminiApiKey = ref.watch(geminiApiKeyProvider);
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

          // Voice Assistant Settings
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              context.tr('Voice Assistant', 'المساعد الصوتي'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.bolt_rounded),
                  title: Text(
                    context.tr(
                      'Skip Voice Confirmation',
                      'حفظ المنبه الصوتي مباشرة بدون تأكيد',
                    ),
                  ),
                  subtitle: Text(
                    context.tr(
                      'Save parsed alarms immediately without asking first',
                      'حفظ المنبه فور فهمه بدون السؤال للتأكيد',
                    ),
                  ),
                  value: skipVoiceConfirm,
                  onChanged: (v) async {
                    ref.read(skipVoiceConfirmationProvider.notifier).state = v;
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('skip_voice_confirmation', v);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(
                    context.tr(
                      'Gemini AI Parser Key (Optional)',
                      'مفتاح Gemini للذكاء الاصطناعي (اختياري)',
                    ),
                  ),
                  subtitle: Text(
                    geminiApiKey.trim().isNotEmpty
                        ? context.tr(
                            'Configured (stored locally on device)',
                            'مُفعّل (محفوظ محلياً على جهازك)',
                          )
                        : context.tr(
                            'Using smart offline Egyptian Arabic parser',
                            'يعمل حالياً بالمحلل المحلي للعامية المصرية بدون إنترنت',
                          ),
                  ),
                  onTap: () async {
                    final ctrl = TextEditingController(text: geminiApiKey);
                    final saved = await showDialog<String>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(
                          context.tr(
                            'Gemini API Key',
                            'مفتاح Gemini API',
                          ),
                        ),
                        content: TextField(
                          controller: ctrl,
                          obscureText: true,
                          decoration: InputDecoration(
                            hintText: 'AIza...',
                            labelText: context.tr(
                              'Paste API key (leave empty for offline mode)',
                              'الصق المفتاح (أو اتركه فارغاً للوضع المحلي)',
                            ),
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            child: Text(context.tr('Cancel', 'إلغاء')),
                          ),
                          FilledButton(
                            onPressed: () =>
                                Navigator.of(ctx).pop(ctrl.text.trim()),
                            child: Text(context.tr('Save', 'حفظ')),
                          ),
                        ],
                      ),
                    );
                    ctrl.dispose();
                    if (saved != null) {
                      ref.read(geminiApiKeyProvider.notifier).state = saved;
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setString('gemini_api_key', saved);
                    }
                  },
                ),
              ],
            ),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              context.tr('About the App', 'عن التطبيق'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(14, 6, 14, 28),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0A1F4D), Color(0xFF10347A)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: Colors.white.withOpacity(0.18),
                width: 1.1,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF051230).withOpacity(0.75),
                  blurRadius: 24,
                  spreadRadius: 2.5,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 12,
                  spreadRadius: 0,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.alarm_on_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      context.tr('About the App', 'عن التطبيق'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'تطبيق U3m alarm الاصدار الاول ١.٣ تطبيق منبه مرن يسمح بكل التخصيصات لتناسب احتياجاتك',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    height: 1.65,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.code_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'تطوير/Yousry Mahmoud Naiem',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
