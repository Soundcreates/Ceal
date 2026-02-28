/// Settings Screen — user preferences, emergency contacts, and BLE config.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:aftermath/main.dart';
import 'package:aftermath/models/responder.dart';
import 'package:aftermath/providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _smsFallbackEnabled = true;

  final _contactNameCtrl = TextEditingController();
  final _contactPhoneCtrl = TextEditingController();
  final List<EmergencyContact> _contacts = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = ref.read(settingsServiceProvider);
    final contacts = await settings.loadContacts();
    final smsEnabled = await settings.isSmsEnabled();
    if (mounted) {
      setState(() {
        _contacts
          ..clear()
          ..addAll(contacts);
        _smsFallbackEnabled = smsEnabled;
      });
      _syncContactsToSmsService();
    }
  }

  Future<void> _persistContacts() async {
    final settings = ref.read(settingsServiceProvider);
    await settings.saveContacts(_contacts);
    _syncContactsToSmsService();
  }

  void _syncContactsToSmsService() {
    final sms = ref.read(smsFallbackProvider);
    sms.emergencyContacts = List.of(_contacts);
    sms.enabled = _smsFallbackEnabled;
  }

  @override
  void dispose() {
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------ BLE Section (always-on) ------
          const NBSectionHeader(icon: Icons.bluetooth, label: 'Bluetooth'),
          const SizedBox(height: 8),
          NBCard(
            child: ListTile(
              leading: const NBIconBox(
                icon: Icons.bluetooth_searching,
                color: AppTheme.nbAccent2,
              ),
              title: Text('Background Scanning', style: tt.titleSmall),
              subtitle: Text(
                'Always on — listening for nearby SOS alerts 24/7.',
                style: tt.bodySmall,
              ),
              trailing: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppTheme.nbOk.withValues(alpha: .15),
                  border: Border.all(
                    color: AppTheme.nbInk,
                    width: AppTheme.nbBorder,
                  ),
                  borderRadius: BorderRadius.zero,
                ),
                child: const Icon(Icons.check, size: 18, color: AppTheme.nbOk),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ------ SMS Fallback Section ------
          const NBSectionHeader(
            icon: Icons.sms_outlined,
            label: 'SMS Fallback',
          ),
          const SizedBox(height: 8),
          NBCard(
            child: SwitchListTile(
              title: Text('Enable SMS Fallback', style: tt.titleSmall),
              subtitle: Text(
                'Send SMS to emergency contacts if BLE relay fails.',
                style: tt.bodySmall,
              ),
              value: _smsFallbackEnabled,
              onChanged: (val) async {
                setState(() => _smsFallbackEnabled = val);
                final settings = ref.read(settingsServiceProvider);
                await settings.setSmsEnabled(val);
                _syncContactsToSmsService();
              },
            ),
          ),
          const SizedBox(height: 20),

          // ------ Emergency Contacts Section ------
          const NBSectionHeader(
            icon: Icons.contacts_outlined,
            label: 'Emergency Contacts',
          ),
          const SizedBox(height: 8),
          if (_contacts.isNotEmpty)
            NBCard(
              child: Column(
                children: _contacts.map((c) {
                  final isLast = c == _contacts.last;
                  return Column(
                    children: [
                      ListTile(
                        leading: const NBIconBox(
                          icon: Icons.person,
                          color: AppTheme.nbAccent,
                          size: 36,
                        ),
                        title: Text(c.name, style: tt.titleSmall),
                        subtitle: Text(c.phone, style: tt.bodySmall),
                        trailing: GestureDetector(
                          onTap: () {
                            setState(() => _contacts.remove(c));
                            _persistContacts();
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: AppTheme.nbError.withValues(alpha: .1),
                              border: Border.all(
                                color: AppTheme.nbInk,
                                width: AppTheme.nbBorder,
                              ),
                              borderRadius: BorderRadius.zero,
                            ),
                            child: const Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: AppTheme.nbError,
                            ),
                          ),
                        ),
                      ),
                      if (!isLast)
                        const Divider(height: 1, color: AppTheme.nbInk),
                    ],
                  );
                }).toList(),
              ),
            ),
          const SizedBox(height: 12),
          NBButton(
            label: 'Add Contact',
            icon: Icons.add,
            color: AppTheme.nbAccent,
            onPressed: _showAddContactDialog,
          ),
          const SizedBox(height: 20),

          // ------ About Section ------
          const NBSectionHeader(icon: Icons.info_outline, label: 'About'),
          const SizedBox(height: 8),
          NBCard(
            child: Column(
              children: [
                ListTile(
                  leading: const NBIconBox(
                    icon: Icons.shield_outlined,
                    color: AppTheme.nbAccent2,
                  ),
                  title: Text('AfterMath v1.0.0', style: tt.titleSmall),
                  subtitle: Text(
                    'Offline-first BLE emergency alert network.',
                    style: tt.bodySmall,
                  ),
                ),
                const Divider(height: 1, color: AppTheme.nbInk),
                ListTile(
                  leading: const NBIconBox(
                    icon: Icons.privacy_tip_outlined,
                    color: AppTheme.nbWarn,
                  ),
                  title: Text('Privacy Policy', style: tt.titleSmall),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppTheme.nbInk,
                  ),
                  onTap: () {
                    // TODO: open privacy policy URL
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          const Divider(height: 32),

          // ------ Account Section ------
          Text('Account', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Log Out', style: TextStyle(color: Colors.red)),
            onTap: () => _handleLogout(context),
          ),
        ],
      ),
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Clear secure storage
    const storage = FlutterSecureStorage();
    await storage.delete(key: 'aftermath_auth_token');
    await storage.delete(key: 'aftermath_user_id');

    // Clear backend service token
    ref.read(backendServiceProvider).authToken = '';

    if (!mounted) return;

    // Navigate back to bootstrap screen
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AppBootstrapScreen()),
      (route) => false,
    );
  }

  void _showAddContactDialog() {
    _contactNameCtrl.clear();
    _contactPhoneCtrl.clear();

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.nbRadius),
          side: const BorderSide(
            color: AppTheme.nbInk,
            width: AppTheme.nbBorder,
          ),
        ),
        title: Row(
          children: [
            const NBIconBox(
              icon: Icons.person_add,
              color: AppTheme.nbAccent,
              size: 36,
            ),
            const SizedBox(width: 12),
            Text('Add Contact', style: Theme.of(ctx).textTheme.titleMedium),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _contactNameCtrl,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contactPhoneCtrl,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                prefixIcon: Icon(Icons.phone),
              ),
              keyboardType: TextInputType.phone,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          NBButton(
            label: 'Add',
            icon: Icons.check,
            color: AppTheme.nbAccent,
            onPressed: () {
              final name = _contactNameCtrl.text.trim();
              final phone = _contactPhoneCtrl.text.trim();
              if (name.isNotEmpty && phone.isNotEmpty) {
                setState(
                  () =>
                      _contacts.add(EmergencyContact(name: name, phone: phone)),
                );
                _persistContacts();
              }
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }
}
