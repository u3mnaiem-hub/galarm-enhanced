import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/app_providers.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  final VoidCallback onFinished;
  const OnboardingScreen({super.key, required this.onFinished});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  bool _exactAlarmOk = false;
  bool _fullScreenOk = true;
  bool _batteryOk = false;

  @override
  void initState() {
    super.initState();
    _refreshPermissions();
  }

  Future<void> _refreshPermissions() async {
    final native = ref.read(nativeAlarmChannelProvider);
    final exact = await native.canScheduleExactAlarms();
    final full = await native.canUseFullScreenIntent();
    final bat = await native.isIgnoringBatteryOptimizations();
    if (mounted) {
      setState(() {
        _exactAlarmOk = exact;
        _fullScreenOk = full;
        _batteryOk = bat;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      _IntroSlide(
        icon: Icons.alarm_on_rounded,
        title: 'Social Alarms & Reminders',
        subtitle:
            'Set personal alarms, coordinate group events across timezones, or send buddy reminders.',
      ),
      _IntroSlide(
        icon: Icons.volume_up_rounded,
        title: 'Rings Even on Silent',
        subtitle:
            'Full-screen lock-screen ringing over the ALARM audio stream with smart auto-snooze.',
      ),
      _IntroSlide(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Live Chat & History',
        subtitle:
            'Confirm or decline group alarms, chat per alarm, and track recurring alarm history.',
      ),
      _buildPermissionsWalkthrough(context),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: AlignmentDirectional.topEnd,
              child: TextButton(
                onPressed: widget.onFinished,
                child: const Text('Skip'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _controller,
                onPageChanged: (i) => setState(() => _page = i),
                children: pages,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: List.generate(
                      pages.length,
                      (i) => Container(
                        width: i == _page ? 20 : 8,
                        height: 8,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: i == _page
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: () {
                      if (_page < pages.length - 1) {
                        _controller.nextPage(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeOut,
                        );
                      } else {
                        widget.onFinished();
                      }
                    },
                    child: Text(_page == pages.length - 1 ? 'Get Started' : 'Next'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionsWalkthrough(BuildContext context) {
    final native = ref.read(nativeAlarmChannelProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Keep Your Alarms Reliable',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        const Text(
          'Grant these permissions so alarms ring on time even when the phone is locked or in Doze mode. You can change any of them later in Settings.',
        ),
        const SizedBox(height: 16),
        _PermissionTile(
          title: 'Exact Alarms (Android 12+)',
          subtitle: 'Required to fire alarms at the exact second.',
          granted: _exactAlarmOk,
          onTap: () async {
            await native.openExactAlarmSettings();
            await _refreshPermissions();
          },
        ),
        _PermissionTile(
          title: 'Full-Screen Alarm UI (Android 14+)',
          subtitle: 'Shows Done / Snooze / Dismiss over the lock screen.',
          granted: _fullScreenOk,
          onTap: () async {
            await native.openFullScreenIntentSettings();
            await _refreshPermissions();
          },
        ),
        _PermissionTile(
          title: 'Ignore Battery Optimization',
          subtitle: 'Prevents Xiaomi, Oppo, Samsung & Huawei from killing alarms.',
          granted: _batteryOk,
          onTap: () async {
            await native.requestIgnoreBatteryOptimizations();
            await _refreshPermissions();
          },
        ),
        _PermissionTile(
          title: 'Notifications',
          subtitle: 'Required for ringing alerts, chat, and buddy updates.',
          granted: true,
          onTap: () => native.openAppNotificationSettings(),
        ),
      ],
    );
  }
}

class _IntroSlide extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _IntroSlide({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 96, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 28),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool granted;
  final VoidCallback onTap;

  const _PermissionTile({
    required this.title,
    required this.subtitle,
    required this.granted,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(
          granted ? Icons.check_circle : Icons.warning_amber_rounded,
          color: granted ? Colors.green : Colors.orange,
        ),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: TextButton(
          onPressed: onTap,
          child: Text(granted ? 'OK' : 'Open Settings'),
        ),
      ),
    );
  }
}
