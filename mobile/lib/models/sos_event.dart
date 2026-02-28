/// SOS Event model — the core domain object transmitted over the mesh.
library;

import 'dart:typed_data';

import 'package:aftermath/core/constants.dart';

/// Current lifecycle state of an SOS event.
enum SosStatus {
  /// User triggered; broadcasting.
  active,

  /// Relayed by at least one bystander.
  relayed,

  /// A responder has acknowledged the event.
  acknowledged,

  /// Incident resolved / closed.
  resolved,

  /// User cancelled before timeout.
  cancelled,
}

class SosEvent {
  SosEvent({
    required this.id,
    required this.deviceIdHash,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.status = SosStatus.active,
    this.relayHops = 0,
    this.message,
  });

  // -------------------------------------------------------------------------
  // Fields
  // -------------------------------------------------------------------------

  /// Unique identifier for this SOS. Typically a short UUID.
  final String id;

  /// 2-byte hash of the originating device ID.
  final Uint8List deviceIdHash;

  /// GPS latitude (decimal degrees).
  final double latitude;

  /// GPS longitude (decimal degrees).
  final double longitude;

  /// When the SOS was triggered (UTC).
  final DateTime timestamp;

  /// Current status.
  SosStatus status;

  /// Number of BLE relay hops this event has traversed.
  int relayHops;

  /// Optional short text (max 64 chars) for additional context.
  final String? message;

  // -------------------------------------------------------------------------
  // Compact GPS encoding (10 bytes: 4B lat + 4B lon + 2B deviceIdHash)
  // -------------------------------------------------------------------------

  /// Encode lat/lon/deviceIdHash into a 10-byte payload for BLE fragments.
  ///
  /// Layout:
  /// ```
  /// Bytes 0-3 : latitude      (int32, value × 1e7, big-endian)
  /// Bytes 4-7 : longitude     (int32, value × 1e7, big-endian)
  /// Bytes 8-9 : deviceIdHash  (2 bytes)
  /// ```
  Uint8List toCompactPayload() {
    final bd = ByteData(kBlePayloadSize);
    bd.setInt32(0, (latitude * kGpsScale).round(), Endian.big);
    bd.setInt32(4, (longitude * kGpsScale).round(), Endian.big);
    final buf = bd.buffer.asUint8List();
    buf[8] = deviceIdHash.isNotEmpty ? deviceIdHash[0] : 0;
    buf[9] = deviceIdHash.length > 1 ? deviceIdHash[1] : 0;
    return buf;
  }

  /// Decode a 10-byte compact payload back into partial SOS data.
  static ({double latitude, double longitude, Uint8List deviceIdHash})
      fromCompactPayload(Uint8List payload) {
    if (payload.length < kBlePayloadSize) {
      throw ArgumentError('Payload too short: ${payload.length}');
    }
    final bd = ByteData.sublistView(payload, 0, 10);
    final lat = bd.getInt32(0, Endian.big) / kGpsScale;
    final lon = bd.getInt32(4, Endian.big) / kGpsScale;
    return (
      latitude: lat,
      longitude: lon,
      deviceIdHash: Uint8List.fromList([payload[8], payload[9]]),
    );
  }

  // -------------------------------------------------------------------------
  // JSON serialisation (for backend API / local DB)
  // -------------------------------------------------------------------------

  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceIdHash': deviceIdHash.toList(),
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'status': status.name,
        'relayHops': relayHops,
        if (message != null) 'message': message,
      };

  factory SosEvent.fromJson(Map<String, dynamic> json) => SosEvent(
        id: json['id'] as String,
        deviceIdHash:
            Uint8List.fromList(List<int>.from(json['deviceIdHash'] as List)),
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        timestamp: DateTime.parse(json['timestamp'] as String),
        status: SosStatus.values.byName(json['status'] as String),
        relayHops: json['relayHops'] as int? ?? 0,
        message: json['message'] as String?,
      );

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Elapsed time since the SOS was triggered.
  Duration get age => DateTime.now().toUtc().difference(timestamp);

  /// Whether this event is still relevant for relay.
  bool get isExpired => age > kPacketMaxAge;

  @override
  String toString() =>
      'SosEvent($id, $status, ${latitude.toStringAsFixed(4)},'
      '${longitude.toStringAsFixed(4)}, hops=$relayHops)';
}
