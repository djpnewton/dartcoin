import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:universal_web/web.dart';

import 'block.dart';
import 'chain_store.dart';
import 'utils.dart';

Future<JSAny?> _requestFuture(IDBRequest req) {
  final c = Completer<JSAny?>();
  req.onsuccess = ((JSObject _) => c.complete(req.result)).toJS;
  req.onerror = ((JSObject _) => c.completeError(
    req.error?.message ?? 'IDB error',
  )).toJS;
  return c.future;
}

/// Completes when [tx] fires `complete`, or errors on `error`/`abort`.
Future<void> _txComplete(IDBTransaction tx) {
  final c = Completer<void>();
  tx.oncomplete = ((JSObject _) => c.complete()).toJS;
  tx.onerror = ((JSObject _) => c.completeError(
    tx.error?.message ?? 'IDB transaction error',
  )).toJS;
  tx.onabort = ((JSObject _) => c.completeError(
    'IDB transaction aborted',
  )).toJS;
  return c.future;
}

bool _storeExists(IDBDatabase db, String name) =>
    db.objectStoreNames.contains(name);

/// Apparently you can only create object stores in the onupgradeneeded event,
/// so this function checks if the store exists and creates it if not.
/// When [rebuildStoresOnUpgrade] is true every listed store is deleted and
/// re-created during an upgrade, which is used to migrate incompatible data.
Future<IDBDatabase> openDatabase(
  String dbName, {
  int version = 1,
  List<String> objectStoreNames = const [],
  bool rebuildStoresOnUpgrade = false,
}) async {
  final c = Completer<IDBDatabase>();
  final req = window.indexedDB.open(dbName, version);
  req.onsuccess = ((JSObject _) {
    final db = (req.result as IDBDatabase);
    c.complete(db);
  }).toJS;
  req.onerror = ((JSObject _) => c.completeError(
    req.error?.message ?? 'Failed to open database',
  )).toJS;
  req.onupgradeneeded = ((IDBVersionChangeEvent event) {
    final db = (event.target as IDBOpenDBRequest).result as IDBDatabase;
    for (final storeName in objectStoreNames) {
      if (_storeExists(db, storeName)) {
        if (rebuildStoresOnUpgrade) {
          db.deleteObjectStore(storeName);
        } else {
          continue;
        }
      }
      db.createObjectStore(storeName);
    }
  }).toJS;
  return c.future;
}

/// [ChainStore] backed by an IndexedDB object store.
///
/// Each CSV row is stored as a separate record, keyed by its 0-based row
/// index (an integer).  Row 0 is always the CSV header line; data rows start
/// at index 1.  This avoids the "read-the-whole-file-then-rewrite-it" cost of
/// the previous single-blob design: `append` only needs `count()` (O(1)) plus
/// individual `put` calls in a single transaction, and `readLines` uses
/// `getAll()` which IDB returns in key order.
///
/// Multiple [ChainStoreWeb] instances can share the same [IDBDatabase] by
/// using different [storeName] values.
class ChainStoreWeb implements ChainStore {
  final IDBDatabase _db;

  /// The name of the IndexedDB object store this instance uses.
  final String storeName;

  ChainStoreWeb(this._db, this.storeName);

  Future<int> _rowCount() async {
    final tx = _db.transaction(storeName.toJS, 'readonly');
    final result = await _requestFuture(tx.objectStore(storeName).count());
    return (result as JSNumber).toDartDouble.toInt();
  }

  /// Writes [lines] into a single readwrite transaction starting at [startKey].
  Future<void> _putLines(List<String> lines, {required int startKey}) async {
    if (lines.isEmpty) return;
    final tx = _db.transaction(storeName.toJS, 'readwrite');
    final store = tx.objectStore(storeName);
    for (var i = 0; i < lines.length; i++) {
      store.put(lines[i].toJS, (startKey + i).toJS);
    }
    await _txComplete(tx);
  }

  static List<String> _splitLines(String content) =>
      content.split('\n').where((l) => l.isNotEmpty).toList();

  @override
  Future<void> init() async {
    if (!_storeExists(_db, storeName)) {
      throw StateError('ChainStoreWeb "$storeName" does not exist in database');
    }
  }

  @override
  Future<bool> exists() async => await _rowCount() > 0;

  @override
  Future<bool> empty() async => await _rowCount() == 0;

  @override
  Future<void> delete() async {
    final tx = _db.transaction(storeName.toJS, 'readwrite');
    await _requestFuture(tx.objectStore(storeName).clear());
  }

  @override
  Future<List<String>> readLines() async {
    final tx = _db.transaction(storeName.toJS, 'readonly');
    final result = await _requestFuture(tx.objectStore(storeName).getAll());
    if (result == null) return [];
    return [for (final s in (result as JSArray<JSString>).toDart) s.toDart];
  }

  @override
  Future<void> writeAll(String content) async {
    if (await exists()) {
      throw StateError('ChainStoreWeb "$storeName" already contains data');
    }
    await _putLines(_splitLines(content), startKey: 0);
  }

  @override
  Future<void> append(String content) async {
    final lines = _splitLines(content);
    if (lines.isEmpty) return;
    final startKey = await _rowCount();
    await _putLines(lines, startKey: startKey);
  }
}

/// [BlockStore] backed by an IndexedDB object store.
///
/// Blocks are stored as hex-encoded byte strings, keyed by the block's
/// little-endian hash hex.
class BlockStoreWeb implements BlockStore {
  final IDBDatabase _db;

  final String _storeName;

  BlockStoreWeb(this._db, this._storeName);

  @override
  Future<void> init() async {
    if (!_storeExists(_db, _storeName)) {
      throw StateError('block store "$_storeName" does not exist in database');
    }
  }

  @override
  Future<bool> contains(Uint8List blockHash) async {
    final tx = _db.transaction(_storeName.toJS, 'readonly');
    final result = await _requestFuture(
      tx.objectStore(_storeName).getKey(blockHash.toHex().toJS),
    );
    return result != null;
  }

  @override
  Future<void> store(Block block) async {
    final hashHex = block.hash().toHex();
    if (await contains(block.hash())) return;
    final tx = _db.transaction(_storeName.toJS, 'readwrite');
    await _requestFuture(
      tx
          .objectStore(_storeName)
          .put(block.toBytes().toHex().toJS, hashHex.toJS),
    );
  }

  @override
  Future<Block?> read(Uint8List blockHash) async {
    final tx = _db.transaction(_storeName.toJS, 'readonly');
    final result = await _requestFuture(
      tx.objectStore(_storeName).get(blockHash.toHex().toJS),
    );
    if (result == null) return null;
    return Block.fromBytes(hexToBytes((result as JSString).toDart));
  }
}

/// [ChainStore] backed by its own IDB database, opened lazily in [init].
///
/// Both the database name and the single object-store name equal [_name],
/// so each logical chain-store lives in its own isolated IDB database.
class ChainStoreWebAuto implements ChainStore {
  final String _name;
  ChainStoreWeb? _inner;

  ChainStoreWebAuto(this._name);

  Future<ChainStoreWeb> _ensureInner() async {
    if (_inner != null) return _inner!;
    // Version 2 = per-row integer keys (version 1 used a single JSON blob).
    // rebuildStoresOnUpgrade wipes any v1 data on the first open after upgrade.
    final db = await openDatabase(
      _name,
      version: 2,
      objectStoreNames: [_name],
      rebuildStoresOnUpgrade: true,
    );
    _inner = ChainStoreWeb(db, _name);
    return _inner!;
  }

  @override
  Future<void> init() async => (await _ensureInner()).init();
  @override
  Future<bool> exists() async => (await _ensureInner()).exists();
  @override
  Future<bool> empty() async => (await _ensureInner()).empty();
  @override
  Future<void> delete() async => (await _ensureInner()).delete();
  @override
  Future<List<String>> readLines() async => (await _ensureInner()).readLines();
  @override
  Future<void> writeAll(String content) async =>
      (await _ensureInner()).writeAll(content);
  @override
  Future<void> append(String content) async =>
      (await _ensureInner()).append(content);
}

/// [BlockStore] backed by its own IDB database, opened lazily in [init].
class BlockStoreWebAuto implements BlockStore {
  final String _name;
  BlockStoreWeb? _inner;

  BlockStoreWebAuto(this._name);

  Future<BlockStoreWeb> _ensureInner() async {
    if (_inner != null) return _inner!;
    final db = await openDatabase(_name, objectStoreNames: [_name]);
    _inner = BlockStoreWeb(db, _name);
    return _inner!;
  }

  @override
  Future<void> init() async => (await _ensureInner()).init();
  @override
  Future<bool> contains(Uint8List blockHash) async =>
      (await _ensureInner()).contains(blockHash);
  @override
  Future<void> store(Block block) async => (await _ensureInner()).store(block);
  @override
  Future<Block?> read(Uint8List blockHash) async =>
      (await _ensureInner()).read(blockHash);
}

ChainStore _chainStoreWebFactory(String name) => ChainStoreWebAuto(name);

BlockStore _blockStoreWebFactory(String name, {bool verbose = false}) =>
    BlockStoreWebAuto(name);

/// The IDB-backed [ChainStoreFactory] for web platforms.
const ChainStoreFactory defaultChainStoreFactory = _chainStoreWebFactory;

/// The IDB-backed [BlockStoreFactory] for web platforms.
const BlockStoreFactory defaultBlockStoreFactory = _blockStoreWebFactory;
