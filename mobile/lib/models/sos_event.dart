/// SOS Event model — the core domain object transmitted over the mesh.
///
/// V2: privacy-first — the BLE packet carries only a static UID, not GPS.
/// The receiver attaches its own location when forwarding to the backend.
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

// ---------------------------------------------------------------------------
// Receiver / relay location model
// ---------------------------------------------------------------------------

/// Location of the receiver that captured or relayed this SOS.
class ReceiverLocation {
  const ReceiverLocation({
    required this.lat,
    required this.lon,
    this.accuracy,
  });

  final double lat;
  final double lon;

  /// Horizontal accuracy in metres (optional).
  final double? accuracy;

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        if (accuracy != null) 'accuracy': accuracy,
      };

  factory ReceiverLocation.fromJson(Map<String, dynamic> json) =>
      ReceiverLocation(
        lat: (json['lat'] as num).toDouble(),
        lon: (json['lon'] as num).toDouble(),
        accuracy: json['accuracy'] != null
            ? (json['accuracy'] as num).toDouble()
            : null,
      );

  @override
  String toString() => 'ReceiverLocation($lat, $lon, acc=$accuracy)';
}

// ---------------------------------------------------------------------------
// SOS Event
// ---------------------------------------------------------------------------

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

  // -------------------------------------------------------------------------
  // Fields
  // -------------------------------------------------------------------------

  /// Unique identifier for this SOS. Dedup key = `uid:{hex}:{sequence}`.
  final String id;

  /// Static 6-byte BLE UID of the victim (pseudonymous).
  final Uint8List bleUid;

  /// Flags from the CoreSosPacket (bit 0 = SOS active, bit 1 = medical).
  final int flags;

  /// Sequence counter from the CoreSosPacket (0-255, wrapping).
  final int sequence;

  /// When the SOS was first received (UTC).
  final DateTime timestamp;

  /// Current status.
  SosStatus status;

  /// Number of BLE relay hops this event has traversed.
  int relayHops;

  /// Location of the receiver that captured this SOS (NOT the victim's).
  ReceiverLocation? receiverLocation;

  /// BLE RSSI at the receiver (dBm, negative).
  int? rssi;

  /// Optional short text (max 64 chars) for additional context.
  final String? message;

  // -------------------------------------------------------------------------
  // Convenience
  // -------------------------------------------------------------------------

  /// Hex representation of the BLE UID (e.g. "aabbccddee01").
  String get bleUidHex =>
      bleUid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // -------------------------------------------------------------------------
  // JSON serialisation (for backend API / local DB)
  // -------------------------------------------------------------------------

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
    // Parse bleUid from hex string.
    final hexStr = json['bleUid'] as String;
    final uidBytes = Uint8List(kBleUidSize);
    for (int i = 0; i < kBleUidSize; i++) {
      uidBytes[i] = int.parse(hexStr.substring(i * 2, i * 2 + 2), radix: 16);
    }

    return SosEvent(
      id: json['id'] as String,
      bleUid: uidBytes,
      flags: json['flags'] as int? ?? 0,
      sequence: json['sequence'] as int? ?? 0,
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: SosStatus.values.byName(json['status'] as String),
      relayHops: json['relayHops'] as int? ?? 0,
      receiverLocation: json['receiverLocation'] != null
          ? ReceiverLocation.fromJson(
              json['receiverLocation'] as Map<String, dynamic>)
          : null,
      rssi: json['rssi'] as int?,
      message: json['message'] as String?,
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Elapsed time since the SOS was first received.
  Duration get age => DateTime.now().toUtc().difference(timestamp);

  /// Whether this event is still relevant for relay.
  bool get isExpired => age > kPacketMaxAge;

  @override
  String toString() =>
      'SosEvent($id, $status, uid=$bleUidHex, seq=$sequence, '
      'hops=$relayHops)';
}
