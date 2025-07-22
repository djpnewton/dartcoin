import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'common.dart';
import 'utils.dart';
import 'block.dart';

final _log = Logger('Chain');

Uint8List reverseHash(Uint8List hash) {
  return Uint8List.fromList(hash.reversed.toList());
}

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

class ChainManager {
  static const int difficultyAdjustmentInterval = 2016;
  static const int maxTimewarp = 600;
  static const int maxReorgDepth = 50;

  final Network network;
  final String blockHeadersFilePath;
  late BlockHeader genesisBlockHeader;
  late ChainEntry bestChainHead;
  List<ChainEntry> chainHeads = [];

  ChainManager({required this.network, required this.blockHeadersFilePath}) {
    genesisBlockHeader = Block.genesisBlock(network).header;
    bestChainHead = _initBestHeader(network);
    chainHeads.add(bestChainHead);
  }

  BigInt _minumumChainWork(Network network) {
    // TODO: update and use the actual minimum chain work for each network
    return switch (network) {
      Network.mainnet => BigInt.parse('0x00'),
      Network.testnet => BigInt.parse('0x00'),
      Network.testnet4 => BigInt.parse('0x00'),
    };
  }

  ChainEntry _initBestHeader(Network network) {
    final genesisBlock = Block.genesisBlock(network);
    // check for block headers file
    final headers = _blockHeadersRead();
    if (headers.isNotEmpty) {
      if (_compareHashes(headers.first.hash(), genesisBlock.header.hash())) {
        ChainEntry? previous;
        ChainEntry? chainHead;
        for (final header in headers) {
          chainHead = _makeChainEntry(header, previous);
          previous = chainHead;
        }
        return chainHead!;
      }
      _log.warning(
        'Genesis block header hash mismatch: ${headers.first.hash().toHex()} != ${genesisBlock.header.hash().toHex()}',
      );
    }
    // if no headers file or mismatch, use genesis block header
    return _makeChainEntry(genesisBlock.header, null);
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

  List<BlockHeader> _blockHeadersRead() {
    final headersFile = File(blockHeadersFilePath);
    if (headersFile.existsSync()) {
      _log.info('Block headers file found: $blockHeadersFilePath');
      final headersJson = headersFile.readAsStringSync();
      final headers = (jsonDecode(headersJson) as List)
          .map(
            (headerData) =>
                BlockHeader.fromBytes((headerData[1] as String).toBytes()),
          )
          .toList();
      _log.info('Loaded ${headers.length} block headers from file');
      return headers;
    }
    return [];
  }

  void _blockHeadersWrite(List<BlockHeader> blockHeaders) {
    final headersFile = File(blockHeadersFilePath);
    final headersJson = JsonEncoder.withIndent('  ').convert(
      blockHeaders
          .map(
            (header) => [
              reverseHash(header.hash()).toHex(),
              header.toBytes().toHex(),
            ],
          )
          .toList(),
    );
    headersFile.writeAsStringSync(headersJson);
    _log.info('Block headers written to file: $blockHeadersFilePath');
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
      bestChainHead,
      bestChainHead.height + 1 < maxReorgDepth ? bestChainHead.height + 1 : maxReorgDepth,
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

  ChainEntry? _findNewChainHead(BlockHeader header) {
    _log.info(
      'Finding new chainhead for header: ${reverseHash(header.hash()).toHex().padLeft(64, '0')} (prev: ${reverseHash(header.previousBlockHeaderHash).toHex().padLeft(64, '0')})',
    );
    // check if the header builds on the best chainhead (should be most common case)
    if (_compareHashes(bestChainHead.header.hash(), header.previousBlockHeaderHash)) {
      return _makeChainEntry(header, bestChainHead);
    }
    // check if the header builds on one of the chainheads
    for (final chainHead in chainHeads) {
      if (_compareHashes(chainHead.header.hash(), header.previousBlockHeaderHash)) {
        return _makeChainEntry(header, chainHead);
      }
    }
    // check if the header is a reorg of one of the heads (up to maxReorgDepth)
    for (final chainHead in chainHeads) {
      if (chainHead.height < bestChainHead.height - maxReorgDepth) continue;
      final initialHeight = chainHead.height;
      ChainEntry? current = chainHead;
      while (current != null &&
          current.height >= 0 &&
          current.height >= initialHeight - maxReorgDepth) {
        if (_compareHashes(
          current.header.hash(),
          header.previousBlockHeaderHash,
        )) {
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
      _log.info(
        'Actual timespan is less than 1/4 of expected: $actualTimespan < ${expectedTimespan ~/ 4}',
      );
      actualTimespan = expectedTimespan ~/ 4;
    }
    if (actualTimespan > expectedTimespan * 4) {
      _log.info(
        'Actual timespan is more than 4x of expected: $actualTimespan > ${expectedTimespan * 4}',
      );
      actualTimespan = expectedTimespan * 4;
    }
    final ratio = actualTimespan / expectedTimespan;
    _log.info(
      'Ratio: $ratio, Actual Timespan: $actualTimespan, Expected Timespan: $expectedTimespan',
    );
    final newTarget =
        (target * BigInt.from(actualTimespan)) ~/ BigInt.from(expectedTimespan);
    final newBits = BlockHeader.targetToBits(newTarget);
    _log.info(
      'Recalculating difficulty: Old Bits: ${currentBits.toRadixString(16)}, New Bits: ${newBits.toRadixString(16)}',
    );
    // check newBits is not greater than the genesis block's nBits
    final genesisTarget = BlockHeader.bitsToTarget(genesisBlockHeader.nBits);
    if (newTarget > genesisTarget) {
      _log.warning(
        'New target is greater than genesis target: $newTarget > $genesisTarget',
      );
      return genesisBlockHeader.nBits;
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
        _log.info(
          'Resetting work required on testnet due to long time since last block: $blockInterval seconds',
        );
        return genesisBlockHeader.nBits; // reset to the first block's nBits
      } else if (newChainHead.previous!.height > 2) {
        // use the last non special minimum difficulty block
        ChainEntry? current = newChainHead.previous;
        while (current != null &&
            (current.height + 1) % difficultyAdjustmentInterval != 0 &&
            current.header.nBits == genesisBlockHeader.nBits) {
          current = current.previous;
        }
        return current?.header.nBits ?? genesisBlockHeader.nBits;
      }
    }
    // otherwise, use the last block's nBits
    return newChainHead.previous!.header.nBits;
  }

  void _updateHeads(ChainEntry newChainHead) {
    // 1) check if the new chainhead can replace one of the existing heads
    var replacedHead = false;
    for (final chainHead in chainHeads) {
      if (_compareHashes(
        chainHead.header.hash(),
        newChainHead.header.previousBlockHeaderHash,
      )) {
        // remove the old chainhead
        chainHeads.remove(chainHead);
        // add the new chainhead
        chainHeads.add(newChainHead);
        // set 'replacedHead' and break
        replacedHead = true;
        break;
      }
    }
    // 2) if the new chainhead does not replace any existing chainhead it must be a reorg so add it as a new chainhead
    if (!replacedHead) {
      chainHeads.add(newChainHead);
    }
    // 3) find the new best chainhead based on chain work (and time created)
    List<ChainEntry> candidates = [];
    for (final chainHead in chainHeads) {
      if (candidates.isEmpty || chainHead.chainWork > candidates.first.chainWork) {
        candidates.clear();
        candidates.add(chainHead);
      } else if (chainHead.chainWork == candidates.first.chainWork) {
        candidates.add(chainHead);
      }
    }
    if (candidates.length == 1) {
      bestChainHead = candidates.first;
    } else {
      // if there are multiple candidates, choose the one with earliest timeCreated
      candidates.sort((a, b) => a.timeCreated.compareTo(b.timeCreated));
      bestChainHead = candidates.first;
    }
  }

  void _cleanHeads() {
    // remove chainheads that are too far behind the best chainhead
    chainHeads.removeWhere((chainHead) => chainHead.height < bestChainHead.height - maxReorgDepth);
  }

  bool addHeaders(List<BlockHeader> headers) {
    final initialBest = bestChainHead;
    for (final header in headers) {
      // create new chainhead from block header
      final newChainHead = _findNewChainHead(header);
      if (newChainHead == null) {
        _log.warning(
          'Received header does not build on (or reorg) any known chainhead',
        );
        return false; // abort adding headers
      }
      final headerHash = newChainHead.header.hash();
      final headerHashReversed = reverseHash(headerHash);
      _log.info(
        'Received header: ${headerHashReversed.toHex().padLeft(64, '0')}, height: ${newChainHead.height}, time: ${newChainHead.header.time - newChainHead.previous!.header.time}s',
      );
      _log.info('header bits:     ${newChainHead.header.nBits.toRadixString(16)}');
      _log.info(
        'header target:   ${BlockHeader.bitsToTarget(newChainHead.header.nBits).toRadixString(16).padLeft(64, '0')}',
      );
      // check the median time past
      if (!_checkMedianTimePast(newChainHead)) {
        return false; // abort adding headers
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
            return false; // abort adding headers
          }
        }
      }
      // get the work required
      final bits = _getNextWork(newChainHead);
      _log.info('Work required:   ${bits.toRadixString(16).padLeft(8, '0')}');
      // check the work
      if (bits != newChainHead.header.nBits) {
        _log.warning(
          'Received header with different nBits: ${newChainHead.header.nBits.toRadixString(16)}, expected: ${bits.toRadixString(16)}',
        );
        return false; // abort adding headers
      }
      final target = BlockHeader.bitsToTarget(bits);
      final headerWork = bytesToBigInt(headerHashReversed);
      if (headerWork > target) {
        _log.warning(
          'Received header with insufficient work: ${headerHashReversed.toHex().padLeft(64, '0')} (needed: ${target.toRadixString(16).padLeft(64, '0')})',
        );
        return false; // abort adding headers
      }
      // update heads
      _updateHeads(newChainHead);
    }
    _log.info(
      'Added ${headers.length} headers, new height: ${bestChainHead.height}, chain work: ${bestChainHead.chainWork.toRadixString(16)}',
    );
    // write the headers to file
    if (!_compareHashes(bestChainHead.header.hash(), initialBest.header.hash())) {
      final blockHeaders = <BlockHeader>[];
      ChainEntry? current = bestChainHead;
      while (current != null) {
        blockHeaders.add(current.header);
        current = current.previous;
      }
      // TODO: change to write only new headers (change file format to CSV for easier appending?)
      _blockHeadersWrite(blockHeaders.reversed.toList());
    }
    // clean chainheads
    _cleanHeads();
    return true;
  }
}
