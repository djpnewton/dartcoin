import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'common.dart';
import 'utils.dart';
import 'block.dart';

final _log = Logger('Chain');

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

enum ChainStatus {
  headerSync, // syncing headers from peers
  active, // activated chain, read/write operations allowed
}

enum AddHeadersResult { success, invalidHeader, noChainHead }

class ChainManager {
  static const int difficultyAdjustmentInterval = 2016;
  static const int maxTimewarp = 600;
  static const int maxReorgDepth = 50;

  final Network network;
  late ChainStatus _status;
  final String _blockHeadersFilePath;
  final bool verbose;
  late final BlockHeader _genesisBlockHeader;
  late ChainEntry _bestChainHead;
  final List<ChainEntry> _chainHeads = [];
  ChainEntry? _fileChainHead;

  ChainStatus get status => _status;
  ChainEntry get bestChainHead => _bestChainHead;
  List<ChainEntry> get chainHeads => _chainHeads;

  ChainManager({
    required this.network,
    required String blockHeadersFilePath,
    this.verbose = false,
  }) : _blockHeadersFilePath = blockHeadersFilePath {
    _status = ChainStatus.headerSync;
    _genesisBlockHeader = Block.genesisBlock(network).header;
    _bestChainHead = _initBestHeader(network);
    _chainHeads.add(_bestChainHead);
  }

  BigInt _minumumChainWork(Network network) {
    return switch (network) {
      Network.mainnet => BigInt.parse(
        '0x0000000000000000000000000000000000000000b1f3b93b65b16d035a82be84',
      ),
      Network.testnet => BigInt.parse(
        '0x0000000000000000000000000000000000000000000015f5e0c9f13455b0eb17',
      ),
      Network.testnet4 => BigInt.parse(
        '0x0000000000000000000000000000000000000000000001d6dce8651b6094e4c1',
      ),
      Network.regtest => BigInt.zero,
    };
  }

  ChainEntry _initBestHeader(Network network) {
    // check if the header file exists and is not empty
    if (File(_blockHeadersFilePath).existsSync() &&
        File(_blockHeadersFilePath).lengthSync() > 0) {
      final headers = _blockHeadersFileRead();
      if (headers.isNotEmpty) {
        if (_compareHashes(headers.first.hash(), _genesisBlockHeader.hash())) {
          ChainEntry? previous;
          ChainEntry? chainHead;
          for (final header in headers) {
            chainHead = _makeChainEntry(header, previous);
            previous = chainHead;
          }
          _fileChainHead = chainHead;
          return chainHead!;
        }
        _log.warning(
          'Genesis block header hash mismatch: ${headers.first.hash().toHex()} != ${_genesisBlockHeader.hash().toHex()}',
        );
      }
    }
    // if no headers file or mismatch, start with genesis block header
    return _makeChainEntry(_genesisBlockHeader, null);
  }

  bool _compareHashes(Uint8List hash1, Uint8List hash2) {
    if (hash1.length != hash2.length) {
      return false;
    }
    for (int i = 0; i < hash1.length; i++) {
      if (hash1[i] != hash2[i]) {
        return false;
      }
    }
    return true;
  }

  List<BlockHeader> _blockHeadersFileRead() {
    final headersFile = File(_blockHeadersFilePath);
    if (!headersFile.existsSync()) {
      throw StateError(
        'Block headers file does not exist: $_blockHeadersFilePath',
      );
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

  void _blockHeadersFileWrite() {
    if (status != ChainStatus.active) {
      throw StateError(
        'Cannot write block headers to file in non-active chain status: $status',
      );
    }
    final chainEntries = _chainEntryListFromHead(_bestChainHead, null);
    if (chainEntries.isEmpty) {
      throw StateError('Cannot write block headers without entries');
    }
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
    final headersFile = File(_blockHeadersFilePath);
    if (headersFile.existsSync()) {
      throw StateError(
        'Block headers file already exists: $_blockHeadersFilePath.',
      );
    }
    headersFile.createSync(recursive: true);
    headersFile.writeAsStringSync(csvData.toString());
    if (verbose) {
      _log.info('Block headers written to file: $_blockHeadersFilePath');
    }
    // update the file chain head
    _fileChainHead = _bestChainHead;
  }

  void _blockHeadersFileAppend(List<ChainEntry> chainEntries) {
    if (status != ChainStatus.active) {
      throw StateError(
        'Cannot write block headers to file in non-active chain status: $status',
      );
    }
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
    final headersFile = File(_blockHeadersFilePath);
    if (!headersFile.existsSync()) {
      throw StateError(
        'Block headers file does not exist: $_blockHeadersFilePath',
      );
    }
    // check the last height in the file
    final lines = headersFile.readAsLinesSync();
    if (lines.isEmpty) {
      throw StateError('Headers file is empty, cannot append new entries');
    }
    final lastHeight = int.tryParse(lines.last.split(',')[0]);
    if (lastHeight == null) {
      throw StateError('Invalid last height in headers file');
    }
    if (lastHeight != chainEntries.first.previous?.height) {
      throw StateError(
        'Last height in file ($lastHeight) does not match first height in new entries (${chainEntries.first.height})',
      );
    }
    // write new entries to the file
    headersFile.writeAsStringSync(csvData.toString(), mode: FileMode.append);
    if (verbose) {
      _log.info('Block headers appended to file: $_blockHeadersFilePath');
    }
    // update the file chain head
    _fileChainHead = _bestChainHead;
  }

  void _blockHeadersFileDelete() {
    final headersFile = File(_blockHeadersFilePath);
    if (headersFile.existsSync()) {
      headersFile.deleteSync();
      if (verbose) {
        _log.info('Block headers file deleted: $_blockHeadersFilePath');
      }
    } else {
      _log.warning('Block headers file does not exist: $_blockHeadersFilePath');
    }
    // reset the file chain head
    _fileChainHead = null;
  }

  void _blockHeadersFileWriteOrAppend() {
    // if no block headers have been read from the file yet,
    // write the entire headers file
    if (_fileChainHead == null) {
      _blockHeadersFileWrite();
    } else {
      // find the list of chain entries from the best chain head to the file chain head
      // this *should* not be empty because we are called after adding new headers
      final chainEntries = _chainEntryListFromHead(
        _bestChainHead,
        _fileChainHead,
      );
      // if the list is empty or contains the genesis block,
      // it means we have reorged past the file chain head
      // so we need to rewrite the entire headers file (should happen very infrequently)
      if (chainEntries.isEmpty || chainEntries.first.height == 0) {
        _blockHeadersFileDelete();
        _blockHeadersFileWrite();
      } else {
        _blockHeadersFileAppend(chainEntries);
      }
    }
  }

  List<BlockHeader> _blockHeadersTake(ChainEntry ce, int count) {
    final headers = <BlockHeader>[];
    var current = ce;
    for (int i = 0; i < count; i++) {
      headers.add(current.header);
      if (headers.length == count) {
        break;
      }
      if (current.previous == null) {
        throw StateError('Not enough headers available to take $count headers');
      }
      current = current.previous!;
    }
    return headers;
  }

  BlockHeader _blockHeaderGet(ChainEntry ce, int height) {
    if (height < 0 || height > ce.height) {
      throw RangeError('Height $height is out of range (0-${ce.height})');
    }
    var current = ce;
    while (current.height > height) {
      current = current.previous!;
    }
    return current.header;
  }

  List<Uint8List> get recentBlockHeadersHashes {
    return _blockHeadersTake(
      _bestChainHead,
      _bestChainHead.height + 1 < maxReorgDepth
          ? _bestChainHead.height + 1
          : maxReorgDepth,
    ).map((header) => header.hash()).toList();
  }

  ChainEntry _makeChainEntry(BlockHeader header, ChainEntry? previous) {
    final work = header.work();
    return ChainEntry(
      height: (previous?.height ?? -1) + 1,
      header: header,
      work: work,
      chainWork: (previous?.chainWork ?? BigInt.zero) + work,
      previous: previous,
    );
  }

  ChainEntry? _findNewChainHead(BlockHeader header, int maxReorgDepth) {
    if (verbose) {
      _log.info(
        'Finding new chainhead for header: ${headerHashNice(header.hash())} (prev: ${headerHashNice(header.previousBlockHeaderHash)})',
      );
    }
    // check if the header builds on the best chainhead (should be most common case)
    if (_compareHashes(
      _bestChainHead.header.hash(),
      header.previousBlockHeaderHash,
    )) {
      return _makeChainEntry(header, _bestChainHead);
    }
    // check if the header builds on one of the chainheads
    for (final chainHead in _chainHeads) {
      if (_compareHashes(
        chainHead.header.hash(),
        header.previousBlockHeaderHash,
      )) {
        return _makeChainEntry(header, chainHead);
      }
    }
    // check if the header is a reorg of one of the heads (up to maxReorgDepth)
    final headerHash = header.hash();
    for (final chainHead in _chainHeads) {
      if (chainHead.height < _bestChainHead.height - maxReorgDepth) continue;
      final initialHeight = chainHead.height;
      ChainEntry? current = chainHead;
      while (current != null &&
          current.height >= 0 &&
          current.height >= initialHeight - maxReorgDepth) {
        final currentHash = current.header.hash();
        if (_compareHashes(currentHash, headerHash)) {
          return null; // already in the chain, no new chainhead found
        }
        if (_compareHashes(currentHash, header.previousBlockHeaderHash)) {
          return _makeChainEntry(header, current);
        }
        current = current.previous;
      }
    }
    return null; // no new chainhead found
  }

  bool _checkMedianTimePast(ChainEntry newChainHead) {
    if (newChainHead.previous == null) {
      throw StateError('Cannot check median time past for the genesis block');
    }
    // block time must be greater then the median time of the last 11 blocks
    if (newChainHead.height < 11) {
      return true; // not enough headers to check median time
    }
    final last11Headers = _blockHeadersTake(newChainHead.previous!, 11);
    last11Headers.sort((a, b) => a.time.compareTo(b.time));
    final medianTime = last11Headers[5].time; // 6th element is the median
    if (newChainHead.header.time <= medianTime) {
      _log.warning(
        'Received header with invalid timestamp: ${newChainHead.header.time}, median time: $medianTime',
      );
      return false;
    }
    return true;
  }

  int _calcNextWorkRequired(ChainEntry newChainHead) {
    if (newChainHead.previous == null) {
      throw StateError(
        'Cannot calculate next work required for the genesis block',
      );
    }
    // convert bits to target
    var currentBits = newChainHead.previous!.header.nBits;
    if (network == Network.testnet4) {
      // bip 94 rule on testnet4
      currentBits = _blockHeaderGet(
        newChainHead,
        newChainHead.height - difficultyAdjustmentInterval,
      ).nBits;
    }
    final target = BlockHeader.bitsToTarget(currentBits);
    // recalculate the difficulty
    var actualTimespan =
        newChainHead.previous!.header.time -
        _blockHeaderGet(
          newChainHead,
          newChainHead.height - difficultyAdjustmentInterval,
        ).time;
    final expectedTimespan = 14 * 24 * 60 * 60; // 14 days in seconds
    if (actualTimespan < expectedTimespan ~/ 4) {
      if (verbose) {
        _log.info(
          'Actual timespan is less than 1/4 of expected: $actualTimespan < ${expectedTimespan ~/ 4}',
        );
      }
      actualTimespan = expectedTimespan ~/ 4;
    }
    if (actualTimespan > expectedTimespan * 4) {
      if (verbose) {
        _log.info(
          'Actual timespan is more than 4x of expected: $actualTimespan > ${expectedTimespan * 4}',
        );
      }
      actualTimespan = expectedTimespan * 4;
    }
    final ratio = actualTimespan / expectedTimespan;
    if (verbose) {
      _log.info(
        'Ratio: $ratio, Actual Timespan: $actualTimespan, Expected Timespan: $expectedTimespan',
      );
    }
    final newTarget =
        (target * BigInt.from(actualTimespan)) ~/ BigInt.from(expectedTimespan);
    final newBits = BlockHeader.targetToBits(newTarget);
    if (verbose) {
      _log.info(
        'Recalculating difficulty: Old Bits: ${currentBits.toRadixString(16)}, New Bits: ${newBits.toRadixString(16)}',
      );
    }
    // check newBits is not greater than the genesis block's nBits
    final genesisTarget = BlockHeader.bitsToTarget(_genesisBlockHeader.nBits);
    if (newTarget > genesisTarget) {
      _log.warning(
        'New target is greater than genesis target: $newTarget > $genesisTarget',
      );
      return _genesisBlockHeader.nBits;
    }
    return newBits;
  }

  int _getNextWork(ChainEntry newChainHead) {
    if (newChainHead.previous == null) {
      throw StateError('Cannot get next work for the genesis block');
    }
    // calculate new work on new epoch
    if (newChainHead.height % difficultyAdjustmentInterval == 0) {
      return _calcNextWorkRequired(newChainHead);
    }
    // reset the work required on testnet if the time between blocks is more than 20 minutes
    if (network == Network.testnet || network == Network.testnet4) {
      final lastTime = newChainHead.previous!.header.time;
      const resetTime = 20 * 60; // 20 minutes in seconds
      var blockInterval = newChainHead.header.time - lastTime;
      if (blockInterval > resetTime) {
        if (verbose) {
          _log.info(
            'Resetting work required on testnet due to long time since last block: $blockInterval seconds',
          );
        }
        return _genesisBlockHeader.nBits; // reset to the first block's nBits
      } else if (newChainHead.previous!.height > 2) {
        // use the last non special minimum difficulty block
        ChainEntry? current = newChainHead.previous;
        while (current != null &&
            (current.height + 1) % difficultyAdjustmentInterval != 0 &&
            current.header.nBits == _genesisBlockHeader.nBits) {
          current = current.previous;
        }
        return current?.header.nBits ?? _genesisBlockHeader.nBits;
      }
    }
    // otherwise, use the last block's nBits
    return newChainHead.previous!.header.nBits;
  }

  void _updateHeads(ChainEntry newChainHead) {
    // 1) check if the new chainhead can replace one of the existing heads
    var replacedHead = false;
    for (final chainHead in _chainHeads) {
      if (_compareHashes(
        chainHead.header.hash(),
        newChainHead.header.previousBlockHeaderHash,
      )) {
        // remove the old chainhead
        _chainHeads.remove(chainHead);
        // add the new chainhead
        _chainHeads.add(newChainHead);
        // set 'replacedHead' and break
        replacedHead = true;
        break;
      }
    }
    // 2) if the new chainhead does not replace any existing chainhead it must be a reorg so add it as a new chainhead
    if (!replacedHead) {
      if (verbose) {
        _log.info(
          'Adding new chainhead: ${newChainHead.header.hashNice()} at height ${newChainHead.height}',
        );
      }
      _chainHeads.add(newChainHead);
    }
    // 3) find the new best chainhead based on chain work (and time created)
    List<ChainEntry> candidates = [];
    for (final chainHead in _chainHeads) {
      if (candidates.isEmpty ||
          chainHead.chainWork > candidates.first.chainWork) {
        candidates.clear();
        candidates.add(chainHead);
      } else if (chainHead.chainWork == candidates.first.chainWork) {
        candidates.add(chainHead);
      }
    }
    if (candidates.length == 1) {
      _bestChainHead = candidates.first;
    } else {
      // if there are multiple candidates, choose the one with earliest timeCreated
      candidates.sort((a, b) => a.timeCreated.compareTo(b.timeCreated));
      _bestChainHead = candidates.first;
    }
  }

  List<ChainEntry> _chainEntryListFromHead(
    ChainEntry chainHead,
    ChainEntry? initialChainHead,
  ) {
    final chainEntries = <ChainEntry>[];
    ChainEntry? current = chainHead;
    // collect all chain entries from a chainhead up to initialChainHead (if provided)
    while (current != null &&
        (initialChainHead == null ||
            !_compareHashes(
              current.header.hash(),
              initialChainHead.header.hash(),
            ))) {
      chainEntries.add(current);
      current = current.previous;
    }
    return chainEntries.reversed.toList();
  }

  void _cleanHeads() {
    // remove chainheads that are too far behind the best chainhead
    _chainHeads.removeWhere(
      (chainHead) => chainHead.height < _bestChainHead.height - maxReorgDepth,
    );
  }

  AddHeadersResult addHeaders(List<BlockHeader> headers) {
    if (headers.isEmpty) {
      return AddHeadersResult.success;
    }
    final initialBest = _bestChainHead;
    var headersAdded = 0;
    for (final header in headers) {
      //print('add header: ${headerHashNice(header.hash())} (best height: ${_bestChainHead.height}, ..${headerHashNice(_bestChainHead.header.hash()).substring(54)})');
      // create new chainhead from block header
      final newChainHead = _findNewChainHead(
        header,
        headers.length > maxReorgDepth ? headers.length : maxReorgDepth,
      );
      if (newChainHead == null) {
        _log.warning(
          'Received header (${headerHashNice(header.hash())}, prev: ..${headerHashNice(header.previousBlockHeaderHash).substring(54)}) does not build on (or reorg) any known chainhead',
        );
        continue; // skip this header
      }
      final headerHash = newChainHead.header.hash();
      final headerHashReversed = reverseHash(headerHash);
      if (verbose) {
        _log.info(
          'Received header: ${headerHashNice(headerHash)}, height: ${newChainHead.height}, time: ${newChainHead.header.time - newChainHead.previous!.header.time}s',
        );
        _log.info(
          'header bits:     ${newChainHead.header.nBits.toRadixString(16)}',
        );
        _log.info(
          'header target:   ${BlockHeader.bitsToTarget(newChainHead.header.nBits).toRadixString(16).padLeft(64, '0')}',
        );
      }
      // check the median time past
      if (!_checkMedianTimePast(newChainHead)) {
        return AddHeadersResult.invalidHeader; // abort adding headers
      }
      // check testnet4 timewarp rule (bip 94)
      if (network == Network.testnet4) {
        if (newChainHead.height % difficultyAdjustmentInterval == 0 &&
            newChainHead.previous!.height > 0) {
          if (newChainHead.header.time <
              newChainHead.previous!.header.time - maxTimewarp) {
            _log.warning(
              'Received header with invalid time: ${newChainHead.header.time}, expected greater then or equal to ${newChainHead.previous!.header.time - maxTimewarp}',
            );
            return AddHeadersResult.invalidHeader; // abort adding headers
          }
        }
      }
      // get the work required
      final bits = _getNextWork(newChainHead);
      if (verbose) {
        _log.info('Work required:   ${bits.toRadixString(16).padLeft(8, '0')}');
      }
      // check the work
      if (bits != newChainHead.header.nBits) {
        _log.warning(
          'Received header with different nBits: ${newChainHead.header.nBits.toRadixString(16)}, expected: ${bits.toRadixString(16)}',
        );
        return AddHeadersResult.invalidHeader; // abort adding headers
      }
      final target = BlockHeader.bitsToTarget(bits);
      final headerWork = bytesToBigInt(headerHashReversed);
      if (headerWork > target) {
        _log.warning(
          'Received header with insufficient work: ${headerHashNice(headerHash)} (needed: ${target.toRadixString(16).padLeft(64, '0')})',
        );
        return AddHeadersResult.invalidHeader; // abort adding headers
      }
      // update heads
      _updateHeads(newChainHead);
      // update number of headers added
      headersAdded += 1;
    }
    // if no headers were added, return no chain head found
    if (headersAdded == 0) {
      return AddHeadersResult.noChainHead;
    }
    if (verbose) {
      _log.info(
        'Added $headersAdded headers, new height: ${_bestChainHead.height}, chain work: ${_bestChainHead.chainWork.toRadixString(16)}',
      );
    }
    // if the chain is active, write the headers to file
    if (status == ChainStatus.active) {
      // write the headers to file
      if (!_compareHashes(
        _bestChainHead.header.hash(),
        initialBest.header.hash(),
      )) {
        _blockHeadersFileWriteOrAppend();
      }
    }
    // clean chainheads
    _cleanHeads();
    return AddHeadersResult.success;
  }

  bool hasMinimumChainWork() {
    return _bestChainHead.chainWork >= _minumumChainWork(network);
  }

  void activate() {
    if (status != ChainStatus.headerSync) {
      throw StateError('Cannot activate chain in status: $status');
    }
    if (verbose) {
      _log.info(
        'Activating chain with best header: ${headerHashNice(_bestChainHead.header.hash())}',
      );
    }
    // set the status to active
    // this allows writing block headers to file
    _status = ChainStatus.active;
    // write the best chain head to file
    _blockHeadersFileWriteOrAppend();
  }

  void sync() {
    if (status != ChainStatus.active) {
      throw StateError('Cannot sync chain in status: $status');
    }
    // set status back to header sync
    _status = ChainStatus.headerSync;
  }
}
