import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';
import 'alarms_tab.dart';
import 'contacts_groups_tab.dart';
import 'notifications_tab.dart';
import 'settings_tab.dart';
import 'alarm_editor_screen.dart';
import '../widgets/voice_assistant_sheet.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_syncAlarmsWithNative);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncAlarmsWithNative();
    }
  }

  Future<void> _syncAlarmsWithNative() async {
    final repo = ref.read(alarmRepositoryProvider);
    await repo.syncNativeEvents();
    await repo.rescheduleAllAlarms();
  }

  static const _pages = [
    AlarmsTab(),
    ContactsGroupsTab(),
    NotificationsTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.small(
                  heroTag: 'voice_assistant_fab',
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const VoiceAssistantSheet(),
                    );
                  },
                  tooltip: context.tr('Voice Assistant', 'المساعد الصوتي'),
                  child: const Icon(Icons.mic),
                ),
                const SizedBox(height: 12),
                FloatingActionButton.extended(
                  heroTag: 'new_alarm_fab',
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const AlarmEditorScreen()),
                    );
                  },
                  icon: const Icon(Icons.add_alarm),
                  label: Text(context.tr('New Alarm', 'منبه جديد')),
                ),
              ],
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.alarm_outlined),
            selectedIcon: const Icon(Icons.alarm),
            label: context.tr('Alarms', 'المنبهات'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.groups_outlined),
            selectedIcon: const Icon(Icons.groups),
            label: context.tr('Groups', 'المجموعات'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.notifications_outlined),
            selectedIcon: const Icon(Icons.notifications),
            label: context.tr('Notifications', 'الإشعارات'),
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: context.tr('Settings', 'الإعدادات'),
          ),
        ],
      ),
    );
  }
}
