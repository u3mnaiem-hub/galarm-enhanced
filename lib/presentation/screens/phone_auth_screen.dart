import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/remote/fcm_alarm_service.dart';
import '../../data/remote/firestore_service.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';

/// Free, instant phone-number registration (no SMS / Blaze billing required).
/// Authenticates anonymously with Firebase (when enabled) and saves the user's
/// normalized phone number + display name + FCM token in Firestore.
class PhoneAuthScreen extends ConsumerStatefulWidget {
  final VoidCallback onAuthenticated;
  const PhoneAuthScreen({super.key, required this.onAuthenticated});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  String _countryCode = '+20';
  final _phoneCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  bool _loading = false;
  String? _error;

  static const _countryCodes = ['+20', '+966', '+971', '+965', '+974', '+1', '+44', '+49'];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Strips spaces/dashes and the leading trunk zero (e.g. 010... -> 10...),
  /// and removes the country code if the user typed it already.
  String _normalizedLocalNumber() {
    var n = _phoneCtrl.text.replaceAll(RegExp(r'[\s\-\(\)\.]'), '');
    final cc = _countryCode;
    if (n.startsWith('+')) {
      if (n.startsWith(cc)) n = n.substring(cc.length);
    } else if (n.startsWith('00') && n.substring(2).startsWith(cc.substring(1))) {
      n = n.substring(2 + cc.length - 1);
    }
    while (n.startsWith('0')) {
      n = n.substring(1);
    }
    return n;
  }

  Future<void> _registerAndContinue() async {
    final name = _nameCtrl.text.trim();
    final local = _normalizedLocalNumber();

    if (name.isEmpty) {
      setState(() {
        _error = context.tr(
          'Please enter your name.',
          'يرجى إدخال اسمك.',
        );
      });
      return;
    }
    if (local.length < 6) {
      setState(() {
        _error = context.tr(
          'Please enter a valid phone number.',
          'يرجى إدخال رقم هاتف صحيح.',
        );
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final normalizedPhone = FirestoreService.normalizePhoneNumber(
        '$_countryCode$local',
        defaultCountryCode: _countryCode,
      );
      final phoneHash = FirestoreService.hashPhoneNumber(
        normalizedPhone,
        defaultCountryCode: _countryCode,
      );

      var tzId = 'Africa/Cairo';
      try {
        tzId = await FlutterTimezone.getLocalTimezone();
      } catch (_) {}

      // Try Firebase Anonymous Auth first (free on Spark plan).
      // If Anonymous Auth is not enabled in Firebase Console, fall back cleanly
      // to a deterministic phone-based UID so Firestore & FCM still work immediately.
      String uid = 'u_${phoneHash.substring(0, 20)}';
      if (Firebase.apps.isNotEmpty) {
        try {
          final existing = FirebaseAuth.instance.currentUser;
          if (existing != null) {
            uid = existing.uid;
          } else {
            final cred = await FirebaseAuth.instance.signInAnonymously();
            if (cred.user != null) {
              uid = cred.user!.uid;
            }
          }
        } catch (_) {
          // Keep deterministic phone-based uid — works seamlessly with Firestore test mode
        }
      }

      ref.read(currentUserIdProvider.notifier).state = uid;
      ref.read(currentUserNameProvider.notifier).state = name;
      ref.read(currentUserPhoneProvider.notifier).state = normalizedPhone;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('user_uid', uid);
      await prefs.setString('user_name', name);
      await prefs.setString('user_phone', normalizedPhone);
      await prefs.setBool('seen_phone_auth', true);

      final fs = ref.read(firestoreServiceProvider);
      if (fs != null) {
        await fs.upsertUserProfile(
          UserProfile(
            uid: uid,
            phoneNumber: normalizedPhone,
            phoneHash: phoneHash,
            displayName: name,
            timezoneId: tzId,
          ),
        );
        await FcmAlarmService.initializeAndRegisterToken(
          uid: uid,
          phoneNumber: normalizedPhone,
          firestore: fs,
          repo: ref.read(alarmRepositoryProvider),
        );
      }

      if (mounted) {
        widget.onAuthenticated();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = context.tr(
            'Could not connect right now ($e). Check your internet or tap Offline Mode.',
            'تعذر الاتصال حالياً ($e). تأكد من الإنترنت أو اضغط بدون إنترنت.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Phone Registration', 'تسجيل رقم الهاتف')),
        actions: [
          TextButton(
            onPressed: _loading ? null : widget.onAuthenticated,
            child: Text(
              context.tr('Offline Mode', 'بدون إنترنت'),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Icon(
              Icons.alarm_on_rounded,
              size: 64,
              color: cs.primary,
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'Connect Your Phone Number',
                'ربط رقم هاتفك بتطبيق منبه U3m',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'Enter your name and phone number once (free, no SMS needed) so Buddies & Groups can share alarms with you.',
                'أدخل اسمك ورقم هاتفك مرة واحدة (مجاناً بدون رسائل SMS) ليتمكن الأصدقاء والمجموعات من مشاركة المنبهات معك.',
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(0.45)),
                ),
                child: Text(
                  _error!,
                  style: const TextStyle(
                    color: Colors.red,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
            TextField(
              controller: _nameCtrl,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.tr('Your Name', 'الاسم'),
                prefixIcon: const Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                DropdownButton<String>(
                  value: _countryCode,
                  items: _countryCodes
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: _loading
                      ? null
                      : (v) {
                          if (v != null) setState(() => _countryCode = v);
                        },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _loading ? null : _registerAndContinue(),
                    decoration: InputDecoration(
                      labelText: context.tr('Phone Number', 'رقم الهاتف'),
                      prefixIcon: const Icon(Icons.phone_outlined),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: _loading ? null : _registerAndContinue,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(
                _loading
                    ? context.tr('Connecting...', 'جاري الاتصال...')
                    : context.tr('Save & Continue', 'تسجيل ومتابعة'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
