import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'block.dart';
import 'logc.dart';
import 'chain_store.dart';
import 'utils.dart';

final _log = ColorLogger('CS_File');

/// [ChainStore] implementation backed by a single file on disk.
class FileChainStore implements ChainStore {
  final String filePath;

  FileChainStore(this.filePath);

  @override
  bool exists() => File(filePath).existsSync();

  @override
  bool empty() => !exists() || File(filePath).lengthSync() == 0;

  @override
  void delete() {
    if (exists()) File(filePath).deleteSync();
  }

  @override
  List<String> readLines() => File(filePath).readAsLinesSync();

  @override
  void writeAll(String content) {
    final file = File(filePath);
    if (file.existsSync()) {
      throw StateError('Storage already exists: $filePath');
    }
    file.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  @override
  void append(String content) =>
      File(filePath).writeAsStringSync(content, mode: FileMode.append);
}

/// [BlockStore] implementation that persists blocks as individual `.bin` files
/// under `[dirPath]/blocks/`, with a JSON index for fast look-up.
///
/// Layout:
///   [dirPath]/blocks/[blockHash].bin   – raw serialised block bytes
///   [dirPath]/blocks/index.json        – dictionary of blockHash (hex) →
///                                        { filename, lastAccessed (ISO-8601) }
class FileBlockStore implements BlockStore {
  final String _blocksDir;
  final bool verbose;
  Map<String, _BlockIndexEntry> _index = {};

  FileBlockStore(String dirPath, {this.verbose = false})
    : _blocksDir = '$dirPath/blocks' {
    _loadIndex();
  }

  String get _indexPath => '$_blocksDir/index.json';

  void _loadIndex() {
    final file = File(_indexPath);
    if (!file.existsSync()) {
      _index = {};
      return;
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    _index = json.map(
      (k, v) =>
          MapEntry(k, _BlockIndexEntry.fromJson(v as Map<String, dynamic>)),
    );
  }

  void _saveIndex() {
    final file = File(_indexPath);
    if (!file.existsSync()) file.createSync(recursive: true);
    file.writeAsStringSync(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(_index.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  @override
  bool contains(Uint8List blockHash) => _index.containsKey(blockHash.toHex());

  @override
  void store(Block block) {
    final hashHex = block.hash().toHex();
    if (_index.containsKey(hashHex)) return;
    final filename = '$hashHex.bin';
    final file = File('$_blocksDir/$filename');
    if (!file.existsSync()) file.createSync(recursive: true);
    file.writeAsBytesSync(block.toBytes());
    _index[hashHex] = _BlockIndexEntry(
      filename: filename,
      lastAccessed: DateTime.now(),
    );
    _saveIndex();
    if (verbose) _log.info('Stored block $hashHex');
  }

  @override
  Block? read(Uint8List blockHash) {
    final hashHex = blockHash.toHex();
    final entry = _index[hashHex];
    if (entry == null) return null;
    final file = File('$_blocksDir/${entry.filename}');
    if (!file.existsSync()) return null;
    final block = Block.fromBytes(Uint8List.fromList(file.readAsBytesSync()));
    entry.lastAccessed = DateTime.now();
    _saveIndex();
    return block;
  }
}

class _BlockIndexEntry {
  final String filename;
  DateTime lastAccessed;

  _BlockIndexEntry({required this.filename, required this.lastAccessed});

  factory _BlockIndexEntry.fromJson(Map<String, dynamic> json) =>
      _BlockIndexEntry(
        filename: json['filename'] as String,
        lastAccessed: DateTime.parse(json['lastAccessed'] as String),
      );

  Map<String, dynamic> toJson() => {
    'filename': filename,
    'lastAccessed': lastAccessed.toIso8601String(),
  };
}
