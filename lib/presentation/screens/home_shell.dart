import 'package:flutter/material.dart';
import 'alarms_tab.dart';
import 'notifications_tab.dart';
import 'contacts_groups_tab.dart';
import 'settings_tab.dart';
import 'alarm_editor_screen.dart';
import '../widgets/voice_assistant_sheet.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _pages = [
    AlarmsTab(),
    NotificationsTab(),
    ContactsGroupsTab(),
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
                  tooltip: 'Voice Assistant',
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
                  label: const Text('New Alarm'),
                ),
              ],
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.alarm_outlined),
            selectedIcon: Icon(Icons.alarm),
            label: 'Alarms',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_outlined),
            selectedIcon: Icon(Icons.notifications),
            label: 'Notifications',
          ),
          NavigationDestination(
            icon: Icon(Icons.group_outlined),
            selectedIcon: Icon(Icons.group),
            label: 'Groups',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
