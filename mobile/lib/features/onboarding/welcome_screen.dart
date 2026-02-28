/// Welcome Screen — first launch introduction to CEAL.
library;

import 'package:flutter/material.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key, required this.onGetStarted});

  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            children: [
              const Spacer(flex: 2),

              // Logo — CEAL brand mark
              Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppTheme.nbRadius),
                  border: Border.all(
                    color: AppTheme.nbInk,
                    width: AppTheme.nbBorder,
                  ),
                  boxShadow: AppTheme.nbShadow,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 28),

              Text(
                'CEAL',
                style: theme.textTheme.headlineLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Civic Emergency Access Layer',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: AppTheme.nbInk.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 36),

              // Feature highlights — NB cards
              const _FeatureRow(
                icon: Icons.bluetooth,
                title: 'Offline BLE Mesh',
                subtitle:
                    'Broadcast SOS alerts to nearby devices without internet.',
                accentColor: AppTheme.nbAccent2,
              ),
              const SizedBox(height: 12),
              const _FeatureRow(
                icon: Icons.people,
                title: 'Local Responders',
                subtitle:
                    'Nearby app users see your alert instantly and can help.',
                accentColor: AppTheme.nbAccent,
              ),
              const SizedBox(height: 12),
              const _FeatureRow(
                icon: Icons.sms,
                title: 'SMS Fallback',
                subtitle:
                    'Automatic SMS to emergency contacts if relay fails.',
                accentColor: AppTheme.nbWarn,
              ),
              const SizedBox(height: 12),
              const _FeatureRow(
                icon: Icons.verified_user,
                title: 'Accountability',
                subtitle:
                    'Every SOS and response is logged for civic review.',
                accentColor: AppTheme.nbOk,
              ),

              const Spacer(flex: 3),

              // NB primary button with shadow
              SizedBox(
                width: double.infinity,
                child: NBButton(
                  label: 'Get Started',
                  onPressed: onGetStarted,
                  icon: Icons.arrow_forward,
                  expanded: true,
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
    this.accentColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color? accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        NBIconBox(
          icon: icon,
          size: 42,
          bgColor: (accentColor ?? AppTheme.nbAccent).withValues(alpha: 0.2),
          color: AppTheme.nbInk,
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  )),
              const SizedBox(height: 2),
              Text(subtitle,
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }
}
