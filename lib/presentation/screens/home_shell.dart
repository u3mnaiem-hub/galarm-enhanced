import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/remote/fcm_alarm_service.dart';
import '../../data/remote/firestore_service.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';
import 'alarms_tab.dart';
import 'buddies_screen.dart';
import 'groups_screen.dart';
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

    // Start the native Android background sync service so buddy & group alarms
    // are received and scheduled even while the phone is locked or app is closed.
    try {
      if (Firebase.apps.isNotEmpty) {
        final projectId = Firebase.app().options.projectId;
        final normalizedPhone =
            phone.isNotEmpty ? FirestoreService.normalizePhoneNumber(phone) : '';
        String idToken = '';
        try {
          idToken = await FirebaseAuth.instance.currentUser?.getIdToken() ?? '';
        } catch (_) {}
        await ref.read(nativeAlarmChannelProvider).startSharedAlarmSync(
              projectId: projectId,
              uid: uid,
              phone: normalizedPhone,
              idToken: idToken,
            );
      }
    } catch (_) {}

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
    BuddiesScreen(),
    GroupsScreen(),
    NotificationsTab(),
    SettingsTab(),
  ];

  @override
  Widget build(BuildContext context) {
    // Re-attach Firestore shared-alarm listeners if the user signs in from Settings
    // after HomeShell is already mounted.
    ref.listen<String>(currentUserIdProvider, (prev, next) {
      if (next != prev && next != 'local_user') {
        _initFirebaseSyncAndFcm();
      }
    });
    ref.listen<String>(currentUserPhoneProvider, (prev, next) {
      if (next != prev && next.isNotEmpty) {
        _initFirebaseSyncAndFcm();
      }
    });

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
            icon: const Icon(Icons.people_outline),
            selectedIcon: const Icon(Icons.people_alt_rounded),
            label: context.tr('Buddies', 'الأصدقاء'),
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
