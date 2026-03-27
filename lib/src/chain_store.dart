import 'dart:typed_data';

import 'logc.dart';
import 'block.dart';
import 'utils.dart';

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
  bool exists();
  bool empty();
  void delete();

  /// Return all stored lines (including any header line).
  List<String> readLines();

  /// Create the storage and write [content].  Throws if storage already exists.
  void writeAll(String content);

  /// Append [content] to existing storage.
  void append(String content);
}

class BlockHeaderStore {
  final ChainStore _backend;
  final bool verbose;

  BlockHeaderStore(this._backend, {this.verbose = false});

  bool exists() => _backend.exists();
  bool empty() => _backend.empty();
  void delete() => _backend.delete();

  List<BlockHeader> read() {
    if (!_backend.exists()) {
      throw StateError('Block headers storage does not exist');
    }
    final headers = <BlockHeader>[];
    for (final line in _backend.readLines()) {
      if (line.startsWith('height,timestamp,hash,header')) continue;
      final fields = line.split(',');
      if (fields.length == 4) {
        headers.add(BlockHeader.fromBytes(fields[3].toBytes()));
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

  void write(List<ChainEntry> chainEntries) {
    if (chainEntries.first.previous != null) {
      throw StateError(
        'First entry must be the genesis block when writing entire headers',
      );
    }
    final buf = StringBuffer()..writeln('height,timestamp,hash,header');
    for (final entry in chainEntries) {
      buf.writeln(_headerEntry(entry));
    }
    _backend.writeAll(buf.toString());
    if (verbose) _log.info('Block headers written');
  }

  void append(List<ChainEntry> chainEntries) {
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
    final lines = _backend.readLines();
    if (lines.isEmpty) throw StateError('Storage is empty, cannot append');
    final lastHeight = int.tryParse(lines.last.split(',')[0]);
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
    _backend.append(buf.toString());
    if (verbose) _log.info('Block headers appended');
  }
}

class BlockFilterHeaderStore {
  final ChainStore _backend;
  final bool verbose;

  BlockFilterHeaderStore(this._backend, {this.verbose = false});

  bool exists() => _backend.exists();
  bool empty() => _backend.empty();
  void delete() => _backend.delete();

  List<Uint8List> read() {
    if (!_backend.exists()) {
      throw StateError('Block filter headers storage does not exist');
    }
    final headers = <Uint8List>[];
    for (final line in _backend.readLines()) {
      if (line.startsWith('height,header')) continue;
      final fields = line.split(',');
      if (fields.length == 2) headers.add(fields[1].toBytes());
    }
    _log.info('Loaded ${headers.length} block filter headers');
    return headers;
  }

  String _headerEntry(BlockFilterHeaderEntry entry) =>
      '${entry.height.toString().padLeft(6, '0')},${entry.header.toHex()}';

  void write(List<BlockFilterHeaderEntry> entries) {
    if (entries.isEmpty) {
      if (verbose) _log.info('No block filter headers to write');
      return;
    }
    final buf = StringBuffer()..writeln('height,header');
    for (final entry in entries) {
      buf.writeln(_headerEntry(entry));
    }
    _backend.writeAll(buf.toString());
    if (verbose) _log.info('Block filter headers written');
  }

  void append(List<BlockFilterHeaderEntry> entries) {
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
    final lines = _backend.readLines();
    if (lines.isEmpty) throw StateError('Storage is empty, cannot append');
    final lastHeight = int.tryParse(lines.last.split(',')[0]);
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
    _backend.append(buf.toString());
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

  BlockFilterStore(this._backend, {this.verbose = false}) {
    _writeHead = _scanWriteHead();
  }

  /// Height of the last flushed filter, or null if nothing stored yet.
  int? get writeHead => _writeHead;

  /// Append a filter to the in-memory list.
  /// Skips entries already on disk or already in the list (duplicate guard).
  void add(BlockFilterEntry entry) {
    if (_writeHead != null && entry.height <= _writeHead!) return;
    if (entries.isNotEmpty && entry.height <= entries.last.height) return;
    entries.add(entry);
  }

  int? _scanWriteHead() {
    if (!_backend.exists() || _backend.empty()) return null;
    final lines = _backend.readLines();
    for (var i = lines.length - 1; i >= 0; i--) {
      final entry = _parseLine(lines[i]);
      if (entry != null) return entry.height;
    }
    return null;
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
  List<BlockFilterEntry> readFrom(int fromHeight) {
    if (!_backend.exists() || _backend.empty()) return [];
    return _backend
        .readLines()
        .map(_parseLine)
        .whereType<BlockFilterEntry>()
        .where((e) => e.height >= fromHeight)
        .toList();
  }

  /// Flush all entries above [writeHead] to the backend in a single write.
  /// Creates storage on first call; appends sequentially thereafter.
  void flush() {
    final toWrite = _writeHead == null
        ? entries
        : entries.where((e) => e.height > _writeHead!).toList();
    if (toWrite.isEmpty) return;

    final buf = StringBuffer();
    if (!_backend.exists()) {
      buf.write('height,blockHash,filterBytes\n');
      for (final e in toWrite) {
        buf.write('${_entryToLine(e)}\n');
      }
      _backend.writeAll(buf.toString());
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
      _backend.append(buf.toString());
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
  bool contains(Uint8List blockHash);
  void store(Block block);
  Block? read(Uint8List blockHash);
}
