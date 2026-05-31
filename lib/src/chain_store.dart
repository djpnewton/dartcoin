import 'dart:typed_data';

import 'logc.dart';
import 'block.dart';
import 'utils.dart';

export 'chain_store_factory_stub.dart'
    if (dart.library.io) 'chain_store_file.dart'
    if (dart.library.js_interop) 'chain_store_web.dart'
    show defaultChainStoreFactory, defaultBlockStoreFactory;

final _log = ColorLogger('ChainStore');

abstract class NodeLL<Self extends NodeLL<Self>> {
  Self? previous;
  int height;
  NodeLL({this.previous, required this.height});
}

class ChainEntry extends NodeLL<ChainEntry> {
  BlockHeader header;
  BigInt work;
  BigInt chainWork;
  int timeCreated = DateTime.now().millisecondsSinceEpoch;
  ChainEntry({
    required super.height,
    required this.header,
    required this.work,
    required this.chainWork,
    super.previous,
  });

  ChainEntry getAt(int targetHeight) {
    var current = this;
    while (current.height > targetHeight) {
      if (current.previous == null) {
        throw StateError(
          'No node found at height $targetHeight, reached genesis at height ${current.height}',
        );
      }
      current = current.previous!;
    }
    if (current.height != targetHeight) {
      throw StateError(
        'No node found at height $targetHeight, stopped at height ${current.height}',
      );
    }
    return current;
  }

  ChainEntry getAtHash(Uint8List targetHash) {
    var current = this;
    while (!listEquals(current.header.hash(), targetHash)) {
      if (current.previous == null) {
        throw StateError(
          'No node found with hash ${targetHash.toHex()}, reached genesis at height ${current.height}',
        );
      }
      current = current.previous!;
    }
    return current;
  }
}

class BlockFilterHeaderEntry extends NodeLL<BlockFilterHeaderEntry> {
  Uint8List header;
  BlockFilterHeaderEntry({
    required super.height,
    required this.header,
    super.previous,
  });
}

class BlockFilterEntry {
  final int height;
  final Uint8List blockHash;
  final Uint8List filterBytes;

  BlockFilterEntry({
    required this.height,
    required this.blockHash,
    required this.filterBytes,
  });
}

/// Abstract backend used by [BlockHeaderStore], [BlockFilterHeaderStore] and
/// [BlockFilterStore].  Implementations are not required to use the file system.
abstract class ChainStore {
  Future<void> init();
  Future<bool> exists();
  Future<bool> empty();
  Future<void> delete();

  /// Return all stored lines (including any header line).
  Future<List<String>> readLines();

  /// Return the last stored line, or null if storage is empty.
  ///
  /// Implementations should make this O(1) where possible
  /// so that append height-continuity checks do not require
  /// reading the entire store on every append.
  Future<String?> lastLine();

  /// Create the storage and write [content].  Throws if storage already exists.
  Future<void> writeAll(String content);

  /// Append [content] to existing storage.
  Future<void> append(String content);
}

class BlockHeaderStore {
  final ChainStore _backend;
  final bool verbose;

  BlockHeaderStore(this._backend, {this.verbose = false});

  Future<void> init() => _backend.init();
  Future<bool> exists() => _backend.exists();
  Future<bool> empty() => _backend.empty();
  Future<void> delete() => _backend.delete();

  Future<List<BlockHeader>> read() async {
    if (!await _backend.exists()) {
      throw StateError('Block headers storage does not exist');
    }
    final headers = <BlockHeader>[];
    for (final line in await _backend.readLines()) {
      if (line.startsWith('height,timestamp,hash,header')) continue;
      final fields = line.split(',');
      if (fields.length == 4) {
        // The stored `hash` field (display/big-endian hex) lets us prime the
        // header's cached hash, avoiding an expensive double-SHA-256 per header
        // when the height index is built on load.
        Uint8List? cachedHash;
        if (fields[2].length == 64) {
          cachedHash = fields[2].toBytes().reverse();
        }
        headers.add(
          BlockHeader.fromBytes(fields[3].toBytes(), cachedHash: cachedHash),
        );
      }
    }
    _log.info('Loaded ${headers.length} block headers');
    return headers;
  }

  String _headerEntry(ChainEntry entry) =>
      '${entry.height.toString().padLeft(6, '0')}'
      ',${DateTime.now().millisecondsSinceEpoch ~/ 1000}'
      ',${headerHashNice(entry.header.hash())}'
      ',${entry.header.toBytes().toHex()}';

  Future<void> write(List<ChainEntry> chainEntries) async {
    if (chainEntries.first.previous != null) {
      throw StateError(
        'First entry must be the genesis block when writing entire headers',
      );
    }
    final buf = StringBuffer()..writeln('height,timestamp,hash,header');
    for (final entry in chainEntries) {
      buf.writeln(_headerEntry(entry));
    }
    await _backend.writeAll(buf.toString());
    if (verbose) _log.info('Block headers written');
  }

  Future<void> append(List<ChainEntry> chainEntries) async {
    if (chainEntries.isEmpty) {
      if (verbose) _log.info('No new block headers to append');
      return;
    }
    if (chainEntries.first.previous == null) {
      throw StateError(
        'First entry must not be the genesis block when appending to headers',
      );
    }
    // Height-continuity check.
    final last = await _backend.lastLine();
    if (last == null) throw StateError('Storage is empty, cannot append');
    final lastHeight = int.tryParse(last.split(',')[0]);
    if (lastHeight == null) throw StateError('Invalid last height in storage');
    final expectedPrev = chainEntries.first.previous?.height;
    if (lastHeight != expectedPrev) {
      throw StateError(
        'Last stored height ($lastHeight) does not match '
        'first new entry predecessor ($expectedPrev)',
      );
    }
    final buf = StringBuffer();
    for (final entry in chainEntries) {
      buf.writeln(_headerEntry(entry));
    }
    await _backend.append(buf.toString());
    if (verbose) _log.info('Block headers appended');
  }
}

class BlockFilterHeaderStore {
  final ChainStore _backend;
  final bool verbose;

  BlockFilterHeaderStore(this._backend, {this.verbose = false});

  Future<void> init() => _backend.init();
  Future<bool> exists() => _backend.exists();
  Future<bool> empty() => _backend.empty();
  Future<void> delete() => _backend.delete();

  Future<List<Uint8List>> read() async {
    if (!await _backend.exists()) {
      throw StateError('Block filter headers storage does not exist');
    }
    final headers = <Uint8List>[];
    for (final line in await _backend.readLines()) {
      if (line.startsWith('height,header')) continue;
      final fields = line.split(',');
      if (fields.length == 2) headers.add(fields[1].toBytes());
    }
    _log.info('Loaded ${headers.length} block filter headers');
    return headers;
  }

  String _headerEntry(BlockFilterHeaderEntry entry) =>
      '${entry.height.toString().padLeft(6, '0')},${entry.header.toHex()}';

  Future<void> write(List<BlockFilterHeaderEntry> entries) async {
    if (entries.isEmpty) {
      if (verbose) _log.info('No block filter headers to write');
      return;
    }
    final buf = StringBuffer()..writeln('height,header');
    for (final entry in entries) {
      buf.writeln(_headerEntry(entry));
    }
    await _backend.writeAll(buf.toString());
    if (verbose) _log.info('Block filter headers written');
  }

  Future<void> append(List<BlockFilterHeaderEntry> entries) async {
    if (entries.isEmpty) {
      if (verbose) _log.info('No new block filter headers to append');
      return;
    }
    if (entries.first.previous == null) {
      throw StateError(
        'First entry must not be the genesis block when appending to filter headers',
      );
    }
    // Height-continuity check.
    final last = await _backend.lastLine();
    if (last == null) throw StateError('Storage is empty, cannot append');
    final lastHeight = int.tryParse(last.split(',')[0]);
    if (lastHeight == null) throw StateError('Invalid last height in storage');
    final expectedPrev = entries.first.previous?.height;
    if (lastHeight != expectedPrev) {
      throw StateError(
        'Last stored height ($lastHeight) does not match '
        'first new entry predecessor ($expectedPrev)',
      );
    }
    final buf = StringBuffer();
    for (final entry in entries) {
      buf.writeln(_headerEntry(entry));
    }
    await _backend.append(buf.toString());
    if (verbose) _log.info('Block filter headers appended');
  }
}

/// Stores raw BIP-158 block filters (GCS).
///
/// CSV format:  height,blockHash,filterBytes
/// Heights are stored in ascending sequential order starting from the first
/// recorded height (the wallet birthday block).
///
/// [writeHead] tracks the height of the last written entry (O(1) gap checks).
class BlockFilterStore {
  final ChainStore _backend;
  final bool verbose;
  final List<BlockFilterEntry> entries = [];
  int? _writeHead;
  bool _initialized = false;

  BlockFilterStore(this._backend, {this.verbose = false});

  /// Height of the last flushed filter, or null if nothing stored yet.
  int? get writeHead => _writeHead;

  Future<void> init() async {
    if (_initialized) return;
    await _backend.init();
    _writeHead = await _scanWriteHead();
    _initialized = true;
  }

  /// Append a filter to the in-memory list.
  /// Skips entries already on disk or already in the list (duplicate guard).
  void add(BlockFilterEntry entry) {
    if (_writeHead != null && entry.height <= _writeHead!) return;
    if (entries.isNotEmpty && entry.height <= entries.last.height) return;
    entries.add(entry);
  }

  Future<int?> _scanWriteHead() async {
    if (!await _backend.exists() || await _backend.empty()) return null;
    final last = await _backend.lastLine();
    return last == null ? null : _parseLine(last)?.height;
  }

  String _entryToLine(BlockFilterEntry e) =>
      '${e.height.toString().padLeft(7, '0')}'
      ',${e.blockHash.toHex()}'
      ',${e.filterBytes.toHex()}';

  BlockFilterEntry? _parseLine(String line) {
    if (line.startsWith('height,') || line.isEmpty) return null;
    final fields = line.split(',');
    if (fields.length != 3) return null;
    final height = int.tryParse(fields[0]);
    if (height == null) return null;
    return BlockFilterEntry(
      height: height,
      blockHash: fields[1].toBytes(),
      filterBytes: fields[2].toBytes(),
    );
  }

  /// Read all stored filters at or above [fromHeight].
  Future<List<BlockFilterEntry>> readFrom(int fromHeight) async {
    if (!await _backend.exists() || await _backend.empty()) return [];
    return (await _backend.readLines())
        .map(_parseLine)
        .whereType<BlockFilterEntry>()
        .where((e) => e.height >= fromHeight)
        .toList();
  }

  /// Flush all entries above [writeHead] to the backend in a single write.
  /// Creates storage on first call; appends sequentially thereafter.
  Future<void> flush() async {
    final toWrite = _writeHead == null
        ? entries
        : entries.where((e) => e.height > _writeHead!).toList();
    if (toWrite.isEmpty) return;

    final buf = StringBuffer();
    if (!await _backend.exists()) {
      buf.write('height,blockHash,filterBytes\n');
      for (final e in toWrite) {
        buf.write('${_entryToLine(e)}\n');
      }
      await _backend.writeAll(buf.toString());
    } else {
      final expected = _writeHead == null ? null : _writeHead! + 1;
      if (expected != null && toWrite.first.height != expected) {
        throw StateError(
          'BlockFilterStore.flush: expected height $expected, '
          'got ${toWrite.first.height} – non-sequential write rejected',
        );
      }
      for (final e in toWrite) {
        buf.write('${_entryToLine(e)}\n');
      }
      await _backend.append(buf.toString());
    }

    _writeHead = toWrite.last.height;
    if (verbose) {
      _log.info(
        'Block filters flushed: heights ${toWrite.first.height}–${toWrite.last.height}',
      );
    }
  }
}

/// Abstract store for full serialised blocks.
/// Implementations are not required to use the file system.
abstract class BlockStore {
  Future<void> init();
  Future<bool> contains(Uint8List blockHash);
  Future<void> store(Block block);
  Future<Block?> read(Uint8List blockHash);
}

/// Factory that creates a [ChainStore] for the given [name].
/// On native platforms [name] is a file path; on web it is an IDB store name.
typedef ChainStoreFactory = ChainStore Function(String name);

/// Factory that creates a [BlockStore] for the given [name].
/// On native platforms [name] is a directory path; on web it is an IDB store name.
typedef BlockStoreFactory = BlockStore Function(String name, {bool verbose});
