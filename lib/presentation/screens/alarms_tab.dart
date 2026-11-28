import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/entities/alarm.dart';
import '../../domain/services/recurrence_calculator.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'alarm_chat_screen.dart';
import 'alarm_editor_screen.dart';
import 'alarm_history_screen.dart';

class AlarmsTab extends ConsumerStatefulWidget {
  const AlarmsTab({super.key});

  @override
  ConsumerState<AlarmsTab> createState() => _AlarmsTabState();
}

class _AlarmsTabState extends ConsumerState<AlarmsTab>
    with WidgetsBindingObserver {
  AlarmType? _filterType; // null = All
  bool _fullScreenOk = true;
  bool _overlayOk = true;
  bool _bannerDismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_checkDisplayPermissions);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkDisplayPermissions();
    }
  }

  Future<void> _checkDisplayPermissions() async {
    try {
      final native = ref.read(nativeAlarmChannelProvider);
      final fs = await native.canUseFullScreenIntent();
      final ov = await native.canDrawOverlays();
      if (mounted) {
        setState(() {
          _fullScreenOk = fs;
          _overlayOk = ov;
        });
      }
    } catch (_) {}
  }

  Future<void> _confirmDelete(
    BuildContext context,
    Alarm alarm,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('Delete Alarm', 'حذف المنبه')),
        content: Text(
          context.tr(
            'Are you sure you want to delete "${alarm.title}"?',
            'هل أنت متأكد من حذف المنبه "${alarm.title}"؟',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('Cancel', 'إلغاء')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('Delete', 'حذف')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(alarmRepositoryProvider).deleteAlarm(alarm.id);
    }
  }

  Color _accentForAlarm(Alarm alarm, ColorScheme cs, bool isMissed) {
    if (isMissed) return const Color(0xFFDC2626);
    if (!alarm.isEnabled) return cs.outline;
    switch (alarm.type) {
      case AlarmType.group:
        return AppTheme.groupTeal;
      case AlarmType.buddy:
        return AppTheme.buddyPurple;
      case AlarmType.personal:
        return cs.primary;
    }
  }

  IconData _iconForType(AlarmType type) {
    switch (type) {
      case AlarmType.group:
        return Icons.groups_rounded;
      case AlarmType.buddy:
        return Icons.people_alt_rounded;
      case AlarmType.personal:
        return Icons.person_rounded;
    }
  }

  String _labelForType(BuildContext context, AlarmType type) {
    switch (type) {
      case AlarmType.group:
        return context.tr('GROUP', 'مجموعة');
      case AlarmType.buddy:
        return context.tr('BUDDY', 'صديق');
      case AlarmType.personal:
        return context.tr('PERSONAL', 'شخصي');
    }
  }

  @override
  Widget build(BuildContext context) {
    final alarmsAsync = ref.watch(alarmsStreamProvider);
    final use24h = ref.watch(use24HourFormatProvider);
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Icon(Icons.alarm_rounded, size: 22),
            const SizedBox(width: 8),
            Text(context.tr('U3m Alarm', 'منبه U3m')),
          ],
        ),
      ),
      body: Column(
        children: [
          if (!_bannerDismissed && (!_fullScreenOk || !_overlayOk))
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.fullscreen_rounded,
                    color: Color(0xFFB45309),
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      !_fullScreenOk
                          ? context.tr(
                              'Enable Full-Screen Alerts so alarms show over lock screen.',
                              'فعّل إذن «إشعارات ملء الشاشة» ليظهر المنبّه كاملاً فوق شاشة القفل.',
                            )
                          : context.tr(
                              'Enable "Appear on top" for reliable full-screen alarm display.',
                              'فعّل إذن «الظهور فوق التطبيقات» لضمان فتح شاشة المنبّه الكاملة.',
                            ),
                      style: const TextStyle(
                        color: Color(0xFF78350F),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor: const Color(0xFFD97706),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () {
                      final native = ref.read(nativeAlarmChannelProvider);
                      if (!_fullScreenOk) {
                        native.openFullScreenIntentSettings();
                      } else {
                        native.openOverlaySettings();
                      }
                    },
                    child: Text(
                      context.tr('Enable', 'تفعيل'),
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16, color: Color(0xFF92400E)),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => setState(() => _bannerDismissed = true),
                  ),
                ],
              ),
            ),
          // Modern filter bar for Personal / Groups / Buddy
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _FilterPill(
                    label: context.tr('All', 'الكل'),
                    selected: _filterType == null,
                    color: cs.primary,
                    onTap: () => setState(() => _filterType = null),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: context.tr('Personal', 'شخصي'),
                    icon: Icons.person_outline,
                    selected: _filterType == AlarmType.personal,
                    color: cs.primary,
                    onTap: () =>
                        setState(() => _filterType = AlarmType.personal),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: context.tr('Groups', 'مجموعات'),
                    icon: Icons.groups_outlined,
                    selected: _filterType == AlarmType.group,
                    color: AppTheme.groupTeal,
                    onTap: () => setState(() => _filterType = AlarmType.group),
                  ),
                  const SizedBox(width: 8),
                  _FilterPill(
                    label: context.tr('Buddy', 'صديق'),
                    icon: Icons.people_outline,
                    selected: _filterType == AlarmType.buddy,
                    color: AppTheme.buddyPurple,
                    onTap: () => setState(() => _filterType = AlarmType.buddy),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: alarmsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text(': $e')),
              data: (allAlarms) {
                final alarms = _filterType == null
                    ? allAlarms
                    : allAlarms.where((a) => a.type == _filterType).toList();

                if (alarms.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.alarm_add_rounded,
                            size: 56,
                            color: cs.primary.withOpacity(0.45),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _filterType == null
                                ? context.tr(
                                    'No alarms yet. Tap + to create one.',
                                    'لا توجد منبهات بعد. اضغط + لإضافة منبه.',
                                  )
                                : context.tr(
                                    'No alarms in this category yet.',
                                    'لا توجد منبهات في هذا القسم بعد.',
                                  ),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 118),
                  itemCount: alarms.length,
                  itemBuilder: (context, index) {
                    final alarm = alarms[index];
                    final nextUtc =
                        RecurrenceCalculator.computeNextFireUtc(alarm) ??
                            alarm.startAtUtc;
                    final localTime = nextUtc.toLocal();
                    final fmt = context.df(use24h ? 'HH:mm' : 'hh:mm a');
                    final dateFmt = context.df('EEE, d MMM');
                    final isMissed = alarm.state == AlarmState.missed;
                    final accent = _accentForAlarm(alarm, cs, isMissed);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? (alarm.isEnabled
                                ? const Color(0xFF16223A)
                                : const Color(0xFF11192B))
                            : (alarm.isEnabled
                                ? Colors.white
                                : const Color(0xFFF8FAFC)),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: alarm.isEnabled
                              ? accent.withOpacity(isDark ? 0.45 : 0.30)
                              : cs.outlineVariant.withOpacity(0.55),
                          width: 1.2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withOpacity(0.80)
                                : const Color(0xFF0F172A).withOpacity(0.30),
                            blurRadius: 18,
                            spreadRadius: 1.5,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: isDark
                                ? Colors.black.withOpacity(0.55)
                                : accent.withOpacity(0.18),
                            blurRadius: 8,
                            spreadRadius: 0,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  AlarmEditorScreen(existing: alarm),
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(17),
                            child: Container(
                              decoration: BoxDecoration(
                                border: BorderDirectional(
                                  start: BorderSide(
                                    color: accent,
                                    width: 5,
                                  ),
                                ),
                              ),
                              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          gradient: alarm.isEnabled
                                              ? LinearGradient(
                                                  colors: [
                                                    accent.withOpacity(
                                                        isDark ? 0.35 : 0.16),
                                                    accent.withOpacity(
                                                        isDark ? 0.20 : 0.08),
                                                  ],
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                )
                                              : null,
                                          color: alarm.isEnabled
                                              ? null
                                              : cs.surfaceContainerHighest,
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          fmt.format(localTime),
                                          style: TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w800,
                                            color: isMissed
                                                ? const Color(0xFFDC2626)
                                                : (alarm.isEnabled
                                                    ? (isDark
                                                        ? Colors.white
                                                        : accent)
                                                    : cs.outline),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              alarm.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 14.5,
                                                fontWeight: FontWeight.w700,
                                                color: alarm.isEnabled
                                                    ? cs.onSurface
                                                    : cs.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '${dateFmt.format(localTime)}${alarm.notes.isNotEmpty ? " • ${alarm.notes}" : ""}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 11.5,
                                                color: cs.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        height: 30,
                                        child: Transform.scale(
                                          scale: 0.82,
                                          child: Switch(
                                            value: alarm.isEnabled,
                                            activeColor: accent,
                                            onChanged: (val) {
                                              ref
                                                  .read(alarmRepositoryProvider)
                                                  .saveAlarm(
                                                    alarm.copyWith(
                                                      isEnabled: val,
                                                      state: val
                                                          ? AlarmState.upcoming
                                                          : AlarmState.archived,
                                                    ),
                                                  );
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 5,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color: accent.withOpacity(
                                              isDark ? 0.25 : 0.13),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              _iconForType(alarm.type),
                                              size: 12,
                                              color: isDark
                                                  ? Colors.white
                                                  : accent,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              _labelForType(
                                                  context, alarm.type),
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? Colors.white
                                                    : accent,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (alarm.type != AlarmType.personal &&
                                          alarm.participants.isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerHighest
                                                .withOpacity(0.8),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            alarm.participants
                                                .map((p) => p.displayName)
                                                .take(2)
                                                .join(', ') +
                                                (alarm.participants.length > 2
                                                    ? ' +${alarm.participants.length - 2}'
                                                    : ''),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                      if (alarm.repeatRule.isRecurring)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.secondaryContainer
                                                .withOpacity(0.75),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            context.trLabel(
                                              alarm.repeatRule.displayLabel,
                                            ),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: cs.onSecondaryContainer,
                                            ),
                                          ),
                                        ),
                                      if (isMissed)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.red.withOpacity(0.14),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            context.tr('MISSED', 'فائت'),
                                            style: const TextStyle(
                                              color: Color(0xFFDC2626),
                                              fontSize: 10,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Divider(
                                    height: 1,
                                    color: cs.outlineVariant.withOpacity(0.45),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      _ActionChipButton(
                                        icon: Icons.edit_outlined,
                                        label: context.tr('Edit', 'تعديل'),
                                        color: cs.primary,
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => AlarmEditorScreen(
                                              existing: alarm,
                                            ),
                                          ),
                                        ),
                                      ),
                                      _ActionChipButton(
                                        icon: Icons.delete_outline,
                                        label: context.tr('Delete', 'حذف'),
                                        color: const Color(0xFFDC2626),
                                        onTap: () =>
                                            _confirmDelete(context, alarm),
                                      ),
                                      _ActionChipButton(
                                        icon: Icons.history,
                                        label: context.tr('History', 'السجل'),
                                        color: cs.secondary,
                                        onTap: () => Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) => AlarmHistoryScreen(
                                              alarm: alarm,
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (alarm.type != AlarmType.personal)
                                        _ActionChipButton(
                                          icon: Icons.chat_bubble_outline,
                                          label: context.tr('Chat', 'محادثة'),
                                          color: alarm.type == AlarmType.buddy
                                              ? AppTheme.buddyPurple
                                              : AppTheme.groupTeal,
                                          onTap: () =>
                                              Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => AlarmChatScreen(
                                                alarm: alarm,
                                              ),
                                            ),
                                          ),
                                        ),
                                      _ActionChipButton(
                                        icon: Icons.check_circle_outline,
                                        label: context.tr('Done', 'تم'),
                                        color: const Color(0xFF059669),
                                        bold: true,
                                        onTap: () => ref
                                            .read(alarmRepositoryProvider)
                                            .markOccurrenceDone(alarm),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: selected
          ? color
          : (isDark ? const Color(0xFF152036) : Colors.white),
      borderRadius: BorderRadius.circular(20),
      elevation: selected ? 4 : 2,
      shadowColor: Colors.black.withOpacity(isDark ? 0.5 : 0.16),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 15,
                  color: selected
                      ? Colors.white
                      : (isDark ? Colors.white70 : color),
                ),
                const SizedBox(width: 5),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChipButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool bold;
  final VoidCallback onTap;

  const _ActionChipButton({
    required this.icon,
    required this.label,
    required this.color,
    this.bold = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
