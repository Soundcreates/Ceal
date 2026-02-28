/// Signup screen — collects name, phone, and one emergency contact,
/// then registers the user with the backend and stores the confirmed BLE UID.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/providers.dart';

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  static const _storage = FlutterSecureStorage();

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController(text: '+91');
  final _contactNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController(text: '+91');

  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    // The device has already generated a random BLE UID stored in secure
    // storage. We send it to the backend so the DB record matches exactly
    // what this device will broadcast over BLE.
    final bleUidBytes = await ref.read(bleUidProvider.future);
    final bleUidHex =
        bleUidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    final contacts = <Map<String, dynamic>>[];
    final cPhone = _contactPhoneCtrl.text.trim();
    if (cPhone.isNotEmpty && cPhone != '+91') {
      contacts.add({
        'name': _contactNameCtrl.text.trim().isEmpty
            ? null
            : _contactNameCtrl.text.trim(),
        'phone': cPhone,
        'priority': 1,
      });
    }

    final backend = ref.read(backendServiceProvider);
    final result = await backend.signup(
      phone: _phoneCtrl.text.trim(),
      bleUid: bleUidHex,
      name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      emergencyContacts: contacts.isEmpty ? null : contacts,
    );

    if (!mounted) return;

    if (result.success) {
      // Persist token so it survives app restarts.
      if (result.token != null) {
        await _storage.write(key: 'aftermath_auth_token', value: result.token);
        backend.authToken = result.token;
      }
      if (result.userId != null) {
        await _storage.write(key: 'aftermath_user_id', value: result.userId);
      }
      // The backend confirmed our bleUid — nothing to overwrite
      // (bleUidProvider already has the same value from secure storage).
      debugPrint(
        '[SignupScreen] Signup OK — userId=${result.userId} bleUid=$bleUidHex',
      );
      widget.onComplete();
      return;
    }

    setState(() {
      _submitting = false;
      _error = result.error ?? 'Signup failed.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Icon(
                    Icons.person_add_alt_1,
                    size: 64,
                    color: AppTheme.sosColor,
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Create Account',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    'Your phone registers your emergency identity.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 32),

                // ── Personal details ──────────────────────────────────────
                Text('Your details',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: Colors.grey)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Full name (optional)',
                    prefixIcon: Icon(Icons.person),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Your phone (E.164, e.g. +919876543210)',
                    prefixIcon: Icon(Icons.phone),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (!RegExp(r'^\+[1-9]\d{9,14}$').hasMatch(t)) {
                      return 'Enter a valid E.164 phone (e.g. +919876543210)';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // ── Emergency contact ─────────────────────────────────────
                Text('Emergency contact (optional)',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: Colors.grey)),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _contactNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Contact name',
                    prefixIcon: Icon(Icons.people),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _contactPhoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Contact phone (E.164)',
                    prefixIcon: Icon(Icons.phone_in_talk),
                  ),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty || t == '+91') return null; // optional
                    if (!RegExp(r'^\+[1-9]\d{9,14}$').hasMatch(t)) {
                      return 'Enter a valid E.164 phone';
                    }
                    return null;
                  },
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: Colors.red, fontSize: 13)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    child: _submitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Register'),
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: TextButton(
                    onPressed: _submitting ? null : widget.onComplete,
                    child: const Text('Skip for now'),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'BLE UID: ${_formatBleUid()}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: Colors.grey.shade400, fontSize: 10),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatBleUid() {
    final uid = ref.watch(bleUidProvider);
    return uid.when(
      data: (bytes) =>
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(':'),
      loading: () => 'loading…',
      error: (_, _) => 'error',
    );
  }
}
