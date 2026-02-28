/// Permission Screen — requests all runtime permissions during onboarding.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/permissions.dart';
import 'package:aftermath/providers.dart';

class PermissionScreen extends ConsumerStatefulWidget {
  const PermissionScreen({super.key, required this.onComplete});

  final VoidCallback onComplete;

  @override
  ConsumerState<PermissionScreen> createState() => _PermissionScreenState();
}

class _PermissionScreenState extends ConsumerState<PermissionScreen> {
  PermissionResult? _result;
  bool _requesting = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(),

              Icon(
                Icons.security,
                size: 72,
                color: AppTheme.sosColor,
              ),
              const SizedBox(height: 24),
              Text(
                'Permissions Required',
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Text(
                'AfterMath needs the following permissions to send and '
                'receive emergency alerts.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: Colors.grey),
              ),
              const SizedBox(height: 32),

              // Permission items
              _PermissionRow(
                icon: Icons.bluetooth,
                label: 'Bluetooth',
                granted: _result?.bluetooth,
              ),
              _PermissionRow(
                icon: Icons.location_on,
                label: 'Location',
                granted: _result?.location,
              ),
              _PermissionRow(
                icon: Icons.notifications,
                label: 'Notifications',
                granted: _result?.notification,
              ),
              _PermissionRow(
                icon: Icons.sms,
                label: 'SMS (Android)',
                granted: _result?.sms,
              ),

              const Spacer(),

              if (_result == null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _requesting ? null : _requestPermissions,
                    child: _requesting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Grant Permissions'),
                  ),
                ),
              ] else if (_result!.allGranted) ...[
                // All critical permissions granted — allow continue.
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: widget.onComplete,
                    child: const Text('Continue'),
                  ),
                ),
              ] else ...[
                // Blocking: critical permissions missing.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Grant all permissions to join the safety network.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.sosColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: FilledButton(
                    onPressed: _requestPermissions,
                    child: const Text('Retry Permissions'),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () =>
                      ref.read(permissionServiceProvider).openSettings(),
                  child: const Text('Open Settings'),
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _requestPermissions() async {
    setState(() => _requesting = true);
    final svc = ref.read(permissionServiceProvider);
    final result = await svc.requestAll();
    setState(() {
      _result = result;
      _requesting = false;
    });
  }
}

class _PermissionRow extends StatelessWidget {
  const _PermissionRow({
    required this.icon,
    required this.label,
    this.granted,
  });

  final IconData icon;
  final String label;
  final bool? granted;

  @override
  Widget build(BuildContext context) {
    final statusIcon = granted == null
        ? const Icon(Icons.circle_outlined, color: Colors.grey, size: 20)
        : granted!
            ? Icon(Icons.check_circle, color: AppTheme.safeColor, size: 20)
            : const Icon(Icons.cancel, color: Colors.redAccent, size: 20);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          statusIcon,
        ],
      ),
    );
  }
}
