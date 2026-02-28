/// BLE advertiser service for SOS packets.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_ble_peripheral/flutter_ble_peripheral.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/core_sos_packet.dart';

class BleAdvertiserService {
  final FlutterBlePeripheral _peripheral = FlutterBlePeripheral();

  bool _isAdvertising = false;
  bool get isAdvertising => _isAdvertising;

  /// Timer for continuous re-advertising during an active SOS session.
  Timer? _continuousTimer;

  /// How long to keep re-advertising (total session duration).
  static const _sosBroadcastDuration = Duration(seconds: 60);

  /// Interval between re-advertising rounds.
  static const _reAdvertiseInterval = Duration(seconds: 15);

  Future<void> broadcastCoreSos(CoreSosPacket packet) async {
    final raw = packet.toBytes();

    // Full hex dump + field breakdown so every broadcast is traceable.
    final hexDump = raw.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    // CORE V2 layout: [version(0)] [flags(1)] [bleUid(2..7)] [seq(8)] [ttl(9)] [crc8(10)]
    final version = raw.isNotEmpty ? '0x${raw[0].toRadixString(16).padLeft(2, '0')}' : '??';
    final flags   = raw.length > 1 ? '0x${raw[1].toRadixString(16).padLeft(2, '0')}' : '??';
    final uidHex  = raw.length >= 8
        ? raw.sublist(2, 8).map((b) => b.toRadixString(16).padLeft(2, '0')).join(':')
        : '??';
    final seq  = raw.length > 8 ? raw[8] : -1;
    final ttl  = raw.length > 9 ? raw[9] : -1;
    final crc8 = raw.length > 10 ? '0x${raw[10].toRadixString(16).padLeft(2, '0')}' : '??';
    debugPrint(
      '[BleAdvertiserService] BEGIN CORE V2 broadcast | '
      'len=${raw.length} ver=$version flags=$flags uid=$uidHex seq=$seq ttl=$ttl crc8=$crc8 | '
      'hex: $hexDump',
    );

    // --- Initial burst round ---
    await _runBurstCycle(raw, uidHex, seq);

    // --- Continuous re-advertising: repeat bursts every 15s for 60s ---
    // This ensures receivers pick up the signal even if their scan is throttled.
    stopContinuousBroadcast(); // clear any previous timer
    final stopAt = DateTime.now().add(_sosBroadcastDuration);
    _continuousTimer = Timer.periodic(_reAdvertiseInterval, (timer) async {
      if (DateTime.now().isAfter(stopAt)) {
        timer.cancel();
        _continuousTimer = null;
        debugPrint(
          '[BleAdvertiserService] Continuous broadcast session ended.',
        );
        return;
      }
      debugPrint('[BleAdvertiserService] Re-advertising burst round…');
      await _runBurstCycle(raw, uidHex, seq);
    });

    debugPrint(
      '[BleAdvertiserService] CORE V2 initial broadcast complete | '
      'uid=$uidHex seq=$seq | continuous re-advertising active for 60s',
    );
  }

  /// Run one full burst cycle (kAdvertiseBurstCount rounds).
  Future<void> _runBurstCycle(Uint8List raw, String uidHex, int seq) async {
    for (int burst = 0; burst < kAdvertiseBurstCount; burst++) {
      debugPrint(
        '[BleAdvertiserService] Burst ${burst + 1}/$kAdvertiseBurstCount — start',
      );
      await stopAdvertising(); // ensure previous slot is released
      await _advertiseRawBytes(raw);
      // Hold for kBurstInterval so the receiver can pick up the packet.
      await Future<void>.delayed(kBurstInterval);
      await stopAdvertising();
      debugPrint(
        '[BleAdvertiserService] Burst ${burst + 1}/$kAdvertiseBurstCount — stopped',
      );
      if (burst < kAdvertiseBurstCount - 1) {
        await Future<void>.delayed(kChunkDelay);
      }
    }
    await stopAdvertising();
  }

  /// Stop the continuous re-advertising timer and any active BLE advertising.
  void stopContinuousBroadcast() {
    _continuousTimer?.cancel();
    _continuousTimer = null;
  }

  Future<void> broadcastPacket(BlePacket packet) async {
    await _advertiseRawBytes(packet.toBytes());
    await Future<void>.delayed(kChunkDelay);
    await stopAdvertising();
  }

  Future<void> stopAdvertising() async {
    // Always ask the controller to stop — even if our flag says idle —
    // because a failed start() can leave a phantom hardware slot allocated.
    try {
      await _peripheral.stop();
    } catch (e) {
      debugPrint('[BleAdvertiserService] Stop error: $e');
    }
    _isAdvertising = false;
    // Give the BLE controller time to fully release the advertising set.
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _advertiseRawBytes(Uint8List raw) async {
    final advertiseData = AdvertiseData(
      serviceUuid: kSosServiceUuid,
      manufacturerId: kManufacturerId,
      manufacturerData: raw,
    );

    final advertiseSettings = AdvertiseSettings(
      advertiseMode: AdvertiseMode.advertiseModeBalanced,
      connectable: false,
      timeout: 0, // 0 = advertise until stopped explicitly; we manage lifetime
      txPowerLevel: AdvertiseTxPower.advertiseTxPowerHigh,
    );

    debugPrint(
      '[BleAdvertiserService] _advertiseRawBytes | svcUuid=$kSosServiceUuid '
      'mfgId=0x${kManufacturerId.toRadixString(16).padLeft(4, '0')} '
      'payloadLen=${raw.length} isAdvertising=$_isAdvertising',
    );

    try {
      await _peripheral.start(
        advertiseData: advertiseData,
        advertiseSettings: advertiseSettings,
      );
      _isAdvertising = true;
      debugPrint('[BleAdvertiserService] Advertising started OK');
    } catch (e, st) {
      debugPrint('[BleAdvertiserService] Advertise error: $e\n$st');

      // Retry once on TOO_MANY_ADVERTISERS — force-stop all slots first.
      if (e.toString().contains('TOO_MANY_ADVERTISERS')) {
        debugPrint('[BleAdvertiserService] Retrying after forced stop…');
        await stopAdvertising();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        try {
          await _peripheral.start(
            advertiseData: advertiseData,
            advertiseSettings: advertiseSettings,
          );
          _isAdvertising = true;
          debugPrint('[BleAdvertiserService] Retry succeeded');
        } catch (e2) {
          debugPrint('[BleAdvertiserService] Retry also failed: $e2');
        }
      }
    }
  }

  Future<void> dispose() async {
    stopContinuousBroadcast();
    await stopAdvertising();
  }
}
