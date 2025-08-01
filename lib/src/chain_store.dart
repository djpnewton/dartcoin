import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'block.dart';
import 'utils.dart';

final _log = Logger('ChainStore');

abstract class Node<Self extends Node<Self>> {
  Self? previous;
  Node({this.previous});
}

class ChainEntry extends Node<ChainEntry> {
  int height;
  BlockHeader header;
  BigInt work;
  BigInt chainWork;
  int timeCreated = DateTime.now().millisecondsSinceEpoch;
  ChainEntry({
    required this.height,
    required this.header,
    required this.work,
    required this.chainWork,
    super.previous,
  });
}

class BlockFilterHeaderEntry extends Node<BlockFilterHeaderEntry> {
  int height;
  Uint8List header;
  BlockFilterHeaderEntry({
    required this.height,
    required this.header,
    super.previous,
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
