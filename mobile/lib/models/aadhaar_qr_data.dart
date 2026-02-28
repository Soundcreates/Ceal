/// Aadhaar QR payload model and XML parser.
library;

import 'package:xml/xml.dart' as x;

class AadhaarQrData {
  const AadhaarQrData({
    required this.rawXml,
    this.name,
    this.gender,
    this.dob,
    this.yob,
    this.state,
    this.district,
    this.pincode,
  });

  final String rawXml;
  final String? name;
  final String? gender;
  final String? dob;
  final String? yob;
  final String? state;
  final String? district;
  final String? pincode;

  bool get ageAbove18 {
    final now = DateTime.now().toUtc();
    if (dob != null) {
      final parsedDob = _parseDob(dob!);
      if (parsedDob != null) {
        final eighteenth = DateTime.utc(
          parsedDob.year + 18,
          parsedDob.month,
          parsedDob.day,
        );
        return !eighteenth.isAfter(now);
      }
    }
    if (yob != null && RegExp(r'^\d{4}$').hasMatch(yob!)) {
      return now.year - int.parse(yob!) >= 18;
    }
    return false;
  }

  static AadhaarQrData fromQrPayload(String rawPayload) {
    final xmlText = _extractXml(rawPayload);
    final doc = x.XmlDocument.parse(xmlText);

    x.XmlElement? node;
    for (final el in doc.findAllElements('PrintLetterBarcodeData')) {
      node = el;
      break;
    }
    node ??= doc.rootElement.name.local == 'PrintLetterBarcodeData'
        ? doc.rootElement
        : null;

    if (node == null) {
      throw const FormatException(
        'Aadhaar QR XML must contain PrintLetterBarcodeData',
      );
    }

    String? attr(String key) {
      final val = node!.getAttribute(key);
      if (val == null) return null;
      final t = val.trim();
      return t.isEmpty ? null : t;
    }

    return AadhaarQrData(
      rawXml: xmlText,
      name: attr('name'),
      gender: attr('gender'),
      dob: attr('dob'),
      yob: attr('yob'),
      state: attr('state'),
      district: attr('dist'),
      pincode: attr('pc'),
    );
  }

  static DateTime? _parseDob(String dob) {
    final dmy = RegExp(r'^(\d{2})[-/](\d{2})[-/](\d{4})$').firstMatch(dob);
    if (dmy != null) {
      return DateTime.tryParse(
        '${dmy.group(3)}-${dmy.group(2)}-${dmy.group(1)}',
      )?.toUtc();
    }
    final ymd = RegExp(r'^(\d{4})[-/](\d{2})[-/](\d{2})$').firstMatch(dob);
    if (ymd != null) {
      return DateTime.tryParse(
        '${ymd.group(1)}-${ymd.group(2)}-${ymd.group(3)}',
      )?.toUtc();
    }
    return null;
  }

  static String _extractXml(String payload) {
    final trimmed = payload.trim();
    if (trimmed.startsWith('<')) return trimmed;

    try {
      final decoded = Uri.decodeComponent(trimmed);
      if (decoded.contains('<') && decoded.contains('>')) {
        return decoded;
      }
    } catch (_) {
      // Fall through to substring extraction.
    }

    final start = trimmed.indexOf('<');
    final end = trimmed.lastIndexOf('>');
    if (start >= 0 && end > start) {
      return trimmed.substring(start, end + 1);
    }

    throw const FormatException('QR payload did not contain valid XML');
  }

  
}
