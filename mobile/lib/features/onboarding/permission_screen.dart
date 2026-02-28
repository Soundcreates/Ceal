/// Permission Screen — requests all runtime permissions during onboarding.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
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
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(),

              // NB icon box
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: AppTheme.nbAccent2.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppTheme.nbRadius),
                  border: Border.all(
                    color: AppTheme.nbInk,
                    width: AppTheme.nbBorder,
                  ),
                  boxShadow: AppTheme.nbShadowSm,
                ),
                child: const Icon(Icons.security, size: 40, color: AppTheme.nbInk),
              ),
              const SizedBox(height: 24),
              Text(
                'Permissions Required',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(
                'CEAL needs the following permissions to send and '
                'receive emergency alerts.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppTheme.nbInk.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 28),

              // Permission items in an NB card
              NBCard(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  children: [
                    _PermissionRow(
                      icon: Icons.bluetooth,
                      label: 'Bluetooth',
                      granted: _result?.bluetooth,
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0x154A4A4A)),
                    _PermissionRow(
                      icon: Icons.location_on,
                      label: 'Location',
                      granted: _result?.location,
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0x154A4A4A)),
                    _PermissionRow(
                      icon: Icons.notifications,
                      label: 'Notifications',
                      granted: _result?.notification,
                    ),
                    const Divider(height: 1, thickness: 1, color: Color(0x154A4A4A)),
                    _PermissionRow(
                      icon: Icons.sms,
                      label: 'SMS (Android)',
                      granted: _result?.sms,
                    ),
                  ],
                ),
              ),

              const Spacer(),

              if (_result == null) ...[
                SizedBox(
                  width: double.infinity,
                  child: NBButton(
                    label: 'Grant Permissions',
                    onPressed: _requesting ? null : _requestPermissions,
                    icon: Icons.shield,
                    isLoading: _requesting,
                    expanded: true,
                  ),
                ),
              ] else if (_result!.allGranted) ...[
                SizedBox(
                  width: double.infinity,
                  child: NBButton(
                    label: 'Continue',
                    onPressed: widget.onComplete,
                    icon: Icons.arrow_forward,
                    color: AppTheme.nbOk,
                    expanded: true,
                  ),
                ),
              ] else ...[
                NBCard(
                  color: AppTheme.nbError.withValues(alpha: 0.08),
                  borderColor: AppTheme.nbError,
                  shadow: false,
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Grant all permissions to join the safety network.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppTheme.nbError,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: NBButton(
                    label: 'Retry Permissions',
                    onPressed: _requestPermissions,
                    icon: Icons.refresh,
                    expanded: true,
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
        ? Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.nbInk.withValues(alpha: 0.3), width: AppTheme.nbBorder),
            ),
          )
        : granted!
            ? Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.nbOk,
                ),
                child: const Icon(Icons.check, size: 14, color: Colors.white),
              )
            : Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.nbError,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          NBIconBox(icon: icon, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Text(label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
          ),
          statusIcon,
        ],
      ),
    );
  }
}
