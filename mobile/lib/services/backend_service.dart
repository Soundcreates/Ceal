/// Backend Service — REST API client for the AfterMath backend.
library;

import 'dart:convert';

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
  });

  final bool success;
  final int? statusCode;
  final String? error;
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
