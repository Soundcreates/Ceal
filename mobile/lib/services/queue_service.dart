/// Queue Service — local SQLite store-and-forward queue for SOS events.
///
/// Events are persisted locally so they survive app restarts and can be
/// uploaded once connectivity is restored.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

import 'package:aftermath/core/constants.dart';
import 'package:aftermath/models/sos_event.dart';

class QueueService {
  Database? _db;
  Timer? _purgeTimer;

  // -------------------------------------------------------------------------
  // Initialisation
  // -------------------------------------------------------------------------

  Future<Database> _getDb() async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    _db = await openDatabase(
      p.join(dbPath, kQueueDbName),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $kQueueTable (
            id TEXT PRIMARY KEY,
            payload TEXT NOT NULL,
            uploaded INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
      },
    );

    // Start periodic expired-event purge.
    _purgeTimer ??= Timer.periodic(
      const Duration(minutes: 2),
      (_) => purgeExpired(),
    );

    return _db!;
  }

  // -------------------------------------------------------------------------
  // Enqueue / Dequeue
  // -------------------------------------------------------------------------

  /// Persist an SOS event for later upload / relay.
  Future<void> enqueue(SosEvent event) async {
    final db = await _getDb();
    await db.insert(
      kQueueTable,
      {
        'id': event.id,
        'payload': jsonEncode(event.toJson()),
        'uploaded': 0,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    debugPrint('[QueueService] Enqueued ${event.id}.');
  }

  /// Mark an event as successfully uploaded.
  Future<void> markUploaded(String sosId) async {
    final db = await _getDb();
    await db.update(
      kQueueTable,
      {'uploaded': 1},
      where: 'id = ?',
      whereArgs: [sosId],
    );
  }

  /// Get all events that have not yet been uploaded.
  Future<List<SosEvent>> pendingEvents() async {
    final db = await _getDb();
    final rows = await db.query(
      kQueueTable,
      where: 'uploaded = 0',
      orderBy: 'created_at ASC',
    );
    return rows
        .map((r) =>
            SosEvent.fromJson(jsonDecode(r['payload'] as String) as Map<String, dynamic>))
        .toList();
  }

  /// Remove events older than [kPacketMaxAge].
  Future<int> purgeExpired() async {
    final db = await _getDb();
    final cutoff = DateTime.now()
        .toUtc()
        .subtract(kPacketMaxAge)
        .toIso8601String();
    final count = await db.delete(
      kQueueTable,
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
    if (count > 0) {
      debugPrint('[QueueService] Purged $count expired events.');
    }
    return count;
  }

  /// Delete a specific event by ID.
  Future<void> delete(String sosId) async {
    final db = await _getDb();
    await db.delete(kQueueTable, where: 'id = ?', whereArgs: [sosId]);
    debugPrint('[QueueService] Deleted $sosId.');
  }

  /// Total number of events in the queue (uploaded + pending).
  Future<int> count() async {
    final db = await _getDb();
    final result =
        await db.rawQuery('SELECT COUNT(*) as c FROM $kQueueTable');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // -------------------------------------------------------------------------
  // Dispose
  // -------------------------------------------------------------------------

  Future<void> dispose() async {
    _purgeTimer?.cancel();
    _purgeTimer = null;
    await _db?.close();
    _db = null;
  }
}
