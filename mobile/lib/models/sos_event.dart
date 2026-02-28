/// SOS Event model — core domain object relayed over BLE and backend.
library;

import 'dart:typed_data';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/sos_type.dart';

enum SosStatus { active, relayed, acknowledged, resolved, cancelled }

class ReceiverLocation {
  const ReceiverLocation({required this.lat, required this.lon, this.accuracy});

  final double lat;
  final double lon;
  final double? accuracy;

  Map<String, dynamic> toJson() => {
    'lat': lat,
    'lon': lon,
    if (accuracy != null) 'accuracy': accuracy,
  };

  factory ReceiverLocation.fromJson(Map<String, dynamic> json) {
    return ReceiverLocation(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      accuracy: json['accuracy'] != null
          ? (json['accuracy'] as num).toDouble()
          : null,
    );
  }
}

class SosEvent {
  SosEvent({
    required this.id,
    required this.bleUid,
    required this.flags,
    required this.sequence,
    required this.timestamp,
    this.status = SosStatus.active,
    this.relayHops = 0,
    this.receiverLocation,
    this.rssi,
    this.message,
  });

  final String id;
  final Uint8List bleUid;
  final int flags;
  final int sequence;
  final DateTime timestamp;
  SosStatus status;
  int relayHops;
  ReceiverLocation? receiverLocation;
  int? rssi;
  final String? message;

  String get bleUidHex =>
      bleUid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Duration get age => DateTime.now().toUtc().difference(timestamp);
  bool get isExpired => age > kPacketMaxAge;

  /// SOS type extracted from bits 2-5 of the flags byte.
  SosType get sosType => SosType.fromFlags(flags);

  Map<String, dynamic> toJson() => {
    'id': id,
    'bleUid': bleUidHex,
    'flags': flags,
    'sequence': sequence,
    'timestamp': timestamp.toUtc().toIso8601String(),
    'status': status.name,
    'relayHops': relayHops,
    if (receiverLocation != null)
      'receiverLocation': receiverLocation!.toJson(),
    if (rssi != null) 'rssi': rssi,
    if (message != null) 'message': message,
  };

  factory SosEvent.fromJson(Map<String, dynamic> json) {
    final hex = json['bleUid'] as String? ?? '';
    final uid = Uint8List(kBleUidSize);
    if (hex.length >= kBleUidSize * 2) {
      for (int i = 0; i < kBleUidSize; i++) {
        uid[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
      }
    }

    return SosEvent(
      id: json['id'] as String,
      bleUid: uid,
      flags: json['flags'] as int? ?? 0,
      sequence: json['sequence'] as int? ?? 0,
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      status: SosStatus.values.byName((json['status'] as String?) ?? 'active'),
      relayHops: json['relayHops'] as int? ?? 0,
      receiverLocation: json['receiverLocation'] is Map<String, dynamic>
          ? ReceiverLocation.fromJson(
              json['receiverLocation'] as Map<String, dynamic>,
            )
          : null,
      rssi: json['rssi'] as int?,
      message: json['message'] as String?,
    );
  }

  @override
  String toString() {
    return 'SosEvent($id, $status, uid=$bleUidHex, seq=$sequence, hops=$relayHops)';
  }
}
