/// Signup screen — collects name, phone, emergency contacts, medical profile,
/// then registers the user with the backend and stores the confirmed BLE UID.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
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

  // Emergency contacts — support up to 3
  final List<TextEditingController> _contactNameCtrls = [TextEditingController()];
  final List<TextEditingController> _contactPhoneCtrls = [TextEditingController(text: '+91')];

  // Medical profile
  final _bloodGroupCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final _conditionsCtrl = TextEditingController();

  // Language
  String _language = 'en';

  bool _submitting = false;
  String? _error;

  static const _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  static const _languages = [
    ('en', 'English'),
    ('hi', 'Hindi'),
    ('ta', 'Tamil'),
    ('te', 'Telugu'),
    ('mr', 'Marathi'),
    ('bn', 'Bengali'),
    ('gu', 'Gujarati'),
    ('kn', 'Kannada'),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    for (final c in _contactNameCtrls) { c.dispose(); }
    for (final c in _contactPhoneCtrls) { c.dispose(); }
    _bloodGroupCtrl.dispose();
    _allergiesCtrl.dispose();
    _conditionsCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    final bleUidBytes = await ref.read(bleUidProvider.future);
    final bleUidHex =
        bleUidBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Build emergency contacts list (skip blank entries)
    final contacts = <Map<String, dynamic>>[];
    for (int i = 0; i < _contactPhoneCtrls.length; i++) {
      final phone = _contactPhoneCtrls[i].text.trim();
      if (phone.isNotEmpty && phone != '+91') {
        contacts.add({
          'name': _contactNameCtrls[i].text.trim().isEmpty
              ? null
              : _contactNameCtrls[i].text.trim(),
          'phone': phone,
          'priority': i + 1,
        });
      }
    }

    // Build medical profile (only if any field is filled)
    Map<String, dynamic>? medical;
    final bg = _bloodGroupCtrl.text.trim();
    final allergies = _allergiesCtrl.text.trim();
    final conditions = _conditionsCtrl.text.trim();
    if (bg.isNotEmpty || allergies.isNotEmpty || conditions.isNotEmpty) {
      medical = {
        if (bg.isNotEmpty) 'bloodGroup': bg,
        if (allergies.isNotEmpty) 'allergies': allergies,
        if (conditions.isNotEmpty) 'conditions': conditions,
      };
    }

    final backend = ref.read(backendServiceProvider);
    final result = await backend.signup(
      phone: _phoneCtrl.text.trim(),
      bleUid: bleUidHex,
      name: _nameCtrl.text.trim().isEmpty ? null : _nameCtrl.text.trim(),
      language: _language,
      emergencyContacts: contacts.isEmpty ? null : contacts,
      medicalProfile: medical,
    );

    if (!mounted) return;

    if (result.success) {
      if (result.token != null) {
        await _storage.write(key: 'aftermath_auth_token', value: result.token);
        backend.authToken = result.token;
      }
      if (result.userId != null) {
        await _storage.write(key: 'aftermath_user_id', value: result.userId);
      }
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
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.nbAccent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(AppTheme.nbRadius),
                      border: Border.all(
                        color: AppTheme.nbInk,
                        width: AppTheme.nbBorder,
                      ),
                      boxShadow: AppTheme.nbShadowSm,
                    ),
                    child: const Icon(Icons.person_add_alt_1, size: 36, color: AppTheme.nbInk),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    'Create Account',
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
                Center(
                  child: Text(
                    'Your phone registers your emergency identity.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.nbInk.withValues(alpha: 0.5),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 28),

                // ── Personal details ──────────────────────────────────────
                const NBSectionHeader(label: 'Your details', icon: Icons.person),
                const SizedBox(height: 12),
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
                const SizedBox(height: 12),
                // Language picker
                DropdownButtonFormField<String>(
                  initialValue: _language,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Preferred language',
                    prefixIcon: Icon(Icons.language),
                  ),
                  items: _languages.map((lang) {
                    return DropdownMenuItem(
                      value: lang.$1,
                      child: Text(lang.$2),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => _language = v ?? 'en'),
                ),
                const SizedBox(height: 24),

                // ── Emergency contacts ────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const NBSectionHeader(label: 'Emergency Contacts', icon: Icons.contacts),
                    if (_contactPhoneCtrls.length < 3)
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Add'),
                        onPressed: () => setState(() {
                          _contactNameCtrls.add(TextEditingController());
                          _contactPhoneCtrls
                              .add(TextEditingController(text: '+91'));
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                for (int i = 0; i < _contactPhoneCtrls.length; i++) ...[
                  if (i > 0) const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _contactNameCtrls[i],
                              textCapitalization: TextCapitalization.words,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: 'Contact ${i + 1} name',
                                prefixIcon: const Icon(Icons.people),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: _contactPhoneCtrls[i],
                              keyboardType: TextInputType.phone,
                              decoration: InputDecoration(
                                border: const OutlineInputBorder(),
                                labelText: 'Contact ${i + 1} phone',
                                prefixIcon: const Icon(Icons.phone_in_talk),
                              ),
                              validator: (v) {
                                final t = v?.trim() ?? '';
                                if (t.isEmpty || t == '+91') return null;
                                if (!RegExp(r'^\+[1-9]\d{9,14}$')
                                    .hasMatch(t)) {
                                  return 'Enter a valid E.164 phone';
                                }
                                return null;
                              },
                            ),
                          ],
                        ),
                      ),
                      if (i > 0) ...[
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline,
                              color: AppTheme.sosColor),
                          onPressed: () => setState(() {
                            _contactNameCtrls.removeAt(i).dispose();
                            _contactPhoneCtrls.removeAt(i).dispose();
                          }),
                        ),
                      ],
                    ],
                  ),
                ],
                const SizedBox(height: 24),

                // ── Medical profile ───────────────────────────────────────
                const NBSectionHeader(label: 'Medical Profile', icon: Icons.medical_services),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _bloodGroupCtrl.text.isEmpty
                      ? null
                      : _bloodGroupCtrl.text,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Blood group',
                    prefixIcon: Icon(Icons.bloodtype),
                  ),
                  items: _bloodGroups
                      .map((bg) =>
                          DropdownMenuItem(value: bg, child: Text(bg)))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _bloodGroupCtrl.text = v ?? ''),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _allergiesCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Known allergies',
                    prefixIcon: Icon(Icons.warning_amber),
                    hintText: 'e.g. Penicillin, peanuts',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _conditionsCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Medical conditions',
                    prefixIcon: Icon(Icons.medical_services),
                    hintText: 'e.g. Diabetes, epilepsy',
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  NBCard(
                    color: AppTheme.nbError.withValues(alpha: 0.08),
                    borderColor: AppTheme.nbError,
                    shadow: false,
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppTheme.nbError, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  color: AppTheme.nbError, fontSize: 13, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: NBButton(
                    label: 'Register',
                    onPressed: _submitting ? null : _submit,
                    icon: Icons.check,
                    isLoading: _submitting,
                    color: AppTheme.nbOk,
                    expanded: true,
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
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.nbInk.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.zero,
                      border: Border.all(color: AppTheme.nbInk.withValues(alpha: 0.3), width: AppTheme.nbBorder),
                    ),
                    child: Text(
                      'BLE UID: ${_formatBleUid()}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.nbInk.withValues(alpha: 0.4),
                        fontSize: 10,
                      ),
                    ),
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
