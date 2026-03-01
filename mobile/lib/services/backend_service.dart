/// Backend Service — REST API client for the AfterMath backend.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/aadhaar_qr_data.dart';
import 'package:aftermath/models/disaster_report.dart';
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
  final excerpt = bodyExcerpt != null && bodyExcerpt.isNotEmpty
      ? ' body=${bodyExcerpt.substring(0, bodyExcerpt.length.clamp(0, 200))}'
      : '';
  debugPrint(
    '[$tag] ${ok ? '✓' : '✗'} $method ${url.path} → $statusCode (${elapsedMs}ms)$excerpt',
  );
}

/// Log an unhandled exception before returning a failure.
void _logException(String tag, String method, Uri url, Object e) {
  debugPrint('[$tag] $method ${url.path} threw: $e');
}

class SignupResult {
  const SignupResult({
    required this.success,
    this.userId,
    this.token,
    this.bleUid,
    this.statusCode,
    this.error,
  });

  final bool success;
  final String? userId;
  final String? token;

  /// Server-confirmed 12-hex BLE UID the device should broadcast.
  final String? bleUid;
  final int? statusCode;
  final String? error;
}

/// Profile data returned by the victim-profile lookup endpoint.
class VictimProfile {
  const VictimProfile({
    this.userId,
    this.name,
    this.phone,
    this.language,
    this.contacts = const [],
    this.medical,
  });

  final String? userId;
  final String? name;
  final String? phone;
  final String? language;
  final List<VictimContact> contacts;
  final VictimMedical? medical;

  factory VictimProfile.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>? ?? {};
    final contactList =
        (json['contacts'] as List<dynamic>?)
            ?.map((c) => VictimContact.fromJson(c as Map<String, dynamic>))
            .toList() ??
        [];
    final med = json['medical'] as Map<String, dynamic>?;
    return VictimProfile(
      userId: user['id'] as String?,
      name: user['name'] as String?,
      phone: user['phone'] as String?,
      language: user['language'] as String?,
      contacts: contactList,
      medical: med != null ? VictimMedical.fromJson(med) : null,
    );
  }
}

class VictimContact {
  const VictimContact({this.name, this.phone, this.priority});
  final String? name;
  final String? phone;
  final int? priority;

  factory VictimContact.fromJson(Map<String, dynamic> json) => VictimContact(
    name: json['name'] as String?,
    phone: json['phone'] as String?,
    priority: json['priority'] as int?,
  );
}

class VictimMedical {
  const VictimMedical({this.bloodGroup, this.allergies, this.conditions});
  final String? bloodGroup;
  final String? allergies;
  final String? conditions;

  factory VictimMedical.fromJson(Map<String, dynamic> json) => VictimMedical(
    bloodGroup: json['bloodGroup'] as String?,
    allergies: json['allergies'] as String?,
    conditions: json['conditions'] as String?,
  );
}

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

class DisasterReportResult {
  const DisasterReportResult({
    required this.success,
    this.statusCode,
    this.error,
    this.reportId,
    this.verificationStatus,
    this.imageUrl,
  });

  final bool success;
  final int? statusCode;
  final String? error;
  final String? reportId;
  final String? verificationStatus;
  final String? imageUrl;
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
  // SOS — Victim Profile Lookup
  // -------------------------------------------------------------------------

  /// Look up a victim's full profile (name, contacts, medical) by BLE UID.
  ///
  /// Returns `null` if no registered user owns this UID, or on any failure.
  Future<VictimProfile?> lookupVictimProfile(String bleUidHex) async {
    final url = Uri.parse('$_baseUrl$kApiSosVictimProfile/$bleUidHex');
    debugPrint('[BackendService] → GET ${url.path}');
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .get(url, headers: _headers)
          .timeout(const Duration(seconds: 15));
      sw.stop();
      _logResponse(
        'BackendService',
        'GET',
        url,
        response.statusCode,
        sw.elapsedMilliseconds,
      );

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final profile = VictimProfile.fromJson(decoded);
        debugPrint(
          '[BackendService] Victim resolved: name=${profile.name} '
          'contacts=${profile.contacts.length} '
          'hasMedical=${profile.medical != null}',
        );
        return profile;
      }
      return null;
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'GET', url, e);
      return null;
    }
  }

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
          .timeout(const Duration(seconds: 8));
      sw.stop();
      _logResponse(
        'BackendService',
        'POST',
        url,
        response.statusCode,
        sw.elapsedMilliseconds,
        bodyExcerpt: response.body,
      );
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'POST', url, e);
      debugPrint(
        '[BackendService] ingestSos elapsed before error: ${sw.elapsedMilliseconds}ms',
      );
      return false;
    }
  }

  // -------------------------------------------------------------------------
  // Onboarding — Signup
  // -------------------------------------------------------------------------

  /// Register a new user. Sends the device's own BLE UID so the DB record
  /// matches what the device broadcasts over BLE.
  Future<SignupResult> signup({
    required String phone,
    required String bleUid,
    String? name,
    String language = 'en',
    List<Map<String, dynamic>>? emergencyContacts,
    Map<String, dynamic>? medicalProfile,
  }) async {
    final url = Uri.parse('$_baseUrl$kApiOnboardingSignup');
    final payload = <String, dynamic>{
      'phone': phone,
      'bleUid': bleUid,
      'language': language,
      if (name != null && name.isNotEmpty) 'name': name,
      if (emergencyContacts != null && emergencyContacts.isNotEmpty)
        'emergencyContacts': emergencyContacts,
      if (medicalProfile != null && medicalProfile.isNotEmpty)
        'medicalProfile': medicalProfile,
    };
    final body = jsonEncode(payload);
    debugPrint(
      '[BackendService] → POST ${url.path} | phone=$phone bleUid=$bleUid',
    );
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .post(url, headers: _headers, body: body)
          .timeout(const Duration(seconds: 35));
      sw.stop();
      _logResponse(
        'BackendService',
        'POST',
        url,
        response.statusCode,
        sw.elapsedMilliseconds,
        bodyExcerpt: response.statusCode >= 400 ? response.body : null,
      );

      if (response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final user = decoded['user'] as Map<String, dynamic>?;
        return SignupResult(
          success: true,
          statusCode: response.statusCode,
          userId: user?['id'] as String?,
          token: decoded['token'] as String?,
          bleUid: user?['bleUid'] as String?,
        );
      }

      String? msg;
      try {
        final d = jsonDecode(response.body);
        if (d is Map<String, dynamic>) {
          msg = (d['error'] as String?)?.trim();
        }
      } catch (_) {}
      return SignupResult(
        success: false,
        statusCode: response.statusCode,
        error: msg ?? 'Signup failed (${response.statusCode})',
      );
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'POST', url, e);
      return SignupResult(success: false, error: 'Network error: $e');
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
          .timeout(const Duration(seconds: 35));
      sw.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        _logResponse(
          'BackendService',
          'POST',
          url,
          response.statusCode,
          sw.elapsedMilliseconds,
        );
        return AadhaarQrSubmitResult(
          success: true,
          statusCode: response.statusCode,
        );
      }

      _logResponse(
        'BackendService',
        'POST',
        url,
        response.statusCode,
        sw.elapsedMilliseconds,
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
    debugPrint('[BackendService] → POST ${url.path} | sosId=$sosId');
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .post(url, headers: _headers, body: jsonEncode({'id': sosId}))
          .timeout(const Duration(seconds: 35));
      sw.stop();
      _logResponse(
        'BackendService',
        'POST',
        url,
        response.statusCode,
        sw.elapsedMilliseconds,
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
          .timeout(const Duration(seconds: 35));
      sw.stop();

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is List) {
          final events = decoded
              .whereType<Map<String, dynamic>>()
              .map((e) => SosEvent.fromJson(e))
              .toList();
          _logResponse(
            'BackendService',
            'GET',
            url,
            response.statusCode,
            sw.elapsedMilliseconds,
          );
          debugPrint(
            '[BackendService] fetchActiveEvents: ${events.length} event(s) received',
          );
          return events;
        }
      }
      _logResponse(
        'BackendService',
        'GET',
        url,
        response.statusCode,
        sw.elapsedMilliseconds,
        bodyExcerpt: response.body,
      );
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'GET', url, e);
    }
    return [];
  }

  // -------------------------------------------------------------------------
  // Disaster Reporting
  // -------------------------------------------------------------------------

  /// Submit a disaster report with an image (multipart upload).
  Future<DisasterReportResult> submitDisasterReport({
    required Uint8List imageBytes,
    required String filename,
    required double lat,
    required double lon,
    String? description,
  }) async {
    final uri = Uri.parse('$_baseUrl$kApiDisasterReport');
    debugPrint('[BackendService] → POST ${uri.path} | lat=$lat lon=$lon');
    final sw = Stopwatch()..start();

    try {
      final request = http.MultipartRequest('POST', uri);
      if (authToken != null) {
        request.headers['Authorization'] = 'Bearer $authToken';
      }
      request.fields['lat'] = lat.toString();
      request.fields['lon'] = lon.toString();
      if (description != null && description.trim().isNotEmpty) {
        request.fields['description'] = description.trim();
      }
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: filename,
      ));

      final streamed = await request.send().timeout(const Duration(seconds: 45));
      final response = await http.Response.fromStream(streamed);
      sw.stop();
      _logResponse('BackendService', 'POST', uri, response.statusCode, sw.elapsedMilliseconds);

      if (response.statusCode == 201 || response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final report = decoded['report'] as Map<String, dynamic>;
        return DisasterReportResult(
          success: true,
          statusCode: response.statusCode,
          reportId: report['id'] as String?,
          verificationStatus: report['verificationStatus'] as String?,
          imageUrl: report['imageUrl'] as String?,
        );
      }

      String? msg;
      try {
        final d = jsonDecode(response.body);
        if (d is Map<String, dynamic>) msg = d['error'] as String?;
      } catch (_) {}
      return DisasterReportResult(
        success: false,
        statusCode: response.statusCode,
        error: msg ?? 'Report submission failed (${response.statusCode})',
      );
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'POST', uri, e);
      return DisasterReportResult(success: false, error: 'Network error: $e');
    }
  }

  /// Fetch the paginated verified disaster feed.
  Future<List<DisasterReport>> fetchDisasterFeed({
    int page = 1,
    int limit = 20,
    String? category,
  }) async {
    final params = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (category != null) 'category': category,
    };
    final uri = Uri.parse('$_baseUrl$kApiDisasterFeed').replace(queryParameters: params);
    debugPrint('[BackendService] → GET ${uri.path}?${uri.query}');
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      sw.stop();
      _logResponse('BackendService', 'GET', uri, response.statusCode, sw.elapsedMilliseconds);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map<String, dynamic>) {
          final reports = (decoded['reports'] as List<dynamic>?)
              ?.map((e) => DisasterReport.fromJson(e as Map<String, dynamic>))
              .toList() ?? [];
          return reports;
        }
      }
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'GET', uri, e);
    }
    return [];
  }

  /// Fetch a single disaster report by ID.
  Future<DisasterReport?> fetchDisasterReport(String reportId) async {
    final uri = Uri.parse('$_baseUrl$kApiDisasterDetail/$reportId');
    debugPrint('[BackendService] → GET ${uri.path}');
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      sw.stop();
      _logResponse('BackendService', 'GET', uri, response.statusCode, sw.elapsedMilliseconds);

      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final report = decoded['report'] as Map<String, dynamic>;
        return DisasterReport.fromJson(report);
      }
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'GET', uri, e);
    }
    return null;
  }

  /// Fetch aggregated disaster stats.
  Future<DisasterStats?> fetchDisasterStats({String range = '24h'}) async {
    final uri = Uri.parse('$_baseUrl$kApiDisasterStats').replace(
      queryParameters: {'range': range},
    );
    debugPrint('[BackendService] → GET ${uri.path}?${uri.query}');
    final sw = Stopwatch()..start();
    try {
      final response = await _client
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 15));
      sw.stop();
      _logResponse('BackendService', 'GET', uri, response.statusCode, sw.elapsedMilliseconds);

      if (response.statusCode == 200) {
        return DisasterStats.fromJson(
          jsonDecode(response.body) as Map<String, dynamic>,
        );
      }
    } catch (e) {
      sw.stop();
      _logException('BackendService', 'GET', uri, e);
    }
    return null;
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
