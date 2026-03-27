import 'dart:typed_data';

import 'package:sqlite3/sqlite3.dart';

import 'package:dartcoin/dartcoin.dart';

/// [ChainStore] backed by a single SQLite table.
///
/// Each logical "line" (as written by [BlockHeaderStore], [BlockFilterHeaderStore]
/// or [BlockFilterStore]) becomes one row.  Insertion order is preserved via an
/// auto-increment primary key so [readLines] always returns rows in the order
/// they were written.
///
/// Multiple [ChainStoreSqlite] instances can share the same [Database] by using
/// different [tableName] values.
class ChainStoreSqlite implements ChainStore {
  final Database db;
  final String tableName;

  ChainStoreSqlite(this.db, this.tableName);

  void _ensureTable() {
    db.execute('''
      CREATE TABLE IF NOT EXISTS "$tableName" (
        id   INTEGER PRIMARY KEY AUTOINCREMENT,
        line TEXT NOT NULL
      )
    ''');
  }

  @override
  bool exists() {
    final result = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      [tableName],
    );
    return result.isNotEmpty;
  }

  @override
  bool empty() {
    if (!exists()) return true;
    final result = db.select('SELECT COUNT(*) AS c FROM "$tableName"');
    return (result.first['c'] as int) == 0;
  }

  @override
  void delete() {
    db.execute('DROP TABLE IF EXISTS "$tableName"');
  }

  @override
  List<String> readLines() {
    if (!exists()) return [];
    final rows = db.select('SELECT line FROM "$tableName" ORDER BY id');
    return rows.map((r) => r['line'] as String).toList();
  }

  @override
  void writeAll(String content) {
    if (exists()) {
      throw StateError('ChainStoreSqlite table "$tableName" already exists');
    }
    _ensureTable();
    final lines = content.split('\n');
    final stmt = db.prepare('INSERT INTO "$tableName" (line) VALUES (?)');
    try {
      db.execute('BEGIN');
      for (final line in lines) {
        // skip trailing empty lines produced by splitlines
        if (line.isNotEmpty) stmt.execute([line]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.close();
    }
  }

  @override
  void append(String content) {
    _ensureTable();
    final lines = content.split('\n');
    final stmt = db.prepare('INSERT INTO "$tableName" (line) VALUES (?)');
    try {
      db.execute('BEGIN');
      for (final line in lines) {
        if (line.isNotEmpty) stmt.execute([line]);
      }
      db.execute('COMMIT');
    } catch (_) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.close();
    }
  }
}

/// [BlockStore] backed by a SQLite table.
///
/// Blocks are stored as raw serialised bytes (BLOB), keyed by their
/// little-endian hash hex string.  A `last_accessed` timestamp (Unix ms) is
/// kept for cache-eviction purposes.
///
/// Multiple [BlockStoreSqlite] instances can share the same [Database] by using
/// different [tableName] values.
class BlockStoreSqlite implements BlockStore {
  final Database db;
  final String tableName;

  BlockStoreSqlite(this.db, this.tableName) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS "$tableName" (
        hash          TEXT PRIMARY KEY,
        bytes         BLOB NOT NULL,
        last_accessed INTEGER NOT NULL
      )
    ''');
  }

  @override
  bool contains(Uint8List blockHash) {
    final result = db.select('SELECT 1 FROM "$tableName" WHERE hash = ?', [
      blockHash.toHex(),
    ]);
    return result.isNotEmpty;
  }

  @override
  void store(Block block) {
    final hashHex = block.hash().toHex();
    db.execute(
      'INSERT OR IGNORE INTO "$tableName" (hash, bytes, last_accessed) VALUES (?, ?, ?)',
      [hashHex, block.toBytes(), DateTime.now().millisecondsSinceEpoch],
    );
  }

  @override
  Block? read(Uint8List blockHash) {
    final hashHex = blockHash.toHex();
    final rows = db.select('SELECT bytes FROM "$tableName" WHERE hash = ?', [
      hashHex,
    ]);
    if (rows.isEmpty) return null;
    final bytes = rows.first['bytes'] as Uint8List;
    db.execute('UPDATE "$tableName" SET last_accessed = ? WHERE hash = ?', [
      DateTime.now().millisecondsSinceEpoch,
      hashHex,
    ]);
    return Block.fromBytes(bytes);
  }
}
