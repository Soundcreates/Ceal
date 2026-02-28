/// Backend Service — REST API client for the AfterMath backend.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/aadhaar_qr_data.dart';
import 'package:aftermath/models/sos_event.dart';

class AadhaarQrSubmitResult {
  const AadhaarQrSubmitResult({
    required this.success,
    this.statusCode,
    this.error,
    this.decodedXml,
  });

  final bool success;
  final int? statusCode;
  final String? error;
  final String? decodedXml;
}

class BackendService {
  BackendService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? kApiBaseUrl;

  final http.Client _client;
  final String _baseUrl;

  /// Auth token set after user authentication.
  String? authToken;

  // -------------------------------------------------------------------------
  // Headers
  // -------------------------------------------------------------------------

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (authToken != null) 'Authorization': 'Bearer $authToken',
  };

  // -------------------------------------------------------------------------
  // SOS Ingestion
  // -------------------------------------------------------------------------

  /// Upload an SOS event to the backend ingestion endpoint.
  ///
  /// Returns `true` on success, `false` on failure.
  Future<bool> ingestSos(SosEvent event) async {
    final url = Uri.parse('$_baseUrl$kApiSosIngest');
    try {
      final response = await _client
          .post(url, headers: _headers, body: jsonEncode(event.toJson()))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('[BackendService] SOS ingested: ${event.id}');
        return true;
      }
      debugPrint(
        '[BackendService] Ingest failed: ${response.statusCode} ${response.body}',
      );
      return false;
    } catch (e) {
      debugPrint('[BackendService] Ingest error: $e');
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Onboarding (Aadhaar QR)
  // -------------------------------------------------------------------------

  /// Submit scanned Aadhaar QR XML payload for onboarding verification.
  Future<AadhaarQrSubmitResult> submitAadhaarQr({
    required String userId,
    required AadhaarQrData data,
  }) async {
    final url = Uri.parse('$_baseUrl$kApiOnboardingVerifyAadhaarQr');
    final payload = {'userId': userId, 'rawXml': data.rawXml};

    try {
      final response = await _client
          .post(url, headers: _headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AadhaarQrSubmitResult(
          success: true,
          statusCode: response.statusCode,
        );
      }

      String? msg;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final err = body['error'];
          if (err is String && err.trim().isNotEmpty) msg = err.trim();
        }
      } catch (_) {
        // Keep fallback error.
      }
      return AadhaarQrSubmitResult(
        success: false,
        statusCode: response.statusCode,
        error: msg ?? 'Request failed (${response.statusCode})',
      );
    } catch (e) {
      return AadhaarQrSubmitResult(success: false, error: 'Network error: $e');
    }
  }

  /// Upload an Aadhaar QR photo for TS-side decoding + onboarding ingestion.
  ///
  /// TS backend decodes QR and persists KYC details directly.
  Future<AadhaarQrSubmitResult> submitAadhaarQrPhoto({
    required String userId,
    required Uint8List imageBytes,
    String filename = 'aadhaar_qr.jpg',
  }) async {
    final uri = Uri.parse('$_baseUrl/onboarding/scan-aadhaar-photo');
    try {
      final rgba = await _toRgbaPayload(imageBytes);
      final response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'userId': userId,
              'source': 'photo',
              'filename': filename,
              'width': rgba.width,
              'height': rgba.height,
              'rgbaBase64': base64Encode(rgba.rgbaBytes),
            }),
          )
          .timeout(const Duration(seconds: 25));

      Map<String, dynamic>? body;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) body = decoded;
      } catch (_) {
        // Non-JSON body.
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AadhaarQrSubmitResult(
          success: true,
          statusCode: response.statusCode,
          decodedXml: body?['decodedXml'] as String?,
        );
      }

      return AadhaarQrSubmitResult(
        success: false,
        statusCode: response.statusCode,
        error: (body?['error']?.toString().trim().isNotEmpty ?? false)
            ? body!['error'].toString()
            : 'Photo scan failed (${response.statusCode})',
      );
    } catch (e) {
      return AadhaarQrSubmitResult(
        success: false,
        error: 'Photo upload failed: $e',
      );
    }
  }

  /// Submit manual KYC details when Aadhaar scan is skipped.
  Future<AadhaarQrSubmitResult> submitManualKyc({
    required String userId,
    required String name,
    required int age,
    required String sex,
    String? dob,
    String? yob,
    required String state,
    required String district,
    required String pincode,
  }) async {
    final url = Uri.parse('$_baseUrl/onboarding/manual-kyc');
    final payload = {
      'userId': userId,
      'name': name,
      'age': age,
      'sex': sex,
      if (dob != null && dob.trim().isNotEmpty) 'dob': dob.trim(),
      if (yob != null && yob.trim().isNotEmpty) 'yob': yob.trim(),
      'state': state,
      'district': district,
      'pincode': pincode,
    };

    try {
      final response = await _client
          .post(url, headers: _headers, body: jsonEncode(payload))
          .timeout(const Duration(seconds: 12));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return AadhaarQrSubmitResult(
          success: true,
          statusCode: response.statusCode,
        );
      }

      String? msg;
      try {
        final body = jsonDecode(response.body);
        if (body is Map<String, dynamic>) {
          final err = body['error'];
          if (err is String && err.trim().isNotEmpty) msg = err.trim();
          if (msg == null) {
            final details = body['details'];
            if (details is Map<String, dynamic>) {
              for (final entry in details.entries) {
                final key = entry.key;
                final value = entry.value;
                if (value is List && value.isNotEmpty) {
                  msg = '$key: ${value.first}';
                  break;
                }
                if (value is String && value.trim().isNotEmpty) {
                  msg = '$key: $value';
                  break;
                }
              }
            }
          }
        }
      } catch (_) {}

      return AadhaarQrSubmitResult(
        success: false,
        statusCode: response.statusCode,
        error: msg ?? 'Manual KYC failed (${response.statusCode})',
      );
    } catch (e) {
      return AadhaarQrSubmitResult(
        success: false,
        error: 'Manual KYC network error: $e',
      );
    }
  }

  // -------------------------------------------------------------------------
  // SOS Acknowledgement
  // -------------------------------------------------------------------------

  /// Acknowledge an SOS event by its [sosId].
  Future<bool> acknowledgeSos(String sosId) async {
    final url = Uri.parse('$_baseUrl$kApiSosAck');
    try {
      final response = await _client
          .post(url, headers: _headers, body: jsonEncode({'id': sosId}))
          .timeout(const Duration(seconds: 10));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      debugPrint('[BackendService] Acknowledge error: $e');
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Fetch active SOS events (for responder dashboard / alert list)
  // -------------------------------------------------------------------------

  /// Get current active SOS events from the backend.
  Future<List<SosEvent>> fetchActiveEvents() async {
    final url = Uri.parse('$_baseUrl$kApiSosActive');
    try {
      final response = await _client
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          return decoded
              .whereType<Map<String, dynamic>>()
              .map((e) => SosEvent.fromJson(e))
              .toList();
        }
      }
    } catch (e) {
      debugPrint('[BackendService] Fetch active events error: $e');
    }
    return [];
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  void dispose() {
    _client.close();
  }
}

class _RgbaPayload {
  const _RgbaPayload({
    required this.width,
    required this.height,
    required this.rgbaBytes,
  });

  final int width;
  final int height;
  final Uint8List rgbaBytes;
}

Future<_RgbaPayload> _toRgbaPayload(Uint8List encodedImageBytes) async {
  final codec = await ui.instantiateImageCodec(
    encodedImageBytes,
    targetWidth: 1024,
  );
  final frame = await codec.getNextFrame();
  final image = frame.image;
  final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  if (bytes == null) {
    throw StateError('Failed to decode image to RGBA');
  }
  return _RgbaPayload(
    width: image.width,
    height: image.height,
    rgbaBytes: bytes.buffer.asUint8List(),
  );
}
