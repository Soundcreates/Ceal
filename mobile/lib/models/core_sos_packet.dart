/// Core SOS Packet — the 20-byte self-contained emergency broadcast.
///
/// This is the PRIMARY packet format. Every SOS transmission begins with a
/// burst of these packets so that a single reception gives the receiver all
/// critical information (identity, location, time).
///
/// Layout (20 bytes, big-endian):
/// ```
///  Byte  0     : version          (uint8,  protocol version)
///  Byte  1     : flags            (uint8,  see [buildFlags])
///  Bytes 2-5   : deviceId         (uint32, hashed user/device ID)
///  Bytes 6-9   : latitude         (int32,  value × 1e7)
///  Bytes 10-13 : longitude        (int32,  value × 1e7)
///  Bytes 14-17 : timestamp        (uint32, Unix epoch seconds)
///  Bytes 18-19 : CRC16-CCITT      (uint16, over bytes 0-17)
/// ```
library;

import 'dart:typed_data';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/core/crc16.dart';

/// Current protocol version.
const int kCorePacketVersion = 1;

class CoreSosPacket {
  const CoreSosPacket({
    this.version = kCorePacketVersion,
    required this.flags,
    required this.deviceId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
  });

  // -----------------------------------------------------------------------
  // Fields
  // -----------------------------------------------------------------------

  /// Protocol version.
  final int version;

  /// Flags bit-field: bit 0 = SOS active, bit 1 = medical emergency.
  final int flags;

  /// 4-byte hashed device/user identifier.
  final int deviceId;

  /// GPS latitude in decimal degrees.
  final double latitude;

  /// GPS longitude in decimal degrees.
  final double longitude;

  /// UTC Unix epoch seconds when the SOS was triggered.
  final int timestamp;

  // -----------------------------------------------------------------------
  // Convenience getters
  // -----------------------------------------------------------------------

  bool get isSosActive => (flags & 0x01) != 0;
  bool get isMedicalEmergency => (flags & 0x02) != 0;

  // -----------------------------------------------------------------------
  // Serialisation
  // -----------------------------------------------------------------------

  /// Encode into a 20-byte [Uint8List] (big-endian), with CRC16 at the end.
  Uint8List toBytes() {
    final bd = ByteData(kCorePacketSize);
    bd.setUint8(0, version & 0xFF);
    bd.setUint8(1, flags & 0xFF);
    bd.setUint32(2, deviceId & 0xFFFFFFFF, Endian.big);
    bd.setInt32(6, (latitude * kGpsScale).round(), Endian.big);
    bd.setInt32(10, (longitude * kGpsScale).round(), Endian.big);
    bd.setUint32(14, timestamp & 0xFFFFFFFF, Endian.big);

    // CRC16 over bytes 0-17.
    final raw = bd.buffer.asUint8List();
    final crc = computeCrc16(Uint8List.fromList(raw.sublist(0, 18)));
    bd.setUint16(18, crc, Endian.big);
    return bd.buffer.asUint8List();
  }

  /// Decode a 20-byte [Uint8List] into a [CoreSosPacket].
  ///
  /// Throws [FormatException] if the CRC16 does not match.
  factory CoreSosPacket.fromBytes(Uint8List raw) {
    if (raw.length < kCorePacketSize) {
      throw ArgumentError(
          'Core packet too short: ${raw.length} bytes (need $kCorePacketSize)');
    }

    // Verify CRC16.
    if (!verifyCrc16(Uint8List.fromList(raw.sublist(0, kCorePacketSize)))) {
      throw FormatException('CRC16 mismatch on core SOS packet');
    }

    final bd = ByteData.sublistView(raw, 0, kCorePacketSize);
    return CoreSosPacket(
      version: bd.getUint8(0),
      flags: bd.getUint8(1),
      deviceId: bd.getUint32(2, Endian.big),
      latitude: bd.getInt32(6, Endian.big) / kGpsScale,
      longitude: bd.getInt32(10, Endian.big) / kGpsScale,
      timestamp: bd.getUint32(14, Endian.big),
    );
  }

  // -----------------------------------------------------------------------
  // Helpers
  // -----------------------------------------------------------------------

  /// Build the [flags] byte.
  static int buildFlags({
    bool sosActive = true,
    bool medicalEmergency = false,
  }) {
    int f = 0;
    if (sosActive) f |= 0x01;
    if (medicalEmergency) f |= 0x02;
    return f;
  }

  @override
  String toString() =>
      'CoreSosPacket(v$version, flags=0x${flags.toRadixString(16)}, '
      'devId=$deviceId, lat=${latitude.toStringAsFixed(5)}, '
      'lon=${longitude.toStringAsFixed(5)}, ts=$timestamp)';
}
