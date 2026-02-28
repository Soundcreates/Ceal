/// BLE fragment packet model — the 13-byte unit of the SOS mesh protocol.
///
/// Layout:
/// ```
///  Byte 0      : sequence number  (0–255)
///  Byte 1      : total chunks     (1–255)
///  Byte 2      : flags            (see [constants.dart])
///  Bytes 3-12  : payload          (10 bytes)
/// ```
library;

import 'dart:typed_data';

import 'package:aftermath/core/constants.dart';

class BlePacket {
  BlePacket({
    required this.sequence,
    required this.totalChunks,
    required this.flags,
    required this.payload,
  }) : assert(payload.length <= kBlePayloadSize);

  // -------------------------------------------------------------------------
  // Fields
  // -------------------------------------------------------------------------

  /// Fragment index (0-based).
  final int sequence;

  /// Total number of fragments for this SOS message.
  final int totalChunks;

  /// Bit-field: msg-type (bits 0-1), encrypted (bit 2), last-chunk (bit 3),
  /// TTL (bits 4-7, decremented per relay hop, max 15).
  final int flags;

  /// 10-byte payload fragment.
  final Uint8List payload;

  // -------------------------------------------------------------------------
  // Convenience getters
  // -------------------------------------------------------------------------

  int get messageType => flags & 0x03;
  bool get isEncrypted => (flags & kFlagEncrypted) != 0;
  bool get isLastChunk => (flags & kFlagLastChunk) != 0;
  int get ttl => (flags >> 4) & 0x0F;

  // -------------------------------------------------------------------------
  // Serialisation (to/from raw bytes)
  // -------------------------------------------------------------------------

  /// Encode this packet into a 13-byte [Uint8List].
  Uint8List toBytes() {
    final bytes = Uint8List(kBlePacketSize);
    bytes[0] = sequence & 0xFF;
    bytes[1] = totalChunks & 0xFF;
    bytes[2] = flags & 0xFF;
    bytes.setRange(3, 3 + payload.length, payload);
    return bytes;
  }

  /// Decode a 13-byte [Uint8List] into a [BlePacket].
  factory BlePacket.fromBytes(Uint8List raw) {
    if (raw.length < kBlePacketSize) {
      throw ArgumentError('Packet too short: ${raw.length} bytes');
    }
    return BlePacket(
      sequence: raw[0],
      totalChunks: raw[1],
      flags: raw[2],
      payload: Uint8List.fromList(raw.sublist(3, kBlePacketSize)),
    );
  }

  /// Create a copy with decremented TTL for relay.
  BlePacket withDecrementedTtl() {
    final currentTtl = ttl;
    if (currentTtl <= 0) {
      throw StateError('Cannot relay packet with TTL=0');
    }
    final newFlags = (flags & 0x0F) | ((currentTtl - 1) << 4);
    return BlePacket(
      sequence: sequence,
      totalChunks: totalChunks,
      flags: newFlags,
      payload: payload,
    );
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  /// Build [flags] byte from individual fields.
  static int buildFlags({
    int messageType = MsgType.sos,
    bool encrypted = false,
    bool lastChunk = false,
    int ttl = kDefaultTtl,
  }) {
    int f = messageType & 0x03;
    if (encrypted) f |= kFlagEncrypted;
    if (lastChunk) f |= kFlagLastChunk;
    f |= (ttl & 0x0F) << 4;
    return f;
  }

  @override
  String toString() =>
      'BlePacket(seq=$sequence/$totalChunks, flags=0x${flags.toRadixString(16)}, '
      'payload=${payload.length}B)';
}
