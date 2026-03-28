import 'dart:async';
import 'dart:convert';
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

bool _storeExists(IDBDatabase db, String name) =>
    db.objectStoreNames.contains(name);

/// Apparently you can only create object stores in the onupgradeneeded event,
/// so this function checks if the store exists and creates it if not
Future<IDBDatabase> openDatabase(
  String dbName, {
  int version = 1,
  List<String> objectStoreNames = const [],
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
      if (!_storeExists(db, storeName)) {
        db.createObjectStore(storeName);
      }
    }
  }).toJS;
  return c.future;
}

/// [ChainStore] backed by an IndexedDB object store.
///
/// The backing object store holds a single record:
///   key = `"rows"`, value = JSON-encoded `List<String>`.
///
/// Multiple [ChainStoreWeb] instances can share the same [IDBDatabase] by
/// using different [storeName] values
class ChainStoreWeb implements ChainStore {
  final IDBDatabase _db;

  /// The name of the IndexedDB object store this instance uses.
  final String storeName;

  ChainStoreWeb(this._db, this.storeName);

  Future<List<String>?> _readRaw() async {
    final tx = _db.transaction(storeName.toJS, 'readonly');
    final result = await _requestFuture(
      tx.objectStore(storeName).get('rows'.toJS),
    );
    if (result == null) return null;
    return List<String>.from(jsonDecode((result as JSString).toDart) as List);
  }

  Future<void> _writeRaw(List<String> lines) async {
    final tx = _db.transaction(storeName.toJS, 'readwrite');
    await _requestFuture(
      tx.objectStore(storeName).put(jsonEncode(lines).toJS, 'rows'.toJS),
    );
  }

  @override
  Future<void> init() async {
    if (!_storeExists(_db, storeName)) {
      throw StateError('ChainStoreWeb "$storeName" does not exist in database');
    }
  }

  @override
  Future<bool> exists() async => await _readRaw() != null;

  @override
  Future<bool> empty() async {
    final lines = await _readRaw();
    return lines == null || lines.isEmpty;
  }

  @override
  Future<void> delete() async {
    final tx = _db.transaction(storeName.toJS, 'readwrite');
    await _requestFuture(tx.objectStore(storeName).delete('rows'.toJS));
  }

  @override
  Future<List<String>> readLines() async => await _readRaw() ?? [];

  @override
  Future<void> writeAll(String content) async {
    if (await exists()) {
      throw StateError('ChainStoreWeb "$storeName" already contains data');
    }
    await _writeRaw(_splitLines(content));
  }

  @override
  Future<void> append(String content) async {
    final lines = await _readRaw() ?? [];
    lines.addAll(_splitLines(content));
    await _writeRaw(lines);
  }

  static List<String> _splitLines(String content) =>
      content.split('\n').where((l) => l.isNotEmpty).toList();
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
    final db = await openDatabase(_name, objectStoreNames: [_name]);
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
