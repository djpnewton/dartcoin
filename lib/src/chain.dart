import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'common.dart';
import 'utils.dart';
import 'block.dart';
import 'block_filter.dart';
import 'chain_store.dart';

final _log = Logger('Chain');

enum AddBlockHeadersResult { success, invalidBlockHeader, noChainHead }

enum AddBlockFilterHeadersResult { success, invalidBlockFilterHeader }

class ChainManager {
  static const int difficultyAdjustmentInterval = 2016;
  static const int maxTimewarp = 600;
  static const int maxReorgDepth = 50;

  final Network network;
  bool _activeChain = false;
  final bool verbose;
  late final BlockHeader _genesisBlockHeader;
  late final Uint8List _genesisBlockFilterHeader;
  final Map<int, Uint8List> _blockHeaderHeightIndex = {};
  final Map<int, Uint8List> _blockFilterHeaderHeightIndex = {};
  // block headers
  late ChainEntry _bestChainHead;
  final List<ChainEntry> _chainHeads = [];
  ChainEntry? _fileChainHead;
  final BlockHeaderStore _blockHeaderStore;
  // block filter headers
  late BlockFilterHeaderEntry _bestBlockFilterHead;
  BlockFilterHeaderEntry? _fileBlockFilterHead;
  final BlockFilterHeaderStore _blockFilterHeaderStore;

  // public getters
  bool get activeChain => _activeChain;
  ChainEntry get bestChainHead => _bestChainHead;
  BlockFilterHeaderEntry get bestBlockFilterHead => _bestBlockFilterHead;
  List<ChainEntry> get chainHeads => _chainHeads;
  List<Uint8List> get recentBlockHeadersHashes {
    return _blockHeadersTake(
      _bestChainHead,
      _bestChainHead.height + 1 < maxReorgDepth
          ? _bestChainHead.height + 1
          : maxReorgDepth,
    ).map((header) => header.hash()).toList();
  }

  ChainManager({
    required this.network,
    required String blockHeadersFilePath,
    required String blockFilterHeadersFilePath,
    this.verbose = false,
  }) : _blockHeaderStore = BlockHeaderStore(blockHeadersFilePath),
       _blockFilterHeaderStore = BlockFilterHeaderStore(
         blockFilterHeadersFilePath,
       ) {
    // init genesis headers
    _genesisBlockHeader = Block.genesisBlock(network).header;
    final genesisFilter = BasicBlockFilter(
      block: Block.genesisBlock(network),
      prevOutputScripts: [],
    );
    _genesisBlockFilterHeader = BasicBlockFilter.filterHeader(
      genesisFilter.filterHash,
      BasicBlockFilter.genesisPreviousHeader,
    );
    // init best heads
    _bestChainHead = _initBestHeader(network);
    _updateBlockHeaderHeightIndex();
    _chainHeads.add(_bestChainHead);
    _bestBlockFilterHead = _initBestBlockFilterHeaderHead(network);
    _updateBlockFilterHeaderHeightIndex();
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
    if (_blockHeaderStore.exists() && !_blockHeaderStore.empty()) {
      final headers = _blockHeaderStore.read();
      if (headers.isNotEmpty) {
        if (compareHashes(headers.first.hash(), _genesisBlockHeader.hash())) {
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

  BlockFilterHeaderEntry _initBestBlockFilterHeaderHead(Network network) {
    // check if the block filter headers file exists and is not empty
    if (_blockFilterHeaderStore.exists() && !_blockFilterHeaderStore.empty()) {
      final headers = _blockFilterHeaderStore.read();
      if (headers.isNotEmpty) {
        if (compareHashes(headers.first, _genesisBlockFilterHeader)) {
          BlockFilterHeaderEntry? previous;
          BlockFilterHeaderEntry? head;
          for (final header in headers) {
            head = _makeBlockFilterHeaderEntry(header, previous);
            previous = head;
          }
          _fileBlockFilterHead = head;
          return head!;
        }
        _log.warning(
          'Genesis block filter header hash mismatch: ${headers.first.toHex()} != ${_genesisBlockFilterHeader.toHex()}',
        );
      }
    }
    // if no headers file or mismatch, start with genesis block filter header
    return _makeBlockFilterHeaderEntry(_genesisBlockFilterHeader, null);
  }

  void _blockHeadersFileWrite() {
    if (!_activeChain) {
      throw StateError(
        'Cannot write block headers to file in non-active chain',
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
    _blockHeaderStore.write(chainEntries);
    // update the file chain head
    _fileChainHead = _bestChainHead;
  }

  void _blockHeadersFileAppend(List<ChainEntry> chainEntries) {
    if (!_activeChain) {
      throw StateError(
        'Cannot write block headers to file in non-active chain',
      );
    }
    _blockHeaderStore.append(chainEntries);
    // update the file chain head
    _fileChainHead = _bestChainHead;
  }

  void _blockHeadersFileDelete() {
    _blockHeaderStore.delete();
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

  void _blockFilterHeadersFileWrite() {
    final entries = _filterEntryListFromHead(_bestBlockFilterHead, null);
    if (entries.isEmpty) {
      throw StateError('Cannot write block filter headers without entries');
    }
    if (entries.first.previous != null) {
      throw StateError(
        'First entry must be the genesis block when writing entire filter headers file',
      );
    }
    _blockFilterHeaderStore.write(entries);
    // update the file chain head
    _fileBlockFilterHead = _bestBlockFilterHead;
  }

  void _blockFilterHeadersFileAppend(List<BlockFilterHeaderEntry> entries) {
    _blockFilterHeaderStore.append(entries);
    // update the file chain head
    _fileBlockFilterHead = _bestBlockFilterHead;
  }

  void _blockFilterHeadersFileDelete() {
    _blockFilterHeaderStore.delete();
    // reset the file chain head
    _fileBlockFilterHead = null;
  }

  void _blockFilterHeadersFileWriteOrAppend() {
    // if no block headers have been read from the file yet,
    // write the entire headers file
    if (_fileBlockFilterHead == null) {
      _blockFilterHeadersFileWrite();
    } else {
      // find the list of chain entries from the best chain head to the file chain head
      // this *should* not be empty because we are called after adding new headers
      final chainEntries = _filterEntryListFromHead(
        _bestBlockFilterHead,
        _fileBlockFilterHead,
      );
      // if the list is empty or contains the genesis block,
      // it means we have reorged past the file chain head
      // so we need to rewrite the entire headers file (should happen very infrequently)
      if (chainEntries.isEmpty || chainEntries.first.height == 0) {
        _blockFilterHeadersFileDelete();
        _blockFilterHeadersFileWrite();
      } else {
        _blockFilterHeadersFileAppend(chainEntries);
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

  BlockFilterHeaderEntry _makeBlockFilterHeaderEntry(
    Uint8List header,
    BlockFilterHeaderEntry? previous,
  ) {
    return BlockFilterHeaderEntry(
      height: (previous?.height ?? -1) + 1,
      header: header,
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
    if (canAddBlockHeader(header)) {
      return _makeChainEntry(header, _bestChainHead);
    }
    // check if the header builds on one of the chainheads
    for (final chainHead in _chainHeads) {
      if (compareHashes(
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
        if (compareHashes(currentHash, headerHash)) {
          return null; // already in the chain, no new chainhead found
        }
        if (compareHashes(currentHash, header.previousBlockHeaderHash)) {
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
            current.height % difficultyAdjustmentInterval != 0 &&
            current.header.nBits == _genesisBlockHeader.nBits) {
          current = current.previous;
        }
        if (current == null) {
          _log.warning(
            'No previous block found with non-genesis nBits, using genesis nBits',
          );
          return _genesisBlockHeader.nBits;
        }
        return current.header.nBits;
      }
    }
    // otherwise, use the last block's nBits
    return newChainHead.previous!.header.nBits;
  }

  void _updateHeads(ChainEntry newChainHead) {
    // 1) check if the new chainhead can replace one of the existing heads
    var replacedHead = false;
    for (final chainHead in _chainHeads) {
      if (compareHashes(
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
    ChainEntry newBest;
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
      newBest = candidates.first;
    } else {
      // if there are multiple candidates, choose the one with earliest timeCreated
      candidates.sort((a, b) => a.timeCreated.compareTo(b.timeCreated));
      newBest = candidates.first;
    }
    // 4) if the new best chainhead is a reorg we need to find the point where the reorg starts
    if (newBest != _bestChainHead && newBest.previous != _bestChainHead) {
      // rewind new best chainhead to the same height as the current best chainhead
      var newBestPrev = newBest;
      while (newBestPrev.height > _bestChainHead.height) {
        if (newBestPrev.previous == null) {
          throw StateError(
            'New best chainhead has no previous block, cannot rewind to current best height',
          );
        }
        newBestPrev = newBestPrev.previous!;
      }
      var currentBestPrev = _bestChainHead;
      while (!compareHashes(
        currentBestPrev.header.hash(),
        newBestPrev.header.hash(),
      )) {
        if (currentBestPrev.previous == null) {
          throw StateError(
            'Current best chainhead has no previous block, cannot find reorg point',
          );
        }
        currentBestPrev = currentBestPrev.previous!;
        if (newBestPrev.previous == null) {
          throw StateError(
            'New best chainhead has no previous block, cannot find reorg point',
          );
        }
        newBestPrev = newBestPrev.previous!;
      }
      // 4a) now we have the point where the reorg starts, we can reset the block filter headers to this point
      _resetBlockFilterHeaders(currentBestPrev);
    }
    // 5) update the best chain head
    _bestChainHead = newBest;
    _updateBlockHeaderHeightIndex();
  }

  void _updateBlockHeaderHeightIndex() {
    ChainEntry? current = _bestChainHead;
    while (current != null) {
      final hash = current.header.hash();
      if (_blockHeaderHeightIndex.containsKey(current.height) &&
          _blockHeaderHeightIndex[current.height] == hash) {
        // already indexed and index matches chain
        break;
      }
      // add to or update the index
      _blockHeaderHeightIndex[current.height] = hash;
      current = current.previous;
    }
  }

  void _updateBlockFilterHeaderHeightIndex() {
    BlockFilterHeaderEntry? current = _bestBlockFilterHead;
    while (current != null) {
      final hash = current.header;
      if (_blockFilterHeaderHeightIndex.containsKey(current.height) &&
          compareHashes(_blockFilterHeaderHeightIndex[current.height]!, hash)) {
        // already indexed and index matches chain
        break;
      }
      // add to or update the index
      _blockFilterHeaderHeightIndex[current.height] = hash;
      current = current.previous;
    }
  }

  void _resetBlockFilterHeaders(ChainEntry reorgPoint) {
    // reset the block filter headers to the point where the reorg starts
    BlockFilterHeaderEntry? current = _bestBlockFilterHead;
    while (current != null && current.height > reorgPoint.height) {
      if (_blockFilterHeaderHeightIndex.containsKey(current.height)) {
        _blockFilterHeaderHeightIndex.remove(current.height);
      }
      current = current.previous;
    }
    if (current == null) {
      throw StateError('No block filter headers found for reorg point');
    }
    _bestBlockFilterHead = current;
    _blockFilterHeadersFileDelete();
    _blockFilterHeadersFileWrite();
    _fileBlockFilterHead = _bestBlockFilterHead;
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
            !compareHashes(
              current.header.hash(),
              initialChainHead.header.hash(),
            ))) {
      chainEntries.add(current);
      current = current.previous;
    }
    return chainEntries.reversed.toList();
  }

  List<BlockFilterHeaderEntry> _filterEntryListFromHead(
    BlockFilterHeaderEntry chainHead,
    BlockFilterHeaderEntry? initialChainHead,
  ) {
    final chainEntries = <BlockFilterHeaderEntry>[];
    BlockFilterHeaderEntry? current = chainHead;
    // collect all chain entries from a chainhead up to initialChainHead (if provided)
    while (current != null &&
        (initialChainHead == null ||
            !compareHashes(current.header, initialChainHead.header))) {
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

  bool canAddBlockHeader(BlockHeader header) {
    // Check if the header can be added to the chain
    return compareHashes(
      _bestChainHead.header.hash(),
      header.previousBlockHeaderHash,
    );
  }

  AddBlockHeadersResult addBlockHeaders(List<BlockHeader> headers) {
    if (headers.isEmpty) {
      return AddBlockHeadersResult.success;
    }
    final initialBest = _bestChainHead;
    var headersAdded = 0;
    for (final header in headers) {
      // check if header is already is a head
      bool isAHead = false;
      for (final chainHead in _chainHeads) {
        if (compareHashes(chainHead.header.hash(), header.hash())) {
          isAHead = true;
          headersAdded++;
          break;
        }
      }
      if (isAHead) {
        if (verbose) {
          _log.info(
            'Received header (${headerHashNice(header.hash())}) is already a chainhead, skipping',
          );
        }
        continue; // skip this header
      }
      // create new chainhead from block header
      final newChainHead = _findNewChainHead(
        header,
        headers.length > maxReorgDepth ? headers.length : maxReorgDepth,
      );
      if (newChainHead == null) {
        if (verbose) {
          _log.info(
            'Received header (${headerHashNice(header.hash())}, prev: ..${headerHashNice(header.previousBlockHeaderHash).substring(54)}) does not build on (or reorg) any known chainhead',
          );
        }
        continue; // skip this header
      }
      final headerHash = newChainHead.header.hash();
      final headerHashReversed = headerHash.reverse();
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
        return AddBlockHeadersResult.invalidBlockHeader; // abort adding headers
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
            return AddBlockHeadersResult
                .invalidBlockHeader; // abort adding headers
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
        return AddBlockHeadersResult.invalidBlockHeader; // abort adding headers
      }
      final target = BlockHeader.bitsToTarget(bits);
      final headerWork = bytesToBigInt(headerHashReversed);
      if (headerWork > target) {
        _log.warning(
          'Received header with insufficient work: ${headerHashNice(headerHash)} (needed: ${target.toRadixString(16).padLeft(64, '0')})',
        );
        return AddBlockHeadersResult.invalidBlockHeader; // abort adding headers
      }
      // update heads
      _updateHeads(newChainHead);
      // update number of headers added
      headersAdded += 1;
    }
    // if no headers were added, return no chain head found
    if (headersAdded == 0) {
      return AddBlockHeadersResult.noChainHead;
    }
    if (verbose) {
      _log.info(
        'Added $headersAdded headers, new height: ${_bestChainHead.height}, chain work: ${_bestChainHead.chainWork.toRadixString(16)}',
      );
    }
    // if the chain is active, write the headers to file
    if (_activeChain) {
      // write the headers to file
      if (!compareHashes(
        _bestChainHead.header.hash(),
        initialBest.header.hash(),
      )) {
        _blockHeadersFileWriteOrAppend();
      }
    }
    // clean chainheads
    _cleanHeads();
    return AddBlockHeadersResult.success;
  }

  AddBlockFilterHeadersResult addBlockFilterHeaders(
    Uint8List previousFilterHash,
    List<Uint8List> filterHashes,
    Uint8List stopHash,
  ) {
    final initialBest = _bestBlockFilterHead;
    // check previous filter hash
    if (!compareHashes(_bestBlockFilterHead.header, previousFilterHash)) {
      _log.warning(
        'Received block filter header with invalid previous header: ${headerHashNice(_bestBlockFilterHead.header)} != ${headerHashNice(previousFilterHash)}',
      );
      return AddBlockFilterHeadersResult
          .invalidBlockFilterHeader; // abort adding block filter headers
    }
    for (final filterHash in filterHashes) {
      // create header
      final header = BasicBlockFilter.filterHeader(
        filterHash,
        _bestBlockFilterHead.header,
      );
      // create new block filter entry
      final newBlockFilterHead = _makeBlockFilterHeaderEntry(
        header,
        _bestBlockFilterHead,
      );
      // update the best block filter head
      _bestBlockFilterHead = newBlockFilterHead;
    }
    // write the headers to file
    if (!compareHashes(_bestBlockFilterHead.header, initialBest.header)) {
      _blockFilterHeadersFileWriteOrAppend();
    }

    _updateBlockFilterHeaderHeightIndex();
    return AddBlockFilterHeadersResult.success;
  }

  bool hasMinimumChainWork() {
    return _bestChainHead.chainWork >= _minumumChainWork(network);
  }

  Uint8List? blockHashForHeight(int height) {
    if (height < 0 || !_blockHeaderHeightIndex.containsKey(height)) {
      return null; // height out of range or not indexed
    }
    return _blockHeaderHeightIndex[height];
  }

  Uint8List? blockFilterHeaderForHeight(int height) {
    if (height < 0 || !_blockFilterHeaderHeightIndex.containsKey(height)) {
      return null; // height out of range or not indexed
    }
    return _blockFilterHeaderHeightIndex[height];
  }

  void activate() {
    if (_activeChain) {
      throw StateError('Cannot activate already activated chain');
    }
    if (verbose) {
      _log.info(
        'Activating chain with best header: ${headerHashNice(_bestChainHead.header.hash())}',
      );
    }
    // set the status to active
    // this allows writing block headers to file
    _activeChain = true;
    // write the best chain head to file (if it is not already written)
    if (_fileChainHead == null ||
        !compareHashes(
          _fileChainHead!.header.hash(),
          _bestChainHead.header.hash(),
        )) {
      _blockHeadersFileWriteOrAppend();
    }
  }

  void deactivate() {
    if (!_activeChain) {
      throw StateError('Cannot deactivate already deactivated chain');
    }
    _activeChain = false;
  }

  Future<bool> hasValidFilterChain(Block block, int blockHeight) async {
    // get the  current and previous filter header
    if (bestBlockFilterHead.height < blockHeight) {
      _log.warning(
        '_chainManager bestBlockFilterHead height is less than requested block number',
      );
      return false;
    }
    var bfhNode = bestBlockFilterHead;
    while (bfhNode.height > blockHeight) {
      if (bfhNode.previous == null) {
        _log.warning(
          '_chainManager bestBlockFilterHead previous is null while traversing to requested block number',
        );
        return false;
      }
      bfhNode = bfhNode.previous!;
    }
    final currentFilterHeader = bfhNode.header;
    if (bfhNode.previous == null) {
      _log.warning(
        '_chainManager bestBlockFilterHead previous is null for requested block number',
      );
      return false;
    }
    final previousFilterHeader = bfhNode.previous!.header;
    // get the block inputs to create the filter
    final prevOutputScripts = await BasicBlockFilter.prevOutputScripts(
      block,
      BlockDnTxProvider(network),
    );
    // create the block filter
    final blockFilter = BasicBlockFilter(
      block: block,
      prevOutputScripts: prevOutputScripts,
    );
    // verify the filter header
    final expectedFilterHeader = BasicBlockFilter.filterHeader(
      blockFilter.filterHash,
      previousFilterHeader,
    );
    if (!listEquals(expectedFilterHeader, currentFilterHeader)) {
      _log.warning(
        'Block filter header mismatch for block at height $blockHeight: expected ${currentFilterHeader.toHex()}, got ${expectedFilterHeader.toHex()}',
      );
      return false;
    }
    if (verbose) {
      _log.info('Block filter verified for block at height $blockHeight');
    }
    return true;
  }
}
