import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'block.dart';
import 'logc.dart';
import 'chain_store.dart';
import 'utils.dart';

final _log = ColorLogger('CS_File');

/// [ChainStore] implementation backed by a single file on disk.
class ChainStoreFile implements ChainStore {
  final String filePath;

  ChainStoreFile(this.filePath);

  @override
  Future<void> init() async {}

  @override
  Future<bool> exists() async => await File(filePath).exists();

  @override
  Future<bool> empty() async =>
      !(await exists()) || await File(filePath).length() == 0;

  @override
  Future<void> delete() async {
    if (await exists()) await File(filePath).delete();
  }

  @override
  Future<List<String>> readLines() async => await File(filePath).readAsLines();

  @override
  Future<void> writeAll(String content) async {
    final file = File(filePath);
    if (await file.exists()) {
      throw StateError('Storage already exists: $filePath');
    }
    await file.create(recursive: true);
    await file.writeAsString(content);
  }

  @override
  Future<void> append(String content) async =>
      await File(filePath).writeAsString(content, mode: FileMode.append);
}

/// [BlockStore] implementation that persists blocks as individual `.bin` files
/// under `[dirPath]/blocks/`, with a JSON index for fast look-up.
///
/// Layout:
///   [dirPath]/blocks/[blockHash].bin   – raw serialised block bytes
///   [dirPath]/blocks/index.json        – dictionary of blockHash (hex) →
///                                        { filename, lastAccessed (ISO-8601) }
class BlockStoreFile implements BlockStore {
  final String _blocksDir;
  final bool verbose;
  Map<String, _BlockIndexEntry> _index = {};
  bool initialized = false;

  BlockStoreFile(String dirPath, {this.verbose = false})
    : _blocksDir = '$dirPath/blocks';

  String get _indexPath => '$_blocksDir/index.json';

  @override
  Future<void> init() async {
    final file = File(_indexPath);
    if (!await file.exists()) {
      _index = {};
      initialized = true;
      return;
    }
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    _index = json.map(
      (k, v) =>
          MapEntry(k, _BlockIndexEntry.fromJson(v as Map<String, dynamic>)),
    );
    initialized = true;
  }

  void _ensureInitialized() {
    if (!initialized) {
      throw StateError('BlockStoreFile not initialized. Call init() first.');
    }
  }

  Future<void> _saveIndex() async {
    _ensureInitialized();
    final file = File(_indexPath);
    if (!await file.exists()) await file.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent(
        '  ',
      ).convert(_index.map((k, v) => MapEntry(k, v.toJson()))),
    );
  }

  @override
  Future<bool> contains(Uint8List blockHash) async {
    _ensureInitialized();
    return _index.containsKey(blockHash.toHex());
  }

  @override
  Future<void> store(Block block) async {
    _ensureInitialized();
    final hashHex = block.hash().toHex();
    if (_index.containsKey(hashHex)) return;
    final filename = '$hashHex.bin';
    final file = File('$_blocksDir/$filename');
    if (!await file.exists()) await file.create(recursive: true);
    await file.writeAsBytes(block.toBytes());
    _index[hashHex] = _BlockIndexEntry(
      filename: filename,
      lastAccessed: DateTime.now(),
    );
    await _saveIndex();
    if (verbose) _log.info('Stored block $hashHex');
  }

  @override
  Future<Block?> read(Uint8List blockHash) async {
    _ensureInitialized();
    final hashHex = blockHash.toHex();
    final entry = _index[hashHex];
    if (entry == null) return null;
    final file = File('$_blocksDir/${entry.filename}');
    if (!await file.exists()) return null;
    final block = Block.fromBytes(Uint8List.fromList(await file.readAsBytes()));
    entry.lastAccessed = DateTime.now();
    await _saveIndex();
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
