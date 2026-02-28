/// Settings Screen — user preferences, emergency contacts, and BLE config.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ------ BLE Section (always-on) ------
          Text('Bluetooth', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.bluetooth_searching, color: Colors.blue),
            title: Text('Background Scanning'),
            subtitle: Text('Always on — listening for nearby SOS alerts 24/7.'),
            trailing: Icon(Icons.check_circle, color: Colors.green),
          ),
          const Divider(height: 32),

          // ------ SMS Fallback Section ------
          Text('SMS Fallback', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Enable SMS Fallback'),
            subtitle: const Text(
              'Send SMS to emergency contacts if BLE relay fails.',
            ),
            value: _smsFallbackEnabled,
            onChanged: (val) async {
              setState(() => _smsFallbackEnabled = val);
              final settings = ref.read(settingsServiceProvider);
              await settings.setSmsEnabled(val);
              _syncContactsToSmsService();
            },
          ),
          const Divider(height: 32),

          // ------ Emergency Contacts Section ------
          Text(
            'Emergency Contacts',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          ..._contacts.map(
            (c) => ListTile(
              leading: const Icon(Icons.person),
              title: Text(c.name),
              subtitle: Text(c.phone),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  setState(() => _contacts.remove(c));
                  _persistContacts();
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _showAddContactDialog,
            icon: const Icon(Icons.add),
            label: const Text('Add Contact'),
          ),
          const Divider(height: 32),

          // ------ About Section ------
          Text('About', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('AfterMath v1.0.0'),
            subtitle: Text('Offline-first BLE emergency alert network.'),
          ),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy Policy'),
            onTap: () {
              // TODO: open privacy policy URL
            },
          ),
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
        title: const Text('Add Emergency Contact'),
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
          FilledButton(
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
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
