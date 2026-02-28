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

  Future<int> sendSos(SosEvent event) async {
    if (!enabled || emergencyContacts.isEmpty) return 0;

    final message = _formatMessage(event);
    int sent = 0;

    for (final contact in emergencyContacts) {
      if (await _sendSms(contact.phone, message)) {
        sent++;
      }
    }

    return sent;
  }

  String _formatMessage(SosEvent event) {
    final loc = event.receiverLocation;
    final locStr = loc != null
        ? '${loc.lat.toStringAsFixed(5)}, ${loc.lon.toStringAsFixed(5)}'
        : 'Unknown';
    final mapsUrl = loc != null
        ? 'https://maps.google.com/?q=${loc.lat},${loc.lon}'
        : '';

    return 'EMERGENCY SOS from AfterMath!\n'
        'Approx location: $locStr\n'
        '${mapsUrl.isNotEmpty ? '$mapsUrl\n' : ''}'
        'Time: ${event.timestamp.toIso8601String()}\n'
        'ID: ${event.id}';
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
