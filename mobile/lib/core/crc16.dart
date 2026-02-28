/// CRC16-CCITT implementation for BLE packet integrity checking.
///
/// Uses polynomial 0x1021 (CCITT) with initial value 0xFFFF.
/// Produces a 2-byte (16-bit) checksum appended to the 20-byte CORE packet.
library;

import 'dart:typed_data';

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
