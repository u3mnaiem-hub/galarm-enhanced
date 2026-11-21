import 'dart:async';
import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/remote/fcm_alarm_service.dart';
import '../../domain/entities/alarm.dart';
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
  StreamSubscription<List<Alarm>>? _sharedByUidSub;
  StreamSubscription<List<Alarm>>? _sharedByPhoneSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_syncAlarmsWithNative);
    Future.microtask(_initFirebaseSyncAndFcm);
  }

  @override
  void dispose() {
    _sharedByUidSub?.cancel();
    _sharedByPhoneSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initFirebaseSyncAndFcm() async {
    final fs = ref.read(firestoreServiceProvider);
    final repo = ref.read(alarmRepositoryProvider);
    final uid = ref.read(currentUserIdProvider);
    final phone = ref.read(currentUserPhoneProvider);
    if (fs == null || uid == 'local_user') return;

    await FcmAlarmService.initializeAndRegisterToken(
      uid: uid,
      phoneNumber: phone,
      firestore: fs,
      repo: repo,
    );

    _sharedByUidSub?.cancel();
    _sharedByUidSub = fs.watchSharedAlarmsForUser(uid).listen((alarms) async {
      for (final a in alarms) {
        if (a.ownerId != uid) {
          await repo.saveIncomingSharedAlarm(a);
        }
      }
    });

    if (phone.isNotEmpty) {
      _sharedByPhoneSub?.cancel();
      _sharedByPhoneSub =
          fs.watchSharedAlarmsForPhone(phone).listen((alarms) async {
        for (final a in alarms) {
          if (a.ownerId != uid) {
            await repo.saveIncomingSharedAlarm(a);
          }
        }
      });
    }
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
            label: context.tr('Buddies', 'الأصدقاء'),
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
