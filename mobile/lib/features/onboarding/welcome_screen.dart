/// Welcome Screen — first launch introduction to AfterMath.
library;

import 'package:flutter/material.dart';

import 'package:aftermath/core/app_theme.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo / icon
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.sosColor.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.health_and_safety,
                  size: 64,
                  color: AppTheme.sosColor,
                ),
              ),
              const SizedBox(height: 32),

              Text(
                'AfterMath',
                style: theme.textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Emergency SOS Network',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 40),

              // Feature highlights
              const _FeatureRow(
                icon: Icons.bluetooth,
                title: 'Offline BLE Mesh',
                subtitle:
                    'Broadcast SOS alerts to nearby devices without internet.',
              ),
              const SizedBox(height: 20),
              const _FeatureRow(
                icon: Icons.people,
                title: 'Local Responders',
                subtitle:
                    'Nearby app users see your alert instantly and can help.',
              ),
              const SizedBox(height: 20),
              const _FeatureRow(
                icon: Icons.sms,
                title: 'SMS Fallback',
                subtitle:
                    'Automatic SMS to emergency contacts if relay fails.',
              ),
              const SizedBox(height: 20),
              const _FeatureRow(
                icon: Icons.verified_user,
                title: 'Accountability',
                subtitle:
                    'Every SOS and response is logged for civic review.',
              ),

              const Spacer(flex: 3),

              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton(
                  onPressed: onGetStarted,
                  child: const Text('Get Started'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 32, color: AppTheme.sosColor),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(subtitle,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
