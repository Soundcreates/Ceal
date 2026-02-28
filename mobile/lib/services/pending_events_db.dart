/// Persistent pending-events queue for offline-first SOS relay (PoC mode).
///
/// Stores SOS events locally with tracking flags for backend upload and SMS
/// delivery status. Events are drained when connectivity returns.
library;

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

const String _dbName = 'aftermath_pending_events.db';
const String _table = 'pending_events';

class PendingEvent {
  PendingEvent({
    required this.id,
    required this.uid,
    required this.flags,
    required this.sequence,
    required this.receiverLat,
    required this.receiverLon,
    required this.rssi,
    required this.timestamp,
    this.relayHops = 0,
    this.sentToBackend = false,
    this.smsSent = false,
    this.lastAttemptAt,
  });

  final String id;
  final String uid;
  final int flags;
  final int sequence;
  final double receiverLat;
  final double receiverLon;
  final int rssi;
  final int timestamp; // millis since epoch
  int relayHops;
  bool sentToBackend;
  bool smsSent;
  int? lastAttemptAt;

  Map<String, dynamic> toRow() => {
        'id': id,
        'uid': uid,
        'flags': flags,
        'sequence': sequence,
        'receiver_lat': receiverLat,
        'receiver_lon': receiverLon,
        'rssi': rssi,
        'timestamp': timestamp,
        'relay_hops': relayHops,
        'sent_to_backend': sentToBackend ? 1 : 0,
        'sms_sent': smsSent ? 1 : 0,
        'last_attempt_at': lastAttemptAt,
      };

  factory PendingEvent.fromRow(Map<String, dynamic> row) => PendingEvent(
        id: row['id'] as String,
        uid: row['uid'] as String,
        flags: row['flags'] as int,
        sequence: row['sequence'] as int,
        receiverLat: (row['receiver_lat'] as num).toDouble(),
        receiverLon: (row['receiver_lon'] as num).toDouble(),
        rssi: row['rssi'] as int,
        timestamp: row['timestamp'] as int,
        relayHops: (row['relay_hops'] as int?) ?? 0,
        sentToBackend: (row['sent_to_backend'] as int) == 1,
        smsSent: (row['sms_sent'] as int) == 1,
        lastAttemptAt: row['last_attempt_at'] as int?,
      );
}

class PendingEventsDb {
  Database? _db;
  Timer? _purgeTimer;

  // ---------------------------------------------------------------------------
  // Init
  // ---------------------------------------------------------------------------

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, _dbName),
      version: 2,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_table (
            id TEXT PRIMARY KEY,
            uid TEXT NOT NULL,
            flags INTEGER NOT NULL,
            sequence INTEGER NOT NULL,
            receiver_lat REAL NOT NULL DEFAULT 0.0,
            receiver_lon REAL NOT NULL DEFAULT 0.0,
            rssi INTEGER NOT NULL DEFAULT 0,
            timestamp INTEGER NOT NULL,
            relay_hops INTEGER NOT NULL DEFAULT 0,
            sent_to_backend INTEGER NOT NULL DEFAULT 0,
            sms_sent INTEGER NOT NULL DEFAULT 0,
            last_attempt_at INTEGER
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_pending_backend ON $_table (sent_to_backend)',
        );
        await db.execute(
          'CREATE INDEX idx_pending_sms ON $_table (sms_sent)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            'ALTER TABLE $_table ADD COLUMN relay_hops INTEGER NOT NULL DEFAULT 0',
          );
        }
      },
    );

    _purgeTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) => purgeOld(),
    );

    debugPrint('[PendingEventsDb] Database initialised.');
    return _db!;
  }

  // ---------------------------------------------------------------------------
  // Insert
  // ---------------------------------------------------------------------------

  /// Insert a new pending event. Ignores duplicates (by id).
  Future<void> insert(PendingEvent event) async {
    final db = await _getDb();
    await db.insert(_table, event.toRow(),
        conflictAlgorithm: ConflictAlgorithm.ignore);
    debugPrint('[PendingEventsDb] Inserted ${event.id}');
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Events not yet uploaded to backend.
  Future<List<PendingEvent>> pendingBackendEvents() async {
    final db = await _getDb();
    final rows = await db.query(
      _table,
      where: 'sent_to_backend = 0',
      orderBy: 'timestamp ASC',
    );
    return rows.map(PendingEvent.fromRow).toList();
  }

  /// Events not yet SMS'd.
  Future<List<PendingEvent>> pendingSmsEvents() async {
    final db = await _getDb();
    final rows = await db.query(
      _table,
      where: 'sms_sent = 0',
      orderBy: 'timestamp ASC',
    );
    return rows.map(PendingEvent.fromRow).toList();
  }

  // ---------------------------------------------------------------------------
  // Update flags
  // ---------------------------------------------------------------------------

  Future<void> markSentToBackend(String id) async {
    final db = await _getDb();
    await db.update(
      _table,
      {'sent_to_backend': 1, 'last_attempt_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> markSmsSent(String id) async {
    final db = await _getDb();
    await db.update(
      _table,
      {'sms_sent': 1, 'last_attempt_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateLastAttempt(String id) async {
    final db = await _getDb();
    await db.update(
      _table,
      {'last_attempt_at': DateTime.now().millisecondsSinceEpoch},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ---------------------------------------------------------------------------
  // Purge
  // ---------------------------------------------------------------------------

  /// Remove events older than 24 hours.
  Future<int> purgeOld() async {
    final db = await _getDb();
    final cutoff =
        DateTime.now().subtract(const Duration(hours: 24)).millisecondsSinceEpoch;
    final count = await db.delete(
      _table,
      where: 'timestamp < ?',
      whereArgs: [cutoff],
    );
    if (count > 0) debugPrint('[PendingEventsDb] Purged $count old events.');
    return count;
  }

  // ---------------------------------------------------------------------------
  // Stats
  // ---------------------------------------------------------------------------

  Future<int> pendingCount() async {
    final db = await _getDb();
    final result = await db.rawQuery(
      'SELECT COUNT(*) as c FROM $_table WHERE sent_to_backend = 0',
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Dispose
  // ---------------------------------------------------------------------------

  Future<void> dispose() async {
    _purgeTimer?.cancel();
    _purgeTimer = null;
    await _db?.close();
    _db = null;
  }
}
