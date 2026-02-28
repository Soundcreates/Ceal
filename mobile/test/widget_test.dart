// AfterMath unit and widget tests.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/ble_packet.dart';
import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/core/encryption.dart';
import 'package:aftermath/services/location_service.dart';

void main() {
  group('BlePacket', () {
    test('round-trip serialisation', () {
      final payload = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
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
        payload: Uint8List(8),
      );

      final relayed = packet.withDecrementedTtl();
      expect(relayed.ttl, 4);
    });

    test('throws on TTL=0 relay', () {
      final packet = BlePacket(
        sequence: 0,
        totalChunks: 1,
        flags: BlePacket.buildFlags(ttl: 0),
        payload: Uint8List(8),
      );
      expect(() => packet.withDecrementedTtl(), throwsStateError);
    });
  });

  group('SosEvent GPS encoding', () {
    test('compact payload round-trip', () {
      final event = SosEvent(
        id: 'test-1',
        deviceIdHash: Uint8List.fromList([0xAB, 0xCD]),
        latitude: 28.6139,
        longitude: 77.2090,
        timestamp: DateTime.now().toUtc(),
      );

      final payload = event.toCompactPayload();
      expect(payload.length, kBlePayloadSize);

      final decoded = SosEvent.fromCompactPayload(payload);
      // Precision loss expected due to 3-byte scaling  (~0.01 degree).
      expect(decoded.latitude, closeTo(28.6139, 0.01));
      expect(decoded.longitude, closeTo(77.2090, 0.01));
      expect(decoded.deviceIdHash, Uint8List.fromList([0xAB, 0xCD]));
    });

    test('handles negative coordinates', () {
      final event = SosEvent(
        id: 'test-2',
        deviceIdHash: Uint8List.fromList([0x00, 0x01]),
        latitude: -33.8688,
        longitude: -151.2093,
        timestamp: DateTime.now().toUtc(),
      );

      final payload = event.toCompactPayload();
      final decoded = SosEvent.fromCompactPayload(payload);
      expect(decoded.latitude, closeTo(-33.8688, 0.01));
      expect(decoded.longitude, closeTo(-151.2093, 0.01));
    });
  });

  group('SosEvent JSON', () {
    test('round-trip serialisation', () {
      final event = SosEvent(
        id: 'json-test',
        deviceIdHash: Uint8List.fromList([0x12, 0x34]),
        latitude: 40.7128,
        longitude: -74.0060,
        timestamp: DateTime.utc(2026, 2, 28, 12, 0),
        status: SosStatus.active,
        relayHops: 2,
        message: 'Help!',
      );

      final json = event.toJson();
      final restored = SosEvent.fromJson(json);

      expect(restored.id, 'json-test');
      expect(restored.latitude, 40.7128);
      expect(restored.longitude, -74.0060);
      expect(restored.status, SosStatus.active);
      expect(restored.relayHops, 2);
      expect(restored.message, 'Help!');
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
    test('encodeLatLon / decodeLatLon round-trip', () {
      final encoded = LocationService.encodeLatLon(51.5074, -0.1278);
      expect(encoded.length, 6);

      final decoded = LocationService.decodeLatLon(encoded);
      expect(decoded.latitude, closeTo(51.5074, 0.01));
      expect(decoded.longitude, closeTo(-0.1278, 0.01));
    });
  });
}
