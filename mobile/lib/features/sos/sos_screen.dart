/// SOS screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:aftermath/core/app_theme.dart';
import 'package:aftermath/core/constants.dart';
import 'package:aftermath/features/sos/sos_notifier.dart';
import 'package:aftermath/providers.dart';

class SosScreen extends ConsumerWidget {
  const SosScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sosState = ref.watch(sosNotifierProvider);
    final notifier = ref.read(sosNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('AfterMath SOS'),
        actions: [
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
        child: Center(
          child: _buildBody(context, sosState, notifier),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, SosState sosState, SosNotifier notifier) {
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
          onCancel: () {
            HapticFeedback.mediumImpact();
            notifier.cancelSos();
          },
        );
      case SosPhase.locating:
        return const _StatusView(
          icon: Icons.my_location,
          label: 'Acquiring location...',
          color: Colors.amber,
        );
      case SosPhase.broadcasting:
        return const _BroadcastingView();
      case SosPhase.awaitingAck:
        return const _StatusView(
          icon: Icons.cloud_upload,
          label: 'Uploading to server...',
          color: Colors.orange,
        );
      case SosPhase.smsFallback:
        return const _StatusView(
          icon: Icons.sms,
          label: 'Sending SMS fallback...',
          color: Colors.deepOrange,
        );
      case SosPhase.sent:
        return _SentView(
          onReset: notifier.reset,
          backendConfirmed: sosState.backendConfirmed,
          smsSent: sosState.smsSent,
        );
      case SosPhase.cancelled:
        return const _StatusView(
          icon: Icons.cancel_outlined,
          label: 'SOS Cancelled',
          color: Colors.grey,
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
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              errorMessage!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
          const SizedBox(height: 24),
        ],
        const Text(
          'Press and hold to\nsend emergency SOS',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.white70),
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
              boxShadow: [
                BoxShadow(
                  color: AppTheme.sosColor.withValues(alpha: 0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: const Center(
              child: Text(
                'SOS',
                style: TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
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
  const _CountdownView({required this.remaining, required this.onCancel});

  final int remaining;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.warning_amber_rounded, size: 64, color: Colors.amber),
        const SizedBox(height: 16),
        Text('Sending SOS in', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          '$remaining',
          style: const TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.bold,
            color: Colors.amber,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onCancel,
          icon: const Icon(Icons.close),
          label: const Text('CANCEL'),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.grey[700],
            minimumSize: const Size(180, 56),
          ),
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
                valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Icon(Icons.bluetooth_searching, color: Colors.blue, size: 40),
          const SizedBox(height: 12),
          Text(
            'Broadcasting SOS via BLE...',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 20),
          if (sorted.isNotEmpty) ..._buildDeviceList(context, sorted)
          else
            Text(
              'Scanning for nearby devices...',
              style: TextStyle(
                color: Colors.white38,
                fontSize: 13,
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildDeviceList(BuildContext context, List<ScanResult> results) {
    return [
      Text(
        '${results.length} device${results.length == 1 ? '' : 's'} nearby',
        style: Theme.of(context)
            .textTheme
            .labelMedium
            ?.copyWith(color: Colors.white60),
      ),
      const SizedBox(height: 8),
      SizedBox(
        height: 240,
        child: ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) =>
              const Divider(height: 1, color: Color(0x1FFFFFFF)),
          itemBuilder: (context, i) {
            final r = results[i];
            final isAfterMath =
                r.advertisementData.manufacturerData.containsKey(kManufacturerId);
            final advName = r.advertisementData.advName;
            final label = advName.isNotEmpty
                ? advName
                : r.device.remoteId.str;
            return ListTile(
              dense: true,
              leading: Icon(
                isAfterMath
                    ? Icons.warning_amber_rounded
                    : Icons.bluetooth,
                color: isAfterMath ? Colors.amber : Colors.white38,
                size: 20,
              ),
              title: Text(
                label,
                style: const TextStyle(fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: isAfterMath
                  ? Text(
                      'AfterMath device',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.withValues(alpha: 0.8),
                      ),
                    )
                  : null,
              trailing: _RssiChip(rssi: r.rssi),
            );
          },
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
      color = Colors.greenAccent;
      icon = Icons.signal_cellular_alt;
    } else if (rssi >= -75) {
      color = Colors.amber;
      icon = Icons.signal_cellular_alt_2_bar;
    } else {
      color = Colors.redAccent;
      icon = Icons.signal_cellular_alt_1_bar;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$rssi dBm',
          style: TextStyle(fontSize: 11, color: color),
        ),
      ],
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
        Icon(icon, color: color, size: 40),
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
      subtitle = 'Server unreachable — SMS sent to emergency contacts. Alert queued and will upload when connection returns.';
    } else {
      subtitle = 'Broadcast to nearby BLE devices. Alert queued — will upload to server when connection returns.';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          backendConfirmed ? Icons.check_circle : Icons.check_circle_outline,
          size: 72,
          color: backendConfirmed ? Colors.green : Colors.amber,
        ),
        const SizedBox(height: 16),
        Text('SOS Sent', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        const SizedBox(height: 24),
        OutlinedButton(
          onPressed: onReset,
          child: const Text('Back'),
        ),
      ],
    );
  }
}
