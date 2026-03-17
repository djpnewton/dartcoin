import 'dart:io';
import 'dart:typed_data';

import 'logc.dart';
import 'block.dart';
import 'utils.dart';

final _log = ColorLogger('ChainStore');

abstract class Node<Self extends Node<Self>> {
  Self? previous;
  int height;
  Node({this.previous, required this.height});
}

class ChainEntry extends Node<ChainEntry> {
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

class BlockFilterHeaderEntry extends Node<BlockFilterHeaderEntry> {
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

abstract class ChainStore {
  final String _filePath;
  final bool verbose;

  ChainStore(this._filePath, {this.verbose = false});

  String get filePath => _filePath;

  bool exists() {
    return File(_filePath).existsSync();
  }

  bool empty() {
    return !exists() || File(_filePath).lengthSync() == 0;
  }

  void delete() {
    if (exists()) {
      File(_filePath).deleteSync();
    }
  }

  void _appendDataWithHeightCheck(String data, int? firstHeightInNewEntries) {
    final file = File(_filePath);
    if (!file.existsSync()) {
      throw StateError('file does not exist: $_filePath');
    }
    // check the last height in the file
    final lines = file.readAsLinesSync();
    if (lines.isEmpty) {
      throw StateError('file is empty, cannot append new entries');
    }
    final lastHeight = int.tryParse(lines.last.split(',')[0]);
    if (lastHeight == null) {
      throw StateError('Invalid last height in file');
    }
    if (lastHeight != firstHeightInNewEntries) {
      throw StateError(
        'Last height in file ($lastHeight) does not match first height in new entries ($firstHeightInNewEntries)',
      );
    }
    // write new entries to the file
    file.writeAsStringSync(data, mode: FileMode.append);
  }
}

class BlockHeaderStore extends ChainStore {
  BlockHeaderStore(super.filePath);

  List<BlockHeader> read() {
    final headersFile = File(_filePath);
    if (!headersFile.existsSync()) {
      throw StateError('Block headers file does not exist: $_filePath');
    }
    // read the headers CSV line by line
    final headers = <BlockHeader>[];
    headersFile.readAsLinesSync().forEach((line) {
      // skip header line
      if (line.startsWith('height,timestamp,hash,header')) {
        return;
      }
      final fields = line.split(',');
      if (fields.length == 4) {
        //final height = int.parse(fields[0]);
        //final timestamp = int.parse(fields[1]);
        //final hash = Uint8List.fromList(fields[2].toBytes());
        final header = BlockHeader.fromBytes(fields[3].toBytes());
        headers.add(header);
      }
    });
    _log.info('Loaded ${headers.length} block headers from file');
    return headers;
  }

  String _headerFileEntry(ChainEntry entry) {
    return '${entry.height.toString().padLeft(6, '0')},${DateTime.now().millisecondsSinceEpoch ~/ 1000},${headerHashNice(entry.header.hash())},${entry.header.toBytes().toHex()}';
  }

  void write(List<ChainEntry> chainEntries) {
    if (chainEntries.first.previous != null) {
      throw StateError(
        'First entry must be the genesis block when writing entire headers file',
      );
    }
    // convert block headers to CSV format
    final csvData = StringBuffer();
    csvData.writeln('height,timestamp,hash,header');
    for (final entry in chainEntries) {
      csvData.writeln(_headerFileEntry(entry));
    }
    // write to file
    final headersFile = File(_filePath);
    if (headersFile.existsSync()) {
      throw StateError('Block headers file already exists: $_filePath.');
    }
    headersFile.createSync(recursive: true);
    headersFile.writeAsStringSync(csvData.toString());
    if (verbose) {
      _log.info('Block headers written to file: $_filePath');
    }
  }

  void append(List<ChainEntry> chainEntries) {
    if (chainEntries.isEmpty) {
      if (verbose) {
        _log.info('No new block headers to append to file');
      }
      return;
    }
    if (chainEntries.first.previous == null) {
      throw StateError(
        'First entry should not be the genesis block when appending to headers file',
      );
    }
    // convert block headers to CSV format
    final csvData = StringBuffer();
    for (final entry in chainEntries) {
      csvData.writeln(_headerFileEntry(entry));
    }
    // append to file
    _appendDataWithHeightCheck(
      csvData.toString(),
      chainEntries.first.previous?.height,
    );
    if (verbose) {
      _log.info('Block headers appended to file: $_filePath');
    }
  }
}

class BlockFilterHeaderStore extends ChainStore {
  BlockFilterHeaderStore(super.filePath);

  List<Uint8List> read() {
    final headersFile = File(_filePath);
    if (!headersFile.existsSync()) {
      throw StateError('Block filter headers file does not exist: $_filePath');
    }
    // read the headers CSV line by line
    final headers = <Uint8List>[];
    headersFile.readAsLinesSync().forEach((line) {
      // skip header line
      if (line.startsWith('height,header')) {
        return;
      }
      final fields = line.split(',');
      if (fields.length == 2) {
        //final height = int.parse(fields[0]);
        final header = fields[1].toBytes();
        headers.add(header);
      }
    });
    _log.info('Loaded ${headers.length} block filter headers from file');
    return headers;
  }

  String _headerFileEntry(BlockFilterHeaderEntry entry) {
    return '${entry.height.toString().padLeft(6, '0')},${entry.header.toHex()}';
  }

  void write(List<BlockFilterHeaderEntry> entries) {
    if (entries.isEmpty) {
      if (verbose) {
        _log.info('No block filter headers to write to file');
      }
      return;
    }
    // convert block filter headers to CSV format
    final csvData = StringBuffer();
    csvData.writeln('height,header');
    for (final entry in entries) {
      csvData.writeln(_headerFileEntry(entry));
    }
    // write to file
    final headersFile = File(_filePath);
    if (headersFile.existsSync()) {
      throw StateError('Block filter headers file already exists: $_filePath.');
    }
    headersFile.createSync(recursive: true);
    headersFile.writeAsStringSync(csvData.toString());
    if (verbose) {
      _log.info('Block filter headers written to file: $_filePath');
    }
  }

  void append(List<BlockFilterHeaderEntry> entries) {
    if (entries.isEmpty) {
      if (verbose) {
        _log.info('No new block filter headers to append to file');
      }
      return;
    }
    if (entries.first.previous == null) {
      throw StateError(
        'First entry should not be the genesis block when appending to headers file',
      );
    }
    // convert block filter headers to CSV format
    final csvData = StringBuffer();
    for (final entry in entries) {
      csvData.writeln(_headerFileEntry(entry));
    }
    // append to file
    _appendDataWithHeightCheck(
      csvData.toString(),
      entries.first.previous?.height,
    );
    if (verbose) {
      _log.info('Block filter headers appended to file: $_filePath');
    }
  }
}

/// Stores raw BIP-158 block filters (GCS) on disk.
///
/// CSV format:  height,blockHash,filterBytes
/// Heights are stored in ascending sequential order starting from the first
/// recorded height (the wallet birthday block).
///
/// [writeHead] tracks the height of the last written entry (O(1) gap checks).
class BlockFilterStore extends ChainStore {
  final List<BlockFilterEntry> entries = [];
  int? _writeHead;

  BlockFilterStore(super.filePath) {
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
    if (!exists() || empty()) return null;
    final lines = File(_filePath).readAsLinesSync();
    for (var i = lines.length - 1; i >= 0; i--) {
      final entry = _parseLine(lines[i]);
      if (entry != null) return entry.height;
    }
    return null;
  }

  String _entryToLine(BlockFilterEntry e) =>
      '${e.height.toString().padLeft(7, '0')},${e.blockHash.toHex()},${e.filterBytes.toHex()}';

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
    if (!exists() || empty()) return [];
    final result = <BlockFilterEntry>[];
    for (final line in File(_filePath).readAsLinesSync()) {
      final entry = _parseLine(line);
      if (entry != null && entry.height >= fromHeight) {
        result.add(entry);
      }
    }
    return result;
  }

  /// Flush all entries above [writeHead] to disk in a single syscall.
  /// Creates the file on first call; appends sequentially thereafter.
  void flush() {
    final toWrite = _writeHead == null
        ? entries
        : entries.where((e) => e.height > _writeHead!).toList();
    if (toWrite.isEmpty) return;
    final file = File(_filePath);
    final buf = StringBuffer();
    if (!file.existsSync()) {
      file.createSync(recursive: true);
      buf.write('height,blockHash,filterBytes\n');
      for (final e in toWrite) buf.write('${_entryToLine(e)}\n');
      file.writeAsStringSync(buf.toString());
      _writeHead = toWrite.last.height;
      if (verbose) {
        _log.info(
          'Block filter file created: $_filePath '
          '(heights ${toWrite.first.height}-${toWrite.last.height})',
        );
      }
      return;
    }
    final expected = _writeHead == null ? null : _writeHead! + 1;
    if (expected != null && toWrite.first.height != expected) {
      throw StateError(
        'BlockFilterStore.flush: expected height $expected, '
        'got ${toWrite.first.height} - non-sequential write rejected',
      );
    }
    for (final e in toWrite) buf.write('${_entryToLine(e)}\n');
    file.writeAsStringSync(buf.toString(), mode: FileMode.append);
    _writeHead = toWrite.last.height;
    if (verbose) {
      _log.info(
        'Block filters appended: heights ${toWrite.first.height}-${toWrite.last.height}',
      );
    }
  }
}
