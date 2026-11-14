import 'package:firebase_auth/firebase_auth.dart';
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

  Future<void> _sendOtp() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final fullPhone = '$_countryCode${_phoneCtrl.text.trim()}';
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
              _error = e.message ?? 'Verification failed';
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
      setState(() {
        _error = e.toString();
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
        _error = 'Invalid code: $e';
        _loading = false;
      });
    }
  }

  Future<void> _saveProfileAndContinue() async {
    final user = FirebaseAuth.instance.currentUser;
    final uid = user?.uid ?? 'local_user';
    final displayName =
        _nameCtrl.text.trim().isEmpty ? 'User' : _nameCtrl.text.trim();
    final tzId = await FlutterTimezone.getLocalTimezone();
    final phoneHash = FirestoreService.hashPhoneNumber(
      '$_countryCode${_phoneCtrl.text.trim()}',
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
        title: const Text('Sign in with Phone'),
        actions: [
          TextButton(
            onPressed: widget.onAuthenticated,
            child: const Text('Offline Mode'),
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
                    decoration: const InputDecoration(
                      labelText: 'Phone Number',
                      border: OutlineInputBorder(),
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
                decoration: const InputDecoration(
                  labelText: 'SMS Verification Code',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loading ? null : _verifyOtp,
                child: const Text('Verify & Continue'),
              ),
            ] else
              FilledButton(
                onPressed: _loading ? null : _sendOtp,
                child: const Text('Send Verification Code'),
              ),
          ] else ...[
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display Name',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saveProfileAndContinue,
              child: const Text('Complete Profile'),
            ),
          ],
        ],
        ),
      ),
    );
  }
}
