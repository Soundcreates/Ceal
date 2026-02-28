/// Backend Service — REST API client for the AfterMath backend.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/aadhaar_qr_data.dart';
import 'package:aftermath/models/sos_event.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Log a completed HTTP call with timing.
void _logResponse(
  String tag,
  String method,
  Uri url,
  int statusCode,
  int elapsedMs, {
  String? bodyExcerpt,
}) {
  final ok = statusCode >= 200 && statusCode < 300;
  final excerpt =
      bodyExcerpt != null && bodyExcerpt.isNotEmpty ? ' body=${bodyExcerpt.substring(0, bodyExcerpt.length.clamp(0, 200))}' : '';
  debugPrint(
    '[$tag] ${ok ? '✓' : '✗'} $method ${url.path} → $statusCode (${elapsedMs}ms)$excerpt',
  );
}

/// Log an unhandled exception before returning a failure.
void _logException(String tag, String method, Uri url, Object e) {
  debugPrint('[$tag] $method ${url.path} threw: $e');
}

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
    final body = jsonEncode(event.toJson());
    debugPrint(
      '[BackendService] → POST ${url.path} | id=${event.id} '
      'flags=${event.flags} seq=${event.sequence} '
      'relayHops=${event.relayHops} bodyLen=${body.length}',
    );
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 10));
      sw.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _logResponse('BackendService', 'POST', url, response.statusCode, sw.elapsedMilliseconds);
        return true;
      }
      _logResponse(
        'BackendService', 'POST', url, response.statusCode, sw.elapsedMilliseconds,
        bodyExcerpt: response.body,
      );
      return false;
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'POST', url, e);
      debugPrint('[BackendService] ingestSos elapsed before error: ${sw.elapsedMilliseconds}ms');
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
    // rawXml is PII — log length only, never content.
    final payload = {'userId': userId, 'rawXml': data.rawXml};
    final body = jsonEncode(payload);
    debugPrint(
      '[BackendService] → POST ${url.path} | userId=$userId xmlLen=${data.rawXml.length} bodyLen=${body.length}',
    );
    final sw = Stopwatch()..start();

    try {
      final response = await _client
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 12));
      sw.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _logResponse('BackendService', 'POST', url, response.statusCode, sw.elapsedMilliseconds);
        return AadhaarQrSubmitResult(
          success: true,
          statusCode: response.statusCode,
        );
      }

      _logResponse(
        'BackendService', 'POST', url, response.statusCode, sw.elapsedMilliseconds,
        bodyExcerpt: response.body,
      );
      String? msg;
      try {
        final bodyDecoded = jsonDecode(response.body);
        if (bodyDecoded is Map<String, dynamic>) {
          final err = bodyDecoded['error'];
          if (err is String && err.trim().isNotEmpty) msg = err.trim();
        }
      } catch (_) {}
      return AadhaarQrSubmitResult(
        success: false,
        statusCode: response.statusCode,
        error: msg ?? 'Request failed (${response.statusCode})',
      );
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'POST', url, e);
      return AadhaarQrSubmitResult(success: false, error: 'Network error: $e');
    }
  }

  // -------------------------------------------------------------------------
  // SOS Acknowledgement
  // -------------------------------------------------------------------------

  /// Acknowledge an SOS event by its [sosId].
  Future<bool> acknowledgeSos(String sosId) async {
    final url = Uri.parse('$_baseUrl$kApiSosAck');
    debugPrint('[BackendService] → POST ${url.path} | sosId=$sosId');
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .post(url, headers: _headers, body: jsonEncode({'id': sosId}))
          .timeout(const Duration(seconds: 10));
      sw.stop();
      _logResponse(
        'BackendService', 'POST', url, response.statusCode, sw.elapsedMilliseconds,
        bodyExcerpt: response.statusCode >= 400 ? response.body : null,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'POST', url, e);
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Fetch active SOS events (for responder dashboard / alert list)
  // -------------------------------------------------------------------------

  /// Get current active SOS events from the backend.
  Future<List<SosEvent>> fetchActiveEvents() async {
    final url = Uri.parse('$_baseUrl$kApiSosActive');
    debugPrint('[BackendService] → GET ${url.path}');
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 10));
      sw.stop();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          final events = decoded
              .whereType<Map<String, dynamic>>()
              .map((e) => SosEvent.fromJson(e))
              .toList();
          _logResponse('BackendService', 'GET', url, response.statusCode, sw.elapsedMilliseconds);
          debugPrint('[BackendService] fetchActiveEvents: ${events.length} event(s) received');
          return events;
        }
      }
      _logResponse(
        'BackendService', 'GET', url, response.statusCode, sw.elapsedMilliseconds,
        bodyExcerpt: response.body,
      );
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'GET', url, e);
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
