// AfterMath unit and widget tests — V2 privacy-first protocol.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/core/crc16.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/core_sos_packet.dart';
import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/core/encryption.dart';
import 'package:aftermath/services/location_service.dart';

void main() {
  group('BlePacket', () {
    test('round-trip serialisation', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]);
      final packet = BlePacket(
        sequence: 0,
        totalChunks: 1,
        flags: BlePacket.buildFlags(
          messageType: MsgType.sos,
          ttl: 5,
          lastChunk: true,
        ),
        payload: payload,
      );

      final bytes = packet.toBytes();
      expect(bytes.length, kBlePacketSize);
      expect(kBlePacketSize, 13);

      final decoded = BlePacket.fromBytes(bytes);
      expect(decoded.sequence, 0);
      expect(decoded.totalChunks, 1);
      expect(decoded.messageType, MsgType.sos);
      expect(decoded.ttl, 5);
      expect(decoded.isLastChunk, true);
      expect(decoded.payload, payload);
    });

    test('TTL decrement', () {
      final packet = BlePacket(
        sequence: 0,
        totalChunks: 1,
        flags: BlePacket.buildFlags(ttl: 5),
        payload: Uint8List(kBlePayloadSize),
      );

      final relayed = packet.withDecrementedTtl();
      expect(relayed.ttl, 4);
    });

    test('throws on TTL=0 relay', () {
      final packet = BlePacket(
        sequence: 0,
        totalChunks: 1,
        flags: BlePacket.buildFlags(ttl: 0),
        payload: Uint8List(kBlePayloadSize),
      );
      expect(() => packet.withDecrementedTtl(), throwsStateError);
    });
  });

  group('SosEvent V2 JSON', () {
    test('round-trip serialisation with all fields', () {
      final uid = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x01]);
      final event = SosEvent(
        id: 'uid:aabbccddee01:42',
        bleUid: uid,
        flags: 0x01,
        sequence: 42,
        timestamp: DateTime.utc(2026, 2, 28, 12, 0),
        status: SosStatus.active,
        relayHops: 2,
        receiverLocation: const ReceiverLocation(lat: 19.076, lon: 72.8777),
        rssi: -65,
        message: 'Help!',
      );

      final json = event.toJson();
      expect(json['bleUid'], 'aabbccddee01');
      expect(json['flags'], 0x01);
      expect(json['sequence'], 42);
      expect(json['receiverLocation'], isNotNull);
      expect(json['rssi'], -65);

      final restored = SosEvent.fromJson(json);
      expect(restored.id, 'uid:aabbccddee01:42');
      expect(restored.bleUidHex, 'aabbccddee01');
      expect(restored.flags, 0x01);
      expect(restored.sequence, 42);
      expect(restored.status, SosStatus.active);
      expect(restored.relayHops, 2);
      expect(restored.receiverLocation!.lat, 19.076);
      expect(restored.receiverLocation!.lon, 72.8777);
      expect(restored.rssi, -65);
      expect(restored.message, 'Help!');
    });

    test('round-trip without optional fields', () {
      final uid = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]);
      final event = SosEvent(
        id: 'uid:010203040506:0',
        bleUid: uid,
        flags: 0x00,
        sequence: 0,
        timestamp: DateTime.utc(2026, 1, 1),
      );

      final json = event.toJson();
      expect(json.containsKey('receiverLocation'), false);
      expect(json.containsKey('rssi'), false);
      expect(json.containsKey('message'), false);

      final restored = SosEvent.fromJson(json);
      expect(restored.receiverLocation, isNull);
      expect(restored.rssi, isNull);
      expect(restored.message, isNull);
    });

    test('bleUidHex getter returns lowercase hex', () {
      final uid = Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45]);
      final event = SosEvent(
        id: 'test',
        bleUid: uid,
        flags: 0,
        sequence: 0,
        timestamp: DateTime.now(),
      );
      expect(event.bleUidHex, 'abcdef012345');
    });
  });

  group('ReceiverLocation', () {
    test('toJson / fromJson round-trip', () {
      const loc = ReceiverLocation(lat: -33.8688, lon: 151.2093, accuracy: 5.5);
      final json = loc.toJson();
      expect(json['lat'], -33.8688);
      expect(json['lon'], 151.2093);
      expect(json['accuracy'], 5.5);

      final restored = ReceiverLocation.fromJson(json);
      expect(restored.lat, -33.8688);
      expect(restored.lon, 151.2093);
      expect(restored.accuracy, 5.5);
    });

    test('omits accuracy when null', () {
      const loc = ReceiverLocation(lat: 0.0, lon: 0.0);
      final json = loc.toJson();
      expect(json.containsKey('accuracy'), false);
    });
  });

  group('EncryptionService', () {
    test('XOR encrypt/decrypt round-trip', () {
      final svc = EncryptionService(secret: 'test-key');
      final original = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final encrypted = svc.encrypt(original, nonce: 'nonce-1');
      expect(encrypted, isNot(equals(original)));

      final decrypted = svc.decrypt(encrypted, nonce: 'nonce-1');
      expect(decrypted, original);
    });

    test('HMAC tag verification', () {
      final svc = EncryptionService(secret: 'test-key');
      final data = Uint8List.fromList([10, 20, 30]);

      final tag = svc.hmacTag(data);
      expect(tag.length, 2);
      expect(svc.verifyTag(data, tag), true);

      // Tampered data should fail.
      final tampered = Uint8List.fromList([10, 20, 31]);
      expect(svc.verifyTag(tampered, tag), false);
    });

    test('deviceIdHash produces 2 bytes', () {
      final svc = EncryptionService();
      final hash = svc.deviceIdHash('some-device-id');
      expect(hash.length, 2);
    });
  });

  group('LocationService encoding', () {
    test('encodeLatLon / decodeLatLon round-trip (8 bytes)', () {
      final encoded = LocationService.encodeLatLon(51.5074, -0.1278);
      expect(encoded.length, 8);

      final decoded = LocationService.decodeLatLon(encoded);
      expect(decoded.latitude, closeTo(51.5074, 0.0000001));
      expect(decoded.longitude, closeTo(-0.1278, 0.0000001));
    });

    test('encodeLatLon handles negative values', () {
      final encoded = LocationService.encodeLatLon(-33.8688, -151.2093);
      final decoded = LocationService.decodeLatLon(encoded);
      expect(decoded.latitude, closeTo(-33.8688, 0.0000001));
      expect(decoded.longitude, closeTo(-151.2093, 0.0000001));
    });
  });

  group('CRC16', () {
    test('computeCrc16 produces a 16-bit value', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final crc = computeCrc16(data);
      expect(crc >= 0 && crc <= 0xFFFF, true);
    });

    test('verifyCrc16 accepts valid data + CRC', () {
      final data = Uint8List.fromList([0x10, 0x20, 0x30, 0x40]);
      final crc = computeCrc16(data);
      final withCrc = Uint8List(6);
      withCrc.setRange(0, 4, data);
      withCrc[4] = (crc >> 8) & 0xFF;
      withCrc[5] = crc & 0xFF;
      expect(verifyCrc16(withCrc), true);
    });

    test('verifyCrc16 rejects tampered data', () {
      final data = Uint8List.fromList([0x10, 0x20, 0x30, 0x40]);
      final crc = computeCrc16(data);
      final withCrc = Uint8List(6);
      withCrc.setRange(0, 4, data);
      withCrc[4] = (crc >> 8) & 0xFF;
      withCrc[5] = crc & 0xFF;
      // Tamper
      withCrc[0] = 0xFF;
      expect(verifyCrc16(withCrc), false);
    });
  });

  group('CRC8', () {
    test('computeCrc8 produces an 8-bit value', () {
      final data = Uint8List.fromList([0x01, 0x02, 0x03]);
      final crc = computeCrc8(data);
      expect(crc >= 0 && crc <= 0xFF, true);
    });

    test('verifyCrc8 accepts valid data + CRC', () {
      final data = Uint8List.fromList([0x10, 0x20, 0x30, 0x40]);
      final crc = computeCrc8(data);
      final withCrc = Uint8List(5);
      withCrc.setRange(0, 4, data);
      withCrc[4] = crc;
      expect(verifyCrc8(withCrc), true);
    });

    test('verifyCrc8 rejects tampered data', () {
      final data = Uint8List.fromList([0x10, 0x20, 0x30, 0x40]);
      final crc = computeCrc8(data);
      final withCrc = Uint8List(5);
      withCrc.setRange(0, 4, data);
      withCrc[4] = crc;
      // Tamper
      withCrc[0] = 0xFF;
      expect(verifyCrc8(withCrc), false);
    });
  });

  group('CoreSosPacket V2', () {
    test('round-trip serialisation (10 bytes)', () {
      final uid = Uint8List.fromList([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0x01]);
      final packet = CoreSosPacket(
        version: kCorePacketVersion,
        flags: CoreSosPacket.buildFlags(sosActive: true),
        bleUid: uid,
        sequence: 42,
      );

      final bytes = packet.toBytes();
      expect(bytes.length, kCorePacketSize);
      expect(kCorePacketSize, 10);

      final decoded = CoreSosPacket.fromBytes(bytes);
      expect(decoded.version, kCorePacketVersion);
      expect(decoded.bleUidHex, 'aabbccddee01');
      expect(decoded.sequence, 42);
      expect(decoded.flags, 0x01);
    });

    test('CRC8 validation rejects tampered bytes', () {
      final uid = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06]);
      final packet = CoreSosPacket(
        version: kCorePacketVersion,
        flags: 0x01,
        bleUid: uid,
        sequence: 99,
      );

      final bytes = packet.toBytes();
      // Tamper with uid byte.
      bytes[3] = 0xFF;
      expect(
        () => CoreSosPacket.fromBytes(bytes),
        throwsA(isA<FormatException>()),
      );
    });

    test('sequence wraps at 255', () {
      final uid = Uint8List.fromList([0, 0, 0, 0, 0, 0]);
      final packet = CoreSosPacket(
        version: kCorePacketVersion,
        flags: 0x00,
        bleUid: uid,
        sequence: 255,
      );

      final decoded = CoreSosPacket.fromBytes(packet.toBytes());
      expect(decoded.sequence, 255);
    });

    test('bleUidHex getter returns lowercase hex', () {
      final uid = Uint8List.fromList([0xAB, 0xCD, 0xEF, 0x01, 0x23, 0x45]);
      final packet = CoreSosPacket(
        version: kCorePacketVersion,
        flags: 0x00,
        bleUid: uid,
        sequence: 0,
      );
      expect(packet.bleUidHex, 'abcdef012345');
    });

    test('buildFlags sets SOS and medical bits', () {
      final flagsBoth = CoreSosPacket.buildFlags(sosActive: true, medicalEmergency: true);
      expect(flagsBoth & 0x01, 0x01); // bit 0 = SOS
      expect(flagsBoth & 0x02, 0x02); // bit 1 = medical
    });
  });
}
