import 'dart:async';
import 'package:drift/drift.dart' hide Column;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/local/app_database.dart';
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

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  int _index = 0;
  StreamSubscription<List<Alarm>>? _sharedByUidSub;
  StreamSubscription<List<Alarm>>? _sharedByPhoneSub;
  StreamSubscription<List<Map<String, dynamic>>>? _statusEventsSub;

  // Red mic button 10-second blinking animation on app start
  late final AnimationController _micBlinkCtrl;
  Timer? _micBlinkStopTimer;
  bool _isMicBlinking = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _micBlinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..repeat(reverse: true);
    _micBlinkStopTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      _micBlinkCtrl.stop();
      setState(() => _isMicBlinking = false);
    });

    Future.microtask(_syncAlarmsWithNative);
    Future.microtask(_initFirebaseSyncAndFcm);
  }

  @override
  void dispose() {
    _micBlinkStopTimer?.cancel();
    _micBlinkCtrl.dispose();
    _sharedByUidSub?.cancel();
    _sharedByPhoneSub?.cancel();
    _statusEventsSub?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _initFirebaseSyncAndFcm() async {
    final fs = ref.read(firestoreServiceProvider);
    final repo = ref.read(alarmRepositoryProvider);
    final db = ref.read(appDatabaseProvider);
    final uid = ref.read(currentUserIdProvider);
    final phone = ref.read(currentUserPhoneProvider);
    if (fs == null || uid == 'local_user') return;

    // 1) Attach real-time Firestore listeners IMMEDIATELY (never block on FCM token)
    _sharedByUidSub?.cancel();
    _sharedByUidSub = fs.watchSharedAlarmsForUser(uid).listen(
      (alarms) async {
        for (final a in alarms) {
          if (a.ownerId != uid) {
            await repo.saveIncomingSharedAlarm(a);
          }
        }
      },
      onError: (_) {},
    );

    if (phone.isNotEmpty) {
      _sharedByPhoneSub?.cancel();
      _sharedByPhoneSub = fs.watchSharedAlarmsForPhone(phone).listen(
        (alarms) async {
          for (final a in alarms) {
            if (a.ownerId != uid) {
              await repo.saveIncomingSharedAlarm(a);
            }
          }
        },
        onError: (_) {},
      );
    }

    // Listen for buddy/group status updates (Done / Missed) to show in Notifications tab
    _statusEventsSub?.cancel();
    _statusEventsSub = fs.watchSharedAlarmStatusEvents(uid).listen(
      (events) async {
        for (final ev in events) {
          final id = (ev['id'] as String?) ?? '';
          final actorUid = (ev['actorUid'] as String?) ?? '';
          if (id.isEmpty || actorUid == uid) continue;

          final actorName = (ev['actorName'] as String?) ?? 'صديق';
          final alarmTitle = (ev['alarmTitle'] as String?) ?? 'منبّه مشترك';
          final alarmId = (ev['alarmId'] as String?) ?? '';
          final status = (ev['status'] as String?) ?? 'done';
          final atMillis = (ev['atMillis'] as num?)?.toInt() ??
              DateTime.now().toUtc().millisecondsSinceEpoch;

          final isDone = status == 'done';
          await db.upsertNotification(
            NotificationsTableCompanion(
              id: Value(id),
              title: Value(
                isDone
                    ? 'أنهى $actorName المنبّه ✓ • $alarmTitle'
                    : 'فات $actorName المنبّه • $alarmTitle',
              ),
              body: Value(
                isDone
                    ? 'تم إيقاف/إنهاء المنبّه بنجاح على هاتف $actorName'
                    : 'لم يرد $actorName على المنبّه في موعده',
              ),
              kind: Value(isDone ? 'buddy_done' : 'buddy_missed'),
              alarmId: Value(alarmId),
              createdAtUtc: Value(
                DateTime.fromMillisecondsSinceEpoch(atMillis, isUtc: true),
              ),
              isRead: const Value(false),
            ),
          );
        }
      },
      onError: (_) {},
    );

    // 2) Flush any queued shared alarms that failed while offline
    unawaited(repo.flushSyncQueue());

    // 3) Start the native Android background sync poller immediately
    unawaited(_refreshNativeSharedSync());

    // 4) Register FCM token in the background (non-blocking)
    unawaited(
      FcmAlarmService.initializeAndRegisterToken(
        uid: uid,
        phoneNumber: phone,
        firestore: fs,
        repo: repo,
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncAlarmsWithNative();
      _refreshNativeSharedSync();
    }
  }

  Future<void> _refreshNativeSharedSync() async {
    final uid = ref.read(currentUserIdProvider);
    final phone = ref.read(currentUserPhoneProvider);
    if (uid == 'local_user' || Firebase.apps.isEmpty) return;
    try {
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
    } catch (_) {}
  }

  Future<void> _syncAlarmsWithNative() async {
    final repo = ref.read(alarmRepositoryProvider);
    await repo.syncNativeEvents();
    await repo.rescheduleAllAlarms();
    unawaited(repo.flushSyncQueue());
  }

  static const _pages = [
    AlarmsTab(),
    BuddiesScreen(),
    GroupsScreen(),
    NotificationsTab(),
    SettingsTab(),
  ];

  Widget _buildRedMicButton(BuildContext context) {
    // Always red regardless of selected color theme, ~4x area of small FAB (84x84 vs 40x40),
    // semi-transparent so underlying text shows through, blinking for first 10 seconds.
    const alwaysRed = Color(0xFFDC2626);
    return AnimatedBuilder(
      animation: _micBlinkCtrl,
      builder: (context, child) {
        final double bgOpacity =
            _isMicBlinking ? (0.28 + (_micBlinkCtrl.value * 0.50)) : 0.68;
        final double iconOpacity =
            _isMicBlinking ? (0.55 + (_micBlinkCtrl.value * 0.45)) : 0.92;
        return Material(
          color: alwaysRed.withOpacity(bgOpacity),
          shape: CircleBorder(
            side: BorderSide(
              color: Colors.white.withOpacity(_isMicBlinking ? 0.55 : 0.35),
              width: 2,
            ),
          ),
          elevation: 6,
          shadowColor: alwaysRed.withOpacity(0.55),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                builder: (_) => const VoiceAssistantSheet(),
              );
            },
            child: Tooltip(
              message: context.tr('Voice Assistant', 'المساعد الصوتي'),
              child: SizedBox(
                width: 84,
                height: 84,
                child: Icon(
                  Icons.mic_rounded,
                  size: 42,
                  color: Colors.white.withOpacity(iconOpacity),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

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

    final notifs = ref.watch(notificationsStreamProvider).valueOrNull ?? const [];
    final unreadCount = notifs.where((n) => !n.isRead).length;

    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      floatingActionButton: _index == 0
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _buildRedMicButton(context),
                const SizedBox(height: 14),
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
            icon: Badge.count(
              count: unreadCount,
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            selectedIcon: Badge.count(
              count: unreadCount,
              isLabelVisible: unreadCount > 0,
              child: const Icon(Icons.notifications),
            ),
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
