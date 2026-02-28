/// CRC16-CCITT and CRC8 implementations for BLE packet integrity checking.
///
/// CRC16: polynomial 0x1021 (CCITT), initial 0xFFFF — used by legacy 20-byte packet.
/// CRC8:  polynomial 0x07 (CCITT), initial 0x00  — used by V2 10-byte packet.
library;

import 'dart:typed_data';

// ---------------------------------------------------------------------------
// CRC16
// ---------------------------------------------------------------------------

/// Compute CRC16-CCITT over [data].
///
/// Returns a 16-bit unsigned integer.
int computeCrc16(Uint8List data) {
  int crc = 0xFFFF;
  for (final byte in data) {
    crc ^= (byte & 0xFF) << 8;
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x8000) != 0) {
        crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
      } else {
        crc = (crc << 1) & 0xFFFF;
      }
    }
  }
  return crc;
}

/// Verify that the last 2 bytes of [packetWithCrc] are a valid CRC16
/// of the preceding bytes.
///
/// Returns `true` if the checksum matches.
bool verifyCrc16(Uint8List packetWithCrc) {
  if (packetWithCrc.length < 3) return false;
  final payload = packetWithCrc.sublist(0, packetWithCrc.length - 2);
  final bd = ByteData.sublistView(packetWithCrc, packetWithCrc.length - 2);
  final expected = bd.getUint16(0, Endian.big);
  return computeCrc16(Uint8List.fromList(payload)) == expected;
}

// ---------------------------------------------------------------------------
// CRC8
// ---------------------------------------------------------------------------

/// Compute CRC8 (polynomial 0x07, init 0x00) over [data].
///
/// Returns an 8-bit unsigned integer.
int computeCrc8(Uint8List data) {
  int crc = 0x00;
  for (final byte in data) {
    crc ^= byte & 0xFF;
    for (int i = 0; i < 8; i++) {
      if ((crc & 0x80) != 0) {
        crc = ((crc << 1) ^ 0x07) & 0xFF;
      } else {
        crc = (crc << 1) & 0xFF;
      }
    }
  }
  return crc;
}

/// Verify that the last byte of [packetWithCrc] is a valid CRC8
/// of the preceding bytes.
///
/// Returns `true` if the checksum matches.
bool verifyCrc8(Uint8List packetWithCrc) {
  if (packetWithCrc.length < 2) return false;
  final payload = packetWithCrc.sublist(0, packetWithCrc.length - 1);
  final expected = packetWithCrc[packetWithCrc.length - 1];
  return computeCrc8(Uint8List.fromList(payload)) == expected;
}
