/// SMS fallback service.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
    buf.writeln('EMERGENCY SOS — CEAL');
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
      if (result == true) {
        return true;
      }
      debugPrint('[SmsFallbackService] Direct Android SMS returned false; opening composer fallback.');
      return _openSmsComposer(phone, message);
    } on PlatformException catch (e) {
      debugPrint('[SmsFallbackService] Android SMS error: ${e.message}');
      return _openSmsComposer(phone, message);
    }
  }

  Future<bool> _sendSmsIos(String phone, String message) {
    return _openSmsComposer(phone, message);
  }

  Future<bool> _openSmsComposer(String phone, String message) async {
    final uri = Uri(
      scheme: 'sms',
      path: phone,
      queryParameters: <String, String>{'body': message},
    );

    if (!await canLaunchUrl(uri)) {
      debugPrint('[SmsFallbackService] Cannot launch SMS composer for $phone');
      return false;
    }

    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      debugPrint('[SmsFallbackService] Failed to launch SMS composer for $phone');
    }
    return launched;
  }
}
