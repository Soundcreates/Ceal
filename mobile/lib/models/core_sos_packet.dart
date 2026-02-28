/// Core SOS Packet V2 — the 10-byte privacy-first emergency broadcast.
///
/// This is the PRIMARY packet format. Every SOS transmission begins with a
/// burst of these packets. GPS is NOT included — the receiver attaches its
/// own location when forwarding to the backend.
///
/// Layout (10 bytes, big-endian):
/// ```
///  Byte  0     : version    (uint8,  protocol version = 0x02)
///  Byte  1     : flags      (uint8,  see [buildFlags])
///  Bytes 2-7   : bleUid     (6 bytes, static pseudonymous BLE UID)
///  Byte  8     : sequence   (uint8,  wrapping counter 0-255)
///  Byte  9     : CRC8       (uint8,  polynomial 0x07 over bytes 0-8)
/// ```
library;

import 'dart:typed_data';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/core/crc16.dart';

/// Current protocol version for V2 packets.
const int kCorePacketVersion = 2;

class CoreSosPacket {
  const CoreSosPacket({
    this.version = kCorePacketVersion,
    required this.flags,
    required this.bleUid,
    required this.sequence,
  });

  // -----------------------------------------------------------------------
  // Fields
  // -----------------------------------------------------------------------

  /// Protocol version (0x02 for V2).
  final int version;

  /// Flags bit-field: bit 0 = SOS active, bit 1 = medical emergency.
  final int flags;

  /// Static 6-byte pseudonymous BLE UID.
  final Uint8List bleUid;

  /// Wrapping sequence counter (0-255).
  final int sequence;

  // -----------------------------------------------------------------------
  // Convenience getters
  // -----------------------------------------------------------------------

  bool get isSosActive => (flags & 0x01) != 0;
  bool get isMedicalEmergency => (flags & 0x02) != 0;

  /// Hex representation of the BLE UID (e.g. "aabbccddee01").
  String get bleUidHex =>
      bleUid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  // -----------------------------------------------------------------------
  // Serialisation
  // -----------------------------------------------------------------------

  /// Encode into a 10-byte [Uint8List], with CRC8 at the end.
  Uint8List toBytes() {
    final buf = Uint8List(kCorePacketSize);
    buf[0] = version & 0xFF;
    buf[1] = flags & 0xFF;
    // Copy 6-byte BLE UID into bytes 2-7.
    for (int i = 0; i < kBleUidSize; i++) {
      buf[2 + i] = i < bleUid.length ? bleUid[i] : 0;
    }
    buf[8] = sequence & 0xFF;

    // CRC8 over bytes 0-8.
    final crc = computeCrc8(Uint8List.fromList(buf.sublist(0, 9)));
    buf[9] = crc & 0xFF;
    return buf;
  }

  /// Decode a 10-byte [Uint8List] into a [CoreSosPacket].
  ///
  /// Throws [FormatException] if the CRC8 does not match.
  factory CoreSosPacket.fromBytes(Uint8List raw) {
    if (raw.length < kCorePacketSize) {
      throw ArgumentError(
          'Core packet too short: ${raw.length} bytes (need $kCorePacketSize)');
    }

    // Verify CRC8 over bytes 0-8, CRC at byte 9.
    if (!verifyCrc8(Uint8List.fromList(raw.sublist(0, kCorePacketSize)))) {
      throw FormatException('CRC8 mismatch on core SOS packet');
    }

    return CoreSosPacket(
      version: raw[0],
      flags: raw[1],
      bleUid: Uint8List.fromList(raw.sublist(2, 2 + kBleUidSize)),
      sequence: raw[8],
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
      'uid=$bleUidHex, seq=$sequence)';
}
