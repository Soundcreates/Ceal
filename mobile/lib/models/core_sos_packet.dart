/// Core SOS Packet V2.
library;

import 'dart:typed_data';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/core/crc16.dart';
import 'package:aftermath/models/sos_type.dart';

const int kCorePacketVersion = 2;

class CoreSosPacket {
  const CoreSosPacket({
    this.version = kCorePacketVersion,
    required this.flags,
    required this.bleUid,
    required this.sequence,
  });

  final int version;
  final int flags;
  final Uint8List bleUid;
  final int sequence;

  bool get isSosActive => (flags & 0x01) != 0;
  bool get isMedicalEmergency => (flags & 0x02) != 0;

  /// SOS type encoded in bits 2-5 of flags.
  SosType get sosType => SosType.fromFlags(flags);

  String get bleUidHex =>
      bleUid.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  Uint8List toBytes() {
    final buf = Uint8List(kCorePacketSize);
    buf[0] = version & 0xFF;
    buf[1] = flags & 0xFF;
    for (int i = 0; i < kBleUidSize; i++) {
      buf[2 + i] = i < bleUid.length ? bleUid[i] : 0;
    }
    buf[8] = sequence & 0xFF;
    buf[9] = computeCrc8(Uint8List.fromList(buf.sublist(0, 9)));
    return buf;
  }

  factory CoreSosPacket.fromBytes(Uint8List raw) {
    if (raw.length < kCorePacketSize) {
      throw ArgumentError(
        'Core packet too short: ${raw.length} bytes (need $kCorePacketSize)',
      );
    }

    if (!verifyCrc8(Uint8List.fromList(raw.sublist(0, kCorePacketSize)))) {
      throw const FormatException('CRC8 mismatch on core SOS packet');
    }

    return CoreSosPacket(
      version: raw[0],
      flags: raw[1],
      bleUid: Uint8List.fromList(raw.sublist(2, 2 + kBleUidSize)),
      sequence: raw[8],
    );
  }

  static int buildFlags({
    bool sosActive = true,
    bool medicalEmergency = false,
    SosType sosType = SosType.general,
  }) {
    int f = 0;
    if (sosActive) f |= 0x01;
    if (medicalEmergency) f |= 0x02;
    // Encode SOS type in bits 2-5.
    f |= sosType.toByte();
    return f;
  }

  @override
  String toString() {
    return 'CoreSosPacket(v$version, flags=0x${flags.toRadixString(16)}, '
        'uid=$bleUidHex, seq=$sequence)';
  }
}
