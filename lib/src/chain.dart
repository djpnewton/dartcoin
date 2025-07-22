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
  ChainEntry({required this.height, required this.header, super.previous});
}

class ChainManager {
  static const int difficultyAdjustmentInterval = 2016;
  static const int maxTimewarp = 600;
  static const int maxReorgDepth = 5;

  final Network network;
  final String blockHeadersFilePath;
  late BlockHeader genesisBlockHeader;
  late ChainEntry best;
  List<ChainEntry> heads = [];

  ChainManager({required this.network, required this.blockHeadersFilePath}) {
    genesisBlockHeader = Block.genesisBlock(network).header;
    best = _initBestHeader(network);
    heads.add(best);
  }

  ChainEntry _initBestHeader(Network network) {
    final genesisBlock = Block.genesisBlock(network);
    // check for block headers file
    final headers = _blockHeadersRead();
    if (headers.isNotEmpty) {
      if (headers.first.hash().toHex() == genesisBlock.header.hash().toHex()) {
        ChainEntry? previous;
        ChainEntry head = ChainEntry(
          height: 0,
          header: headers.first,
          previous: null,
        );
        for (final header in headers) {
          head = ChainEntry(
            height: (previous?.height ?? -1) + 1,
            header: header,
            previous: previous,
          );
          previous = head;
        }
        return head;
      }
      _log.warning(
        'Genesis block header hash mismatch: ${headers.first.hash().toHex()} != ${genesisBlock.header.hash().toHex()}',
      );
    }
    // if no headers file or mismatch, use genesis block header
    return ChainEntry(height: 0, header: genesisBlock.header, previous: null);
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

  List<BlockHeader> blockHeadersTake(int count) {
    final headers = <BlockHeader>[];
    var current = best;
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

  BlockHeader blockHeaderGet(int height) {
    if (height < 0 || height > best.height) {
      throw RangeError('Height $height is out of range (0-${best.height})');
    }
    var current = best;
    while (current.height > height) {
      current = current.previous!;
    }
    return current.header;
  }

  bool _checkMedianTimePast(BlockHeader header) {
    // block time must be greater then the median time of the last 11 blocks
    if (best.height + 1 < 11) {
      return true; // not enough headers to check median time
    }
    final last11Headers = blockHeadersTake(11);
    last11Headers.sort((a, b) => a.time.compareTo(b.time));
    final medianTime = last11Headers[5].time; // 6th element is the median
    if (header.time <= medianTime) {
      _log.warning(
        'Received header with invalid timestamp: ${header.time}, median time: $medianTime',
      );
      return false;
    }
    return true;
  }

  int _calcNextWorkRequired(BlockHeader header) {
    // convert bits to target
    var currentBits = best.header.nBits;
    if (network == Network.testnet4) {
      // bip 94 rule on testnet4
      currentBits = blockHeaderGet(
        best.height - (difficultyAdjustmentInterval - 1),
      ).nBits;
    }
    final target = BlockHeader.bitsToTarget(currentBits);
    // recalculate the difficulty
    var actualTimespan =
        best.header.time -
        blockHeaderGet(best.height - (difficultyAdjustmentInterval - 1)).time;
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

  int _getWork(BlockHeader header) {
    // calculate new work on new epoch
    if ((best.height + 1) % difficultyAdjustmentInterval == 0) {
      return _calcNextWorkRequired(header);
    }
    // reset the work required on testnet if the time between blocks is more than 20 minutes
    if (network == Network.testnet || network == Network.testnet4) {
      final lastTime = best.header.time;
      const resetTime = 20 * 60; // 20 minutes in seconds
      var blockInterval = header.time - lastTime;
      if (blockInterval > resetTime) {
        _log.info(
          'Resetting work required on testnet due to long time since last block: $blockInterval seconds',
        );
        return genesisBlockHeader.nBits; // reset to the first block's nBits
      } else if (best.height > 2) {
        // use the last non special minimum difficulty block
        ChainEntry? current = best;
        while (current != null &&
            (current.height + 1) % difficultyAdjustmentInterval != 0 &&
            current.header.nBits == genesisBlockHeader.nBits) {
          current = current.previous;
        }
        return current?.header.nBits ?? genesisBlockHeader.nBits;
      }
    }
    // otherwise, use the last block's nBits
    return best.header.nBits;
  }

  bool addHeaders(List<BlockHeader> headers) {
    for (final header in headers) {
      final headerHash = header.hash();
      final headerHashReversed = reverseHash(headerHash);
      _log.info(
        'Received header: ${headerHashReversed.toHex().padLeft(64, '0')}, height: ${best.height}, time: ${header.time - best.header.time}s',
      );
      _log.info('header bits:     ${header.nBits.toRadixString(16)}');
      _log.info(
        'header target:   ${BlockHeader.bitsToTarget(header.nBits).toRadixString(16).padLeft(64, '0')}',
      );

      //TODO: deal with reorgs

      // check the previous block header hash
      if (best.header.hash().toHex() !=
          header.previousBlockHeaderHash.toHex()) {
        _log.warning(
          'Received header with previous hash mismatch: ${reverseHash(header.previousBlockHeaderHash).toHex().padLeft(64, '0')}, expected: ${reverseHash(best.header.hash()).toHex().padLeft(64, '0')}',
        );
        return false; // abort adding headers
      }
      // check the median time past
      if (!_checkMedianTimePast(header)) {
        return false; // abort adding headers
      }
      // check testnet4 timewarp rule (bip 94)
      if (network == Network.testnet4) {
        if ((best.height + 1) % difficultyAdjustmentInterval == 0 &&
            best.height > 0) {
          if (header.time < best.header.time - maxTimewarp) {
            _log.warning(
              'Received header with invalid time: ${header.time}, expected greater then or equal to ${best.header.time - maxTimewarp}',
            );
            return false; // abort adding headers
          }
        }
      }
      // get the work required
      final bits = _getWork(header);
      _log.info('Work required:   ${bits.toRadixString(16).padLeft(8, '0')}');
      // check the work
      if (bits != header.nBits) {
        _log.warning(
          'Received header with different nBits: ${header.nBits.toRadixString(16)}, expected: ${bits.toRadixString(16)}',
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
      // set new best
      best = ChainEntry(
        height: best.height + 1,
        header: header,
        previous: best,
      );
    }
    _log.info('Added ${headers.length} headers, height: ${best.height}');
    // write the headers to file
    final blockHeaders = <BlockHeader>[];
    ChainEntry? current = best;
    while (current != null) {
      blockHeaders.add(current.header);
      current = current.previous;
    }
    // TODO: change to write only new headers (change file format to CSV for easier appending?)
    _blockHeadersWrite(blockHeaders.reversed.toList());
    return true;
  }
}
