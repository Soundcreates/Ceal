/// Lightweight encryption helpers for BLE payloads.
///
/// Uses HMAC-SHA256 for integrity and a simple XOR cipher for payload
/// confidentiality within the 8-byte BLE constraint.  A production release
/// should upgrade to AES-256-GCM once the payload can be transmitted over a
/// GATT characteristic (not limited to 8 bytes).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Shared secret used for HMAC and XOR key derivation.
/// In production this should be fetched from the backend during registration
/// and stored in secure storage (e.g. flutter_secure_storage).
const String _defaultSecret = 'aftermath-dev-secret-replace-me';

class EncryptionService {
  EncryptionService({String? secret}) : _secret = secret ?? _defaultSecret;

  final String _secret;

  // -------------------------------------------------------------------------
  // HMAC – message authentication
  // -------------------------------------------------------------------------

  /// Compute a truncated 2-byte HMAC tag for [data].
  /// Used to verify that a packet was not tampered with in transit.
  Uint8List hmacTag(Uint8List data) {
    final hmac = Hmac(sha256, utf8.encode(_secret));
    final digest = hmac.convert(data);
    // Take first 2 bytes as a compact tag (16-bit).
    return Uint8List.fromList(digest.bytes.sublist(0, 2));
  }

  /// Verify an HMAC [tag] against [data].
  bool verifyTag(Uint8List data, Uint8List tag) {
    final expected = hmacTag(data);
    if (tag.length != expected.length) return false;
    // Constant-time comparison.
    int result = 0;
    for (int i = 0; i < tag.length; i++) {
      result |= tag[i] ^ expected[i];
    }
    return result == 0;
  }

  // -------------------------------------------------------------------------
  // XOR cipher – lightweight confidentiality for 8-byte payloads
  // -------------------------------------------------------------------------

  /// Derive an 8-byte key from the secret + a nonce (e.g. sosId).
  Uint8List _deriveKey(String nonce) {
    final input = utf8.encode('$_secret:$nonce');
    final hash = sha256.convert(input);
    return Uint8List.fromList(hash.bytes.sublist(0, 8));
  }

  /// XOR-encrypt [payload] (up to 8 bytes) using a key derived from [nonce].
  Uint8List encrypt(Uint8List payload, {required String nonce}) {
    final key = _deriveKey(nonce);
    final out = Uint8List(payload.length);
    for (int i = 0; i < payload.length; i++) {
      out[i] = payload[i] ^ key[i % key.length];
    }
    return out;
  }

  /// XOR-decrypt (symmetric – same as encrypt).
  Uint8List decrypt(Uint8List ciphertext, {required String nonce}) =>
      encrypt(ciphertext, nonce: nonce);

  // -------------------------------------------------------------------------
  // Device ID hashing
  // -------------------------------------------------------------------------

  /// Hash a device identifier down to a 2-byte value for packet inclusion.
  Uint8List deviceIdHash(String deviceId) {
    final hash = sha256.convert(utf8.encode(deviceId));
    return Uint8List.fromList(hash.bytes.sublist(0, 2));
  }
}
