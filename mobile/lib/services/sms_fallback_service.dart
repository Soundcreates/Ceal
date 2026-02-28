/// SMS Fallback Service — sends SOS details via SMS when Internet is
/// unavailable and BLE relay has not been acknowledged.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:aftermath/models/sos_event.dart';
import 'package:aftermath/models/responder.dart';

class SmsFallbackService {
  /// Platform channel for sending SMS on Android.
  static const _channel = MethodChannel('com.aftermath.sos/sms');

  /// Emergency contacts to notify.
  List<EmergencyContact> emergencyContacts = [];

  /// Whether SMS fallback is enabled by the user.
  bool enabled = true;

  // -------------------------------------------------------------------------
  // API
  // -------------------------------------------------------------------------

  /// Send an SMS to all configured emergency contacts with the SOS details.
  ///
  /// Returns the number of messages successfully dispatched.
  Future<int> sendSos(SosEvent event) async {
    if (!enabled) {
      debugPrint('[SmsFallbackService] SMS fallback is disabled.');
      return 0;
    }
    if (emergencyContacts.isEmpty) {
      debugPrint('[SmsFallbackService] No emergency contacts configured.');
      return 0;
    }

    final message = _formatMessage(event);
    int sent = 0;

    for (final contact in emergencyContacts) {
      final ok = await _sendSms(contact.phone, message);
      if (ok) sent++;
    }

    debugPrint('[SmsFallbackService] Sent $sent/${emergencyContacts.length} '
        'SMS for SOS ${event.id}.');
    return sent;
  }

  // -------------------------------------------------------------------------
  // Message formatting
  // -------------------------------------------------------------------------

  String _formatMessage(SosEvent event) {
    final lat = event.latitude.toStringAsFixed(5);
    final lon = event.longitude.toStringAsFixed(5);
    final mapsUrl = 'https://maps.google.com/?q=$lat,$lon';
    return 'EMERGENCY SOS from AfterMath!\n'
        'Location: $lat, $lon\n'
        '$mapsUrl\n'
        'Time: ${event.timestamp.toIso8601String()}\n'
        'ID: ${event.id}';
  }

  // -------------------------------------------------------------------------
  // Platform SMS
  // -------------------------------------------------------------------------

  Future<bool> _sendSms(String phoneNumber, String message) async {
    try {
      if (Platform.isAndroid) {
        return await _sendSmsAndroid(phoneNumber, message);
      } else if (Platform.isIOS) {
        // iOS cannot send SMS silently — we would need to open
        // MFMessageComposeViewController via a URL scheme.
        return _sendSmsIos(phoneNumber, message);
      }
      return false;
    } catch (e) {
      debugPrint('[SmsFallbackService] SMS send error: $e');
      return false;
    }
  }

  /// Android: use the SmsManager via platform channel.
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

  /// iOS: open the SMS compose sheet via URL scheme (requires user interaction).
  bool _sendSmsIos(String phone, String message) {
    // Note: Silently sending SMS is not possible on iOS.
    // The app should fall back to URLLauncher with sms: scheme.
    debugPrint(
      '[SmsFallbackService] iOS requires user interaction for SMS. '
      'Use url_launcher with sms:$phone?body=$message',
    );
    return false;
  }
}
