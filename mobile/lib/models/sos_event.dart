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
  // Compact GPS encoding (8 bytes total for lat + lon + deviceIdHash)
  // -------------------------------------------------------------------------

  /// Encode lat/lon/deviceIdHash into an 8-byte payload for BLE.
  ///
  /// Layout:
  /// ```
  /// Bytes 0-2 : latitude  (3 bytes, unsigned, scaled)
  /// Bytes 3-5 : longitude (3 bytes, unsigned, scaled)
  /// Bytes 6-7 : deviceIdHash (2 bytes)
  /// ```
  Uint8List toCompactPayload() {
    final buf = Uint8List(kBlePayloadSize);

    // Shift lat from [-90, 90] → [0, 180], then scale.
    final latScaled = ((latitude + 90.0) * kGpsScale).round();
    // Shift lon from [-180, 180] → [0, 360], then scale.
    final lonScaled = ((longitude + 180.0) * kGpsScale).round();

    // Pack as 3 bytes each (big-endian).
    buf[0] = (latScaled >> 16) & 0xFF;
    buf[1] = (latScaled >> 8) & 0xFF;
    buf[2] = latScaled & 0xFF;

    buf[3] = (lonScaled >> 16) & 0xFF;
    buf[4] = (lonScaled >> 8) & 0xFF;
    buf[5] = lonScaled & 0xFF;

    // Device ID hash.
    buf[6] = deviceIdHash.isNotEmpty ? deviceIdHash[0] : 0;
    buf[7] = deviceIdHash.length > 1 ? deviceIdHash[1] : 0;

    return buf;
  }

  /// Decode an 8-byte compact payload back into partial SOS data.
  static ({double latitude, double longitude, Uint8List deviceIdHash})
      fromCompactPayload(Uint8List payload) {
    if (payload.length < kBlePayloadSize) {
      throw ArgumentError('Payload too short: ${payload.length}');
    }

    final latScaled =
        (payload[0] << 16) | (payload[1] << 8) | payload[2];
    final lonScaled =
        (payload[3] << 16) | (payload[4] << 8) | payload[5];

    final lat = (latScaled / kGpsScale) - 90.0;
    final lon = (lonScaled / kGpsScale) - 180.0;

    return (
      latitude: lat,
      longitude: lon,
      deviceIdHash: Uint8List.fromList([payload[6], payload[7]]),
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
