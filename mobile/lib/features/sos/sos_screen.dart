/// SOS screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/nb_components.dart';
import 'package:aftermath/core/constants.dart';
import 'package:aftermath/features/sos/sos_notifier.dart';
import 'package:aftermath/models/sos_type.dart';
import 'package:aftermath/providers.dart';

class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sosState = ref.watch(sosNotifierProvider);
    final notifier = ref.read(sosNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CEAL: Civic Emergency Access Layer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.warning_amber_rounded),
            tooltip: 'Disaster Reports',
            onPressed: () => Navigator.of(context).pushNamed('/disasters'),
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Alert History',
            onPressed: () => Navigator.of(context).pushNamed('/alerts'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(context).pushNamed('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(child: _buildBody(context, sosState, notifier)),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    SosState sosState,
    SosNotifier notifier,
  ) {
    switch (sosState.phase) {
      case SosPhase.idle:
      case SosPhase.error:
        return _IdleView(
          onTrigger: () {
            HapticFeedback.heavyImpact();
            notifier.triggerSos();
          },
          errorMessage: sosState.errorMessage,
        );
      case SosPhase.countdown:
        return _CountdownView(
          remaining: sosState.countdownRemaining,
          sosType: sosState.sosType,
          onCancel: () {
            HapticFeedback.mediumImpact();
            notifier.cancelSos();
          },
        );
      case SosPhase.locating:
        return const _StatusView(
          icon: Icons.my_location,
          label: 'Acquiring location...',
          color: AppTheme.nbWarn,
        );
      case SosPhase.broadcasting:
        return const _BroadcastingView();
      case SosPhase.awaitingAck:
        return const _StatusView(
          icon: Icons.cloud_upload,
          label: 'Uploading to server...',
          color: AppTheme.nbAccent2,
        );
      case SosPhase.smsFallback:
        return const _StatusView(
          icon: Icons.sms,
          label: 'Sending SMS fallback...',
          color: AppTheme.sosColor,
        );
      case SosPhase.sent:
        return _SentView(
          onReset: notifier.reset,
          backendConfirmed: sosState.backendConfirmed,
          smsSent: sosState.smsSent,
        );
      case SosPhase.cancelled:
        return _StatusView(
          icon: Icons.cancel_outlined,
          label: 'SOS Cancelled',
          color: AppTheme.nbInk.withValues(alpha: 0.4),
        );
    }
  }
}

class _IdleView extends StatelessWidget {
  const _IdleView({required this.onTrigger, this.errorMessage});

  final VoidCallback onTrigger;
  final String? errorMessage;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (errorMessage != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: NBCard(
              color: AppTheme.nbError.withValues(alpha: 0.1),
              borderColor: AppTheme.nbError,
              shadow: false,
              padding: const EdgeInsets.all(12),
              child: Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppTheme.nbError,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
        Text(
          'Press and hold to\nsend emergency SOS',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.nbInk.withValues(alpha: 0.5),
          ),
        ),
        const SizedBox(height: 40),
        GestureDetector(
          onLongPress: onTrigger,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.sosColor,
              border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
              boxShadow: AppTheme.nbShadow,
            ),
            child: Center(
              child: Text(
                'SOS',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.nbInk,
                  letterSpacing: 4,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        Text(
          'Long-press for 1 second to activate',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _CountdownView extends StatelessWidget {
  const _CountdownView({
    required this.remaining,
    required this.sosType,
    required this.onCancel,
  });

  final int remaining;
  final SosType sosType;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: AppTheme.nbWarn.withValues(alpha: 0.15),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
          ),
          child: const Icon(Icons.warning_amber_rounded, size: 36, color: AppTheme.nbWarn),
        ),
        const SizedBox(height: 16),
        Text(
          'Sending ${sosType.label} in',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            color: AppTheme.nbWarn.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppTheme.nbRadius),
            border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
            boxShadow: AppTheme.nbShadow,
          ),
          child: Center(
            child: Text(
              '$remaining',
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: AppTheme.nbWarn,
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        NBButton(
          label: 'CANCEL',
          onPressed: onCancel,
          icon: Icons.close,
          color: AppTheme.nbInk.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Broadcasting view — shows status + live nearby device list
// ---------------------------------------------------------------------------

class _BroadcastingView extends ConsumerWidget {
  const _BroadcastingView();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scanAsync = ref.watch(nearbyDevicesStreamProvider);
    final devices = scanAsync.valueOrNull ?? const [];
    final sorted = [...devices]..sort((a, b) => b.rssi.compareTo(a.rssi));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          RepaintBoundary(
            child: SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.nbAccent2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.nbAccent2.withValues(alpha: 0.15),
              borderRadius: BorderRadius.zero,
              border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
            ),
            child: const Icon(Icons.bluetooth_searching, color: AppTheme.nbAccent2, size: 28),
          ),
          const SizedBox(height: 12),
          Text(
            'Broadcasting SOS via BLE...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          if (sorted.isNotEmpty)
            ..._buildDeviceList(context, sorted)
          else
            Text(
              'Scanning for nearby devices...',
              style: TextStyle(
                color: AppTheme.nbInk.withValues(alpha: 0.4),
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildDeviceList(
    BuildContext context,
    List<ScanResult> results,
  ) {
    return [
      NBBadge(
        label: '${results.length} device${results.length == 1 ? '' : 's'} nearby',
        color: AppTheme.nbAccent.withValues(alpha: 0.3),
      ),
      const SizedBox(height: 8),
      Container(
        height: 240,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.nbRadius),
          border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
          color: AppTheme.nbCard,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.zero,
          child: ListView.separated(
            itemCount: results.length,
            separatorBuilder: (_, _) =>
                Divider(height: 1, thickness: 1, color: AppTheme.nbInk.withValues(alpha: 0.15)),
            itemBuilder: (context, i) {
              final r = results[i];
              final isCealDevice =
                  r.advertisementData.manufacturerData.containsKey(kManufacturerId);
              final advName = r.advertisementData.advName;
              final label = advName.isNotEmpty
                  ? advName
                  : r.device.remoteId.str;
              return ListTile(
                dense: true,
                leading: NBIconBox(
                  icon: isCealDevice ? Icons.warning_amber_rounded : Icons.bluetooth,
                  size: 32,
                  bgColor: isCealDevice
                      ? AppTheme.nbWarn.withValues(alpha: 0.2)
                      : AppTheme.nbAccent2.withValues(alpha: 0.1),
                  color: isCealDevice ? AppTheme.nbWarn : AppTheme.nbInk.withValues(alpha: 0.4),
                ),
                title: Text(
                  label,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: isCealDevice
                    ? Text(
                        'CEAL device',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.nbWarn,
                        ),
                      )
                    : null,
                trailing: _RssiChip(rssi: r.rssi),
              );
            },
          ),
        ),
      ),
    ];
  }
}

class _RssiChip extends StatelessWidget {
  const _RssiChip({required this.rssi});

  final int rssi;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    if (rssi >= -60) {
      color = AppTheme.nbOk;
      icon = Icons.signal_cellular_alt;
    } else if (rssi >= -75) {
      color = AppTheme.nbWarn;
      icon = Icons.signal_cellular_alt_2_bar;
    } else {
      color = AppTheme.nbError;
      icon = Icons.signal_cellular_alt_1_bar;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.zero,
        border: Border.all(color: color, width: AppTheme.nbBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$rssi dBm',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _StatusView extends StatelessWidget {
  const _StatusView({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        RepaintBoundary(
          child: SizedBox(
            width: 56,
            height: 56,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 12),
        Text(
          label,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
      ],
    );
  }
}

class _SentView extends StatelessWidget {
  const _SentView({
    required this.onReset,
    required this.backendConfirmed,
    required this.smsSent,
  });

  final VoidCallback onReset;
  final bool backendConfirmed;
  final bool smsSent;

  @override
  Widget build(BuildContext context) {
    final String subtitle;
    if (backendConfirmed) {
      subtitle = 'Alert uploaded to server and broadcast to nearby devices.';
    } else if (smsSent) {
      subtitle =
          'Server unreachable — SMS sent to emergency contacts. Alert queued and will upload when connection returns.';
    } else {
      subtitle =
          'Broadcast to nearby BLE devices. Alert queued — will upload to server when connection returns.';
    }

    final statusColor = backendConfirmed ? AppTheme.nbOk : AppTheme.nbWarn;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(AppTheme.nbRadius),
            border: Border.all(color: AppTheme.nbInk, width: AppTheme.nbBorder),
            boxShadow: AppTheme.nbShadow,
          ),
          child: Icon(
            backendConfirmed ? Icons.check_circle : Icons.check_circle_outline,
            size: 44,
            color: statusColor,
          ),
        ),
        const SizedBox(height: 16),
        Text('SOS Sent', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppTheme.nbInk.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 24),
        NBButton(
          label: 'Back',
          onPressed: onReset,
          icon: Icons.arrow_back,
          color: AppTheme.nbInk.withValues(alpha: 0.7),
        ),
      ],
    );
  }
}
