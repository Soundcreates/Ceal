/// SMS fallback service.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:aftermath/models/responder.dart';
import 'package:aftermath/models/sos_event.dart';

class SmsFallbackService {
  static const _channel = MethodChannel('com.aftermath.sos/sms');

  List<EmergencyContact> emergencyContacts = [];
  bool enabled = true;

  /// Send SOS SMS to all [emergencyContacts].
  ///
  /// [victimInfo] — optional pre-formatted victim details (name, blood group,
  /// allergies, conditions) to prepend to the message body.
  Future<int> sendSos(SosEvent event, {String? victimInfo}) async {
    if (!enabled || emergencyContacts.isEmpty) return 0;

    final message = _formatMessage(event, victimInfo: victimInfo);
    int sent = 0;

    for (final contact in emergencyContacts) {
      if (await _sendSms(contact.phone, message)) {
        sent++;
      }
    }

    return sent;
  }

  String _formatMessage(SosEvent event, {String? victimInfo}) {
    final loc = event.receiverLocation;
    final locStr = loc != null
        ? '${loc.lat.toStringAsFixed(5)}, ${loc.lon.toStringAsFixed(5)}'
        : 'Unknown';
    final mapsUrl = loc != null
        ? 'https://maps.google.com/?q=${loc.lat},${loc.lon}'
        : '';

    final buf = StringBuffer();
    buf.writeln('EMERGENCY SOS — AfterMath');
    if (victimInfo != null && victimInfo.isNotEmpty) {
      buf.writeln(victimInfo);
    }
    buf.writeln('Relayer location: $locStr');
    if (mapsUrl.isNotEmpty) buf.writeln(mapsUrl);
    buf.writeln('Time: ${event.timestamp.toIso8601String()}');
    buf.write('ID: ${event.id}');
    return buf.toString();
  }

  Future<bool> _sendSms(String phoneNumber, String message) async {
    try {
      if (Platform.isAndroid) {
        return await _sendSmsAndroid(phoneNumber, message);
      }
      if (Platform.isIOS) {
        return _sendSmsIos(phoneNumber, message);
      }
      return false;
    } catch (e) {
      debugPrint('[SmsFallbackService] SMS send error: $e');
      return false;
    }
  }

  Future<bool> _sendSmsAndroid(String phone, String message) async {
    try {
      final result = await _channel.invokeMethod<bool>('sendSms', {
        'phone': phone,
        'message': message,
      });
      return result ?? false;
    } on PlatformException catch (e) {
      debugPrint('[SmsFallbackService] Android SMS error: ${e.message}');
      return false;
    }
  }

  bool _sendSmsIos(String phone, String message) {
    debugPrint(
      '[SmsFallbackService] iOS requires user interaction for SMS. '
      'Use url_launcher with sms:$phone?body=$message',
    );
    return false;
  }
}
