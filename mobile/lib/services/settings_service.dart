/// Settings Service — SQLite-backed persistence for user preferences.
///
/// Persists emergency contacts and SMS-fallback toggle so they survive
/// app restarts.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'package:aftermath/models/responder.dart';
import 'package:aftermath/models/sos_type.dart';

class SettingsService {
  Database? _db;

  static const String _dbName = 'aftermath_settings.db';
  static const String _table = 'settings';

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  Future<void> init() async {
    if (_db != null) return;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, _dbName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
          )
        ''');
      },
    );
    debugPrint('[SettingsService] Database initialised.');
  }

  // -------------------------------------------------------------------------
  // Generic key/value helpers
  // -------------------------------------------------------------------------

  Future<void> _set(String key, String value) async {
    final db = _db!;
    await db.insert(
      _table,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String?> _get(String key) async {
    final db = _db!;
    final rows = await db.query(
      _table,
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String;
  }

  // -------------------------------------------------------------------------
  // Emergency Contacts
  // -------------------------------------------------------------------------

  static const _contactsKey = 'emergency_contacts';

  /// Save emergency contacts.
  Future<void> saveContacts(List<EmergencyContact> contacts) async {
    final json = jsonEncode(contacts.map((c) => c.toJson()).toList());
    await _set(_contactsKey, json);
    debugPrint('[SettingsService] Saved ${contacts.length} contacts.');
  }

  /// Load previously saved emergency contacts.
  Future<List<EmergencyContact>> loadContacts() async {
    final raw = await _get(_contactsKey);
    if (raw == null) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => EmergencyContact.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[SettingsService] Failed to parse contacts: $e');
      return [];
    }
  }

  // -------------------------------------------------------------------------
  // SMS toggle
  // -------------------------------------------------------------------------

  static const _smsEnabledKey = 'sms_enabled';

  Future<void> setSmsEnabled(bool enabled) async {
    await _set(_smsEnabledKey, enabled ? '1' : '0');
  }

  Future<bool> isSmsEnabled() async {
    final raw = await _get(_smsEnabledKey);
    return raw == '1';
  }

  // -------------------------------------------------------------------------
  // Accessibility Button SOS Type
  // -------------------------------------------------------------------------

  static const _accessibilitySosTypeKey = 'accessibility_sos_type';

  /// MethodChannel to Android native SharedPreferences.
  static const _accessibilityChannel =
      MethodChannel('com.aftermath.sos/accessibility');

  /// Set the SOS type that fires when the Android Accessibility Button is
  /// pressed.  Persists both in SQLite (Dart state) and in Android
  /// SharedPreferences (so the native AccessibilityService can read it
  /// even when Flutter is not running).
  Future<void> setAccessibilitySosType(SosType type) async {
    final eventStr = 'sos_${type.name}'; // e.g. "sos_fire"
    await _set(_accessibilitySosTypeKey, eventStr);
    // Push to native Android SharedPreferences.
    try {
      await _accessibilityChannel.invokeMethod(
        'setAccessibilitySosType',
        {'sosType': eventStr},
      );
    } catch (e) {
      debugPrint(
        '[SettingsService] Failed to sync accessibility SOS type to native: $e',
      );
    }
    debugPrint('[SettingsService] Accessibility SOS type set to: $eventStr');
  }

  /// Load the currently configured accessibility-button SOS type.
  Future<SosType> getAccessibilitySosType() async {
    // Prefer the native value (source of truth for the AccessibilityService).
    try {
      final native = await _accessibilityChannel
          .invokeMethod<String>('getAccessibilitySosType');
      if (native != null && native.isNotEmpty) {
        return SosType.fromEventString(native);
      }
    } catch (e) {
      debugPrint(
        '[SettingsService] Failed to read native accessibility SOS type: $e',
      );
    }
    // Fallback: read from local SQLite.
    final raw = await _get(_accessibilitySosTypeKey);
    if (raw != null) return SosType.fromEventString(raw);
    return SosType.general;
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  Future<void> dispose() async {
    await _db?.close();
    _db = null;
  }
}
