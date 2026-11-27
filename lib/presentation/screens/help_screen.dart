import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/tr.dart';
import '../providers/app_providers.dart';

class HelpScreen extends ConsumerWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final native = ref.watch(nativeAlarmChannelProvider);

    final sections = <_HelpSectionData>[
      _HelpSectionData(
        icon: Icons.alarm_rounded,
        color: cs.primary,
        titleEn: 'Alarm Types (Personal, Buddy, Group)',
        titleAr: 'أنواع المنبّهات (شخصي، صديق، مجموعة)',
        pointsEn: const [
          'Personal Alarm: Rings only on your own phone.',
          'Buddy Alarm: Set an alarm for a friend. It stays visible in your list so you can track, edit, or delete it, and rings ONLY on your buddy’s phone.',
          'Group Alarm: Rings on your phone AND on all group members’ phones at the exact same time.',
        ],
        pointsAr: const [
          'منبّه شخصي: يرن على هاتفك أنت فقط.',
          'منبّه صديق: تضبطه لصديقك فيظهر في قائمتك لمتابعته أو تعديله أو حذفه، ويرن على هاتف صديقك فقط.',
          'منبّه مجموعة: يرن على هاتفك وعلى هواتف جميع أعضاء المجموعة في نفس الوقت.',
        ],
      ),
      _HelpSectionData(
        icon: Icons.people_alt_rounded,
        color: const Color(0xFF7C3AED),
        titleEn: 'Buddies & Groups Setup',
        titleAr: 'الأصدقاء والمجموعات والمشاركة',
        pointsEn: const [
          'Register your phone number in Settings (free and instant, no SMS required) so friends can send you alarms.',
          'Use the Buddies tab to save friends from your contacts or manually by name and phone number.',
          'Use the Groups tab to create independent groups with multiple members for shared reminders and wake-up calls.',
          'Shared alarms automatically sync in the background even when the phone is locked.',
        ],
        pointsAr: const [
          'سجّل رقم هاتفك من الإعدادات (مجاني وفوري بدون رسائل SMS) ليتمكن أصدقاؤك من إرسال منبّهات لك.',
          'من تبويب «الأصدقاء» يمكنك إضافة أصدقائك من جهات الاتصال أو يدوياً بالاسم ورقم الهاتف.',
          'من تبويب «المجموعات» يمكنك إنشاء مجموعات مستقلة وإضافة أعضائها لضبط منبّهات جماعية.',
          'تتم مزامنة المنبّهات المشتركة تلقائياً في الخلفية حتى مع قفل الشاشة.',
        ],
      ),
      _HelpSectionData(
        icon: Icons.touch_app_rounded,
        color: const Color(0xFF059669),
        titleEn: 'Alarm Card Buttons & "Done" Button',
        titleAr: 'أزرار بطاقة المنبّه وفائدة زر «تم»',
        pointsEn: const [
          'Toggle Switch: Quickly turn any alarm ON or OFF.',
          'Edit / Delete: Modify time, ringtone, repeat rules, or remove the alarm.',
          'History: View a log of completed (Done) and missed occurrences with timestamps.',
          'Chat (Buddy/Group): Exchange quick messages related to a shared alarm.',
          'Done (✓): Marks the current occurrence as completed in History, stops ringing/snooze, turns off one-time alarms, or skips today’s ring on recurring alarms while keeping the next occurrence active.',
        ],
        pointsAr: const [
          'مفتاح التفعيل: لتشغيل أو إيقاف المنبّه بلمسة واحدة.',
          'تعديل / حذف: لتغيير الوقت أو النغمة أو التكرار أو حذف المنبّه.',
          'السجل (History): لعرض سجل المواعيد التي تم إنجازها أو التي فاتت بالتاريخ والوقت.',
          'محادثة (Chat): تظهر في منبّهات الأصدقاء والمجموعات لتبادل الرسائل حول المنبّه.',
          'زر «تم» (✓): يسجّل إنجاز المهمة في السجل، يوقف الرنين أو الغفوة، ويُغلق منبّه المرة الواحدة، أو يتخطى رنّة اليوم في المنبّه المتكرر مع إبقائه مفعّلاً للموعد القادم تلقائياً.',
        ],
      ),
      _HelpSectionData(
        icon: Icons.repeat_rounded,
        color: const Color(0xFF0284C7),
        titleEn: 'Flexible & Custom Repeat Rules',
        titleAr: 'خيارات التكرار المرنة والمخصصة',
        pointsEn: const [
          'Supports One-time, Hourly, Daily, Weekly (pick specific weekdays), Monthly, and Yearly alarms.',
          'Custom Repeat: Set intervals like every 2 days, every 3 hours, last day of every month, or the 2nd Saturday of every month.',
          'Missing one occurrence of a recurring alarm never blocks future repetitions.',
        ],
        pointsAr: const [
          'يدعم التكرار لمرة واحدة، كل ساعة، يومياً، أسبوعياً (باختيار أيام محددة)، شهرياً، وسنوياً.',
          'التكرار المخصص: مثل كل يومين، كل 3 ساعات، آخر يوم في الشهر، أو ثاني سبت من كل شهر.',
          'إذا فاتك موعد في منبّه متكرر، فلن يمنع ذلك رنين المواعيد القادمة.',
        ],
      ),
      _HelpSectionData(
        icon: Icons.mic_rounded,
        color: const Color(0xFFEA580C),
        titleEn: 'Voice Assistant & Offline Voice Mode',
        titleAr: 'المساعد الصوتي والوضع الأوفلاين',
        pointsEn: const [
          'Tap the microphone button on the Alarms screen and speak naturally in Arabic or English (e.g., "Wake me up tomorrow at 7 AM" or "صحيني بكرة الساعة 7 الصبح").',
          'Enable "Skip Voice Confirmation" in Settings to save voice alarms immediately.',
          'Offline Mode in Settings lets you download an offline speech engine so voice alarms work even without internet.',
        ],
        pointsAr: const [
          'اضغط على زر الميكروفون في شاشة المنبهات وتحدث بشكل طبيعي بالعامية المصرية أو العربية أو الإنجليزية (مثل: «صحيني بكرة الساعة 7 الصبح» أو «فكرني بالدواء كل يوم الساعة 8 بالليل»).',
          'يمكنك تفعيل «حفظ المنبّه الصوتي مباشرة بدون تأكيد» من الإعدادات للسرعة.',
          'الوضع الأوفلاين في الإعدادات يتيح لك تحميل محرك التعرف الصوتي للعمل بدون إنترنت.',
        ],
      ),
      _HelpSectionData(
        icon: Icons.palette_rounded,
        color: const Color(0xFFE11D48),
        titleEn: 'Themes, Ringtones & Snooze Customization',
        titleAr: 'الثيمات والألوان والنغمات والغفوة',
        pointsEn: const [
          'Color Themes & Dark Mode: Switch between Light, Dark, or System mode and pick your favorite color theme in Settings.',
          'Main Ringtone: Set one custom audio file from your phone as the default for all new alarms, or override per alarm.',
          'Audio Options: Supports gradual volume ramp-up, vibration, and ringing even when the phone is on silent/vibrate.',
          'Snooze: Customize snooze duration, max snooze count, and auto-snooze ring duration.',
        ],
        pointsAr: const [
          'ثيمات الألوان والوضع الليلي: يمكنك اختيار الوضع الفاتح أو الداكن أو حسب النظام، وتغيير لون ثيم التطبيق بالكامل من الإعدادات.',
          'النغمة الرئيسية: اختر ملفاً صوتياً من هاتفك ليكون النغمة الافتراضية لكل المنبهات الجديدة، أو خصص نغمة مختلفة لكل منبّه.',
          'خيارات الصوت: يدعم رفع الصوت التدريجي، الاهتزاز، والرنين حتى لو كان الهاتف في الوضع الصامت.',
          'الغفوة (Snooze): تحكّم في مدة الغفوة وعدد مرات التكرار ومدة الرنين التلقائي.',
        ],
      ),
      _HelpSectionData(
        icon: Icons.backup_rounded,
        color: const Color(0xFF0D9488),
        titleEn: 'Backup & Restore',
        titleAr: 'النسخ الاحتياطي والاستعادة',
        pointsEn: const [
          'Save a complete JSON backup (all alarms, buddies, and groups) directly to your Downloads folder or any chosen folder.',
          'Share your backup outside the phone via WhatsApp, Telegram, Google Drive, or Email.',
          'Restore all your alarms and lists anytime from a saved backup file.',
        ],
        pointsAr: const [
          'احفظ نسخة احتياطية كاملة (كل المنبّهات والأصدقاء والمجموعات) في مجلد التنزيلات أو أي مجلد تختاره.',
          'شارك النسخة الاحتياطية خارج الهاتف عبر واتساب أو تيليجرام أو جوجل درايف أو الإيميل.',
          'استعد جميع منبّهاتك وقوائمك في أي وقت بضغطة زر من ملف النسخة المحفوظ.',
        ],
      ),
      _HelpSectionData(
        icon: Icons.battery_saver_rounded,
        color: const Color(0xFFD97706),
        titleEn: 'Reliability Tips (Samsung, Xiaomi, Oppo, Huawei)',
        titleAr: 'نصائح لضمان رنين المنبّه دائماً',
        pointsEn: const [
          'Allow Notifications and Exact Alarms permissions for U3m Alarm.',
          'Disable Battery Optimization (set Battery to "Unrestricted") so Android does not put the app to sleep.',
          'Samsung: Add U3m Alarm to "Never sleeping apps" in Device Care.',
          'Xiaomi / Oppo / Huawei: Enable Autostart and Background Activity in App Info.',
        ],
        pointsAr: const [
          'تأكد من السماح بأذونات الإشعارات والمنبّهات الدقيقة لتطبيق U3m Alarm.',
          'اضبط استخدام البطارية للتطبيق على «غير مقيد / بدون قيود» حتى لا يوقفه النظام أثناء قفل الشاشة.',
          'سامسونج: أضف U3m Alarm إلى «التطبيقات التي لا تنام أبداً» من العناية بالجهاز.',
          'شاومي / أوبو / هواوي: فعّل «التشغيل التلقائي» و«النشاط في الخلفية» من معلومات التطبيق.',
        ],
      ),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Help & Features Guide', 'المساعدة ودليل المميزات')),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
        children: [
          // Header banner
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  cs.primary,
                  cs.secondary,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withOpacity(0.32),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.help_center_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('Welcome to U3m Alarm', 'مرحباً بك في منبّه U3m'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.tr(
                          'Tap any section below to learn how every feature works.',
                          'اضغط على أي قسم بالأسفل للتعرف على شرح كامل لكل مميزات التطبيق.',
                        ),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.92),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Expandable feature cards
          for (int i = 0; i < sections.length; i++)
            _HelpSectionCard(
              data: sections[i],
              initiallyExpanded: i == 0,
            ),

          const SizedBox(height: 8),
          // Quick action button for battery optimization
          Card(
            child: ListTile(
              leading: Icon(Icons.bolt_rounded, color: cs.primary),
              title: Text(
                context.tr(
                  'Disable Battery Optimization Now',
                  'تعطيل تحسين البطارية الآن',
                ),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                context.tr(
                  'Recommended for reliable lock-screen and buddy alarms',
                  'موصى به لضمان رنين المنبهات ومنبهات الأصدقاء مع قفل الشاشة',
                ),
              ),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () => native.requestIgnoreBatteryOptimizations(),
            ),
          ),
        ],
      ),
    );
  }
}

class _HelpSectionData {
  final IconData icon;
  final Color color;
  final String titleEn;
  final String titleAr;
  final List<String> pointsEn;
  final List<String> pointsAr;

  const _HelpSectionData({
    required this.icon,
    required this.color,
    required this.titleEn,
    required this.titleAr,
    required this.pointsEn,
    required this.pointsAr,
  });
}

class _HelpSectionCard extends StatelessWidget {
  final _HelpSectionData data;
  final bool initiallyExpanded;

  const _HelpSectionCard({
    required this.data,
    this.initiallyExpanded = false,
  });

  @override
  Widget build(BuildContext context) {
    final points = context.isAr ? data.pointsAr : data.pointsEn;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          leading: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: data.color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(data.icon, color: data.color, size: 20),
          ),
          title: Text(
            context.tr(data.titleEn, data.titleAr),
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          children: [
            const Divider(height: 12),
            for (final point in points)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: data.color,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        point,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
