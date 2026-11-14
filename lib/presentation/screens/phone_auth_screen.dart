import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../l10n/tr.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import '../../data/remote/firestore_service.dart';
import '../../domain/entities/alarm.dart';
import '../providers/app_providers.dart';

class PhoneAuthScreen extends ConsumerStatefulWidget {
  final VoidCallback onAuthenticated;
  const PhoneAuthScreen({super.key, required this.onAuthenticated});

  @override
  ConsumerState<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends ConsumerState<PhoneAuthScreen> {
  String _countryCode = '+20';
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();

  String? _verificationId;
  bool _loading = false;
  bool _needsProfile = false;
  String? _error;

  static const _countryCodes = ['+20', '+966', '+971', '+1', '+44', '+49'];

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
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

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-phone-number':
        return context.tr('The phone number is not valid. Check the country code and number.',
            'رقم الهاتف غير صالح. تأكد من مفتاح الدولة والرقم.');
      case 'too-many-requests':
        return context.tr('Too many attempts. Please try again later.',
            'محاولات كثيرة. حاول مرة أخرى لاحقاً.');
      case 'quota-exceeded':
        return context.tr('SMS quota exceeded. Please try again later.',
            'تم تجاوز حد الرسائل. حاول لاحقاً.');
      case 'network-request-failed':
        return context.tr('No internet connection.', 'لا يوجد اتصال بالإنترنت.');
      case 'app-not-authorized':
      case 'missing-client-identifier':
      case 'invalid-app-credential':
      case 'captcha-check-failed':
      case 'operation-not-allowed':
        return context.tr(
            'Phone sign-in is not configured for this app build (Firebase SHA keys / phone provider). Use Offline Mode for now.',
            'تسجيل الدخول بالهاتف غير مُعدّ لهذه النسخة (بصمات SHA أو تفعيل الدخول بالهاتف في فايربيز). استخدم الوضع بدون إنترنت حالياً.');
      default:
        return context.tr('Verification failed', 'فشل التحقق') +
            (e.message != null ? ': ${e.message}' : '');
    }
  }

  Future<void> _sendOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    if (Firebase.apps.isEmpty) {
      setState(() {
        _error = context.tr(
            'Firebase is not configured in this build (google-services.json is missing). You can continue in Offline Mode.',
            'فايربيز غير مُعدّ في هذه النسخة (ملف google-services.json غير موجود). يمكنك المتابعة بدون إنترنت.');
        _loading = false;
      });
      return;
    }
    final local = _normalizedLocalNumber();
    if (local.length < 6) {
      setState(() {
        _error = context.tr('Enter a valid phone number.', 'أدخل رقم هاتف صحيحاً.');
        _loading = false;
      });
      return;
    }
    final fullPhone = '$_countryCode$local';
    try {
      await FirebaseAuth.instance.verifyPhoneNumber(
        phoneNumber: fullPhone,
        verificationCompleted: (cred) async {
          await FirebaseAuth.instance.signInWithCredential(cred);
          if (mounted) setState(() => _needsProfile = true);
        },
        verificationFailed: (e) {
          if (mounted) {
            setState(() {
              _error = _authErrorMessage(e);
              _loading = false;
            });
          }
        },
        codeSent: (verId, _) {
          if (mounted) {
            setState(() {
              _verificationId = verId;
              _loading = false;
            });
          }
        },
        codeAutoRetrievalTimeout: (verId) {
          _verificationId = verId;
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = context.tr('Could not send the code. Please try again.', 'تعذر إرسال الرمز. حاول مرة أخرى.');
        _loading = false;
      });
    }
  }

  Future<void> _verifyOtp() async {
    if (_verificationId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final cred = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: _otpCtrl.text.trim(),
      );
      await FirebaseAuth.instance.signInWithCredential(cred);
      setState(() {
        _needsProfile = true;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = context.tr('Invalid or expired code.', 'الرمز غير صحيح أو منتهي.');
        _loading = false;
      });
    }
  }

  Future<void> _saveProfileAndContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'local_user';
    final displayName =
        _nameCtrl.text.trim().isEmpty ? context.tr('User', 'مستخدم') : _nameCtrl.text.trim();
    final tzId = await FlutterTimezone.getLocalTimezone();
    final phoneHash = FirestoreService.hashPhoneNumber(
      '$_countryCode${_normalizedLocalNumber()}',
      defaultCountryCode: _countryCode,
    );

    ref.read(currentUserIdProvider.notifier).state = uid;
    ref.read(currentUserNameProvider.notifier).state = displayName;

    final fs = ref.read(firestoreServiceProvider);
    if (fs != null && user != null) {
      await fs.upsertUserProfile(
        UserProfile(
          uid: uid,
          phoneHash: phoneHash,
          displayName: displayName,
          timezoneId: tzId,
        ),
      );
    }
    widget.onAuthenticated();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('Sign in with Phone', 'تسجيل الدخول برقم الهاتف')),
        actions: [
          TextButton(
            onPressed: widget.onAuthenticated,
            child: Text(context.tr('Offline Mode', 'بدون إنترنت')),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (!_needsProfile) ...[
            Row(
              children: [
                DropdownButton<String>(
                  value: _countryCode,
                  items: _countryCodes
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _countryCode = v);
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      labelText: context.tr('Phone Number', 'رقم الهاتف'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_verificationId != null) ...[
              TextField(
                controller: _otpCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('SMS Verification Code', 'رمز التحقق عبر SMS'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _verifyOtp,
                child: Text(context.tr('Verify & Continue', 'تأكيد ومتابعة')),
              ),
            ] else
              FilledButton(
                onPressed: _loading ? null : _sendOtp,
                child: Text(context.tr('Send Verification Code', 'إرسال رمز التحقق')),
              ),
          ] else ...[
            TextField(
              controller: _nameCtrl,
              decoration: InputDecoration(
                labelText: context.tr('Display Name', 'الاسم المعروض'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saveProfileAndContinue,
              child: Text(context.tr('Complete Profile', 'إكمال الملف الشخصي')),
            ),
          ],
        ],
        ),
      ),
    );
  }
}
