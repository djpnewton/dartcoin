import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'logc.dart';
import 'common.dart';
import 'utils.dart';
import 'chain.dart';
import 'chain_store.dart';
import 'block.dart';
import 'peer.dart';
import 'block_filter.dart';
import 'wallet.dart';

final _log = ColorLogger('Node');

class Node {
  final Network network;
  final List<Peer> _peers = [];
  late final String _dataDir;
  late final ChainManager _chainManager;
  final bool verbose;
  final bool syncBlockHeaders;
  final bool syncBlockFilterHeaders;
  final Wallet? wallet;
  late final int? _startBlock = wallet?.birthdayBlock;

  int _requestingBestBlockNumber = 0;
  Uint8List _requestingBestBlockHash = Uint8List(0);
  Uint8List _requestingBlockFiltersCurrentTargetHash = Uint8List(0);
  int _requestingBlockFiltersCurrentTargetHeight = 0;

  Node({
    required this.network,
    String? dataDir,
    this.verbose = false,
    this.syncBlockHeaders = true,
    this.syncBlockFilterHeaders = true,
    this.wallet,
  }) {
    assert(
      !(syncBlockFilterHeaders && !syncBlockHeaders),
      'Cannot sync block filter headers without syncing block headers',
    );
    assert(
      !(wallet != null && wallet!.addresses.isNotEmpty && !syncBlockFilterHeaders),
      'Cannot scan addresses without syncing block filter headers',
    );
    // initialize the data directory
    _dataDir = _initDataDir(network, dataDir: dataDir);
    // initialize the chain manager
    _chainManager = ChainManager(
      network: network,
      blockHeadersFilePath: blockHeadersFilePath,
      blockFilterHeadersFilePath: blockFilterHeadersFilePath,
      blockFiltersFilePath: blockFiltersFilePath,
      verbose: verbose,
    );
  }

  String _initDataDir(Network network, {String? dataDir}) {
    if (dataDir == null) {
      final baseDir = '.';
      final dirName = switch (network) {
        Network.mainnet => '.dartcoin/mainnet',
        Network.testnet => '.dartcoin/testnet',
        Network.testnet4 => '.dartcoin/testnet4',
        Network.regtest => '.dartcoin/regtest',
      };
      dataDir = '$baseDir/$dirName';
    }
    Directory(dataDir).createSync(recursive: true);
    if (verbose) {
      _log.info('Data directory initialized at: $dataDir');
    }
    return dataDir;
  }

  String get blockHeadersFilePath {
    return '$_dataDir/headers.csv';
  }

  String get blockFilterHeadersFilePath {
    return '$_dataDir/filter_headers.csv';
  }

  String get blockFiltersFilePath {
    return '$_dataDir/filters.csv';
  }

  void _peerStatusChange(
    Peer peer,
    PeerStatus status,
    PeerStatus prevStatus, {
    PeerStatusChangeReason? reason,
  }) {
    if (verbose) {
      _log.info(
        'Peer ${peer.ip}:${peer.port} status changed to $status${reason != null ? ' due to $reason' : ''}',
      );
    }
    switch (status) {
      case PeerStatus.connected:
        break;
      case PeerStatus.handshakeComplete:
        if (reason == PeerStatusChangeReason.invalidBlockHeader) {
          _log.warning(
            'Invalid headers received from peer ${peer.ip}:${peer.port}',
          );
          peer.disconnect();
          _peers.remove(peer);
          // TODO: connect to another peer
          return;
        } else if (prevStatus == PeerStatus.blockHeadersSyncing &&
            reason == PeerStatusChangeReason.noChainHead) {
          if (verbose) {
            _log.info(
              'Peer ${peer.ip}:${peer.port} headers syncing, but no chain head found',
            );
          }
          peer.disconnect();
          _peers.remove(peer);
          // TODO: connect to another peer
          return;
        }
        // return chain to headerSync status
        if (_chainManager.activeChain) {
          _chainManager.deactivate();
        }
        // check if peer supports block filters
        if (verbose) {
          _log.info(
            'Peer compact filter support: ${peer.nodeCompactFiltersSupport}',
          );
        }
        if (!peer.nodeCompactFiltersSupport) {
          _log.warning(
            'Peer ${peer.ip}:${peer.port} does not support compact block filters',
          );
          break;
        }
        // Start syncing headers
        if (syncBlockHeaders) {
          peer.syncBlockHeaders(_chainManager);
        }
        break;
      case PeerStatus.requestAddrs:
        break;
      case PeerStatus.blockHeadersSyncing:
        break;
      case PeerStatus.blockHeadersSynced:
        // check if sufficient chain work
        if (_chainManager.hasMinimumChainWork()) {
          if (verbose) {
            _log.info(
              'chain headers from ${peer.ip}:${peer.port} has sufficient chain work',
            );
          }
          // activate chain (and write to disk)
          if (!_chainManager.activeChain) {
            _chainManager.activate();
          }
          // start syncing block filters
          if (syncBlockFilterHeaders) {
            peer.syncBlockFilterHeaders(_chainManager);
          }
          // TODO:
          //  - add new peers and wait for txs/blocks
        } else {
          _log.warning(
            'Insufficient chain work from peer headers ${peer.ip}:${peer.port}',
          );
          peer.disconnect();
          _peers.remove(peer);
          // TODO:
          //  - connect to another peer
          //  - reset the chain
        }
        break;
      case PeerStatus.blockFilterHeaderSyncing:
        break;
      case PeerStatus.blockFilterHeaderSynced:
        if (_chainManager.bestChainHead.height !=
            _chainManager.bestBlockFilterHead.height) {
          _log.warning(
            '_chainManager Block filter header height does not match block header height',
          );
          return;
        }
        // start getting latest block
        _requestingBestBlockHash = _chainManager.bestChainHead.header.hash();
        _requestingBestBlockNumber = _chainManager.bestChainHead.height;
        peer.requestBlocks([
          _requestingBestBlockHash,
        ], PeerStatus.blockFilterGetLatestBlock);
        break;
      case PeerStatus.blockFilterGetLatestBlock:
        break;
      case PeerStatus.blockFilterSyncing:
        break;
      case PeerStatus.blockFilterSynced:
        break;
      case PeerStatus.getInterestingBlocks:
        break;
      case PeerStatus.disconnected:
        _peers.remove(peer);
        break;
      case PeerStatus.connecting:
        break;
    }
  }

  Future<void> _peerBlockReceived(Peer peer, Block block) async {
    if (verbose) {
      _log.info(
        'Block received from peer ${peer.ip}:${peer.port}, block hash: ${block.header.hashNice()}',
      );
    }
    if (peer.status == PeerStatus.blockFilterGetLatestBlock) {
      // check if this is the requested block
      if (listEquals(block.header.hash(), _requestingBestBlockHash)) {
        if (verbose) {
          _log.info(
            'Received requested best block ${block.header.hashNice()} at height $_requestingBestBlockNumber from peer ${peer.ip}:${peer.port}',
          );
        }
        if (await _chainManager.hasValidFilterChain(
          block,
          _requestingBestBlockNumber,
        )) {
          if (_startBlock == null) return;

          // 1) Replay already-stored filters so interestingBlockHashes is populated
          //    for blocks we downloaded on a previous run.
          _chainManager.replayStoredFilters(
            _startBlock,
            (height, blockHash, filterBytes) {
              final filter =
                  BasicBlockFilter.fromBytes(filterBytes: filterBytes);
              wallet?.processBlockFilter(
                blockHash,
                filter,
                network,
                verbose: verbose,
              );
            },
          );

          // 2) Decide where to resume downloading.
          final resumeFrom = (_chainManager.maxStoredFilterHeight != null)
              ? _chainManager.maxStoredFilterHeight! + 1
              : _startBlock;

          if (resumeFrom > _chainManager.bestChainHead.height) {
            // All filters already stored – request interesting blocks directly.
            if (verbose) {
              _log.info(
                'All block filters already stored up to height ${_chainManager.maxStoredFilterHeight}, requesting interesting blocks',
              );
            }
            final interesting = wallet?.interestingBlockHashes ?? [];
            if (interesting.isNotEmpty) {
              peer.requestBlocks(
                interesting,
                PeerStatus.getInterestingBlocks,
              );
            }
            return;
          }

          // 3) Request remaining filters from resumeFrom.
          if (verbose) {
            _log.info(
              'Resuming block filter download from height $resumeFrom (stored up to ${_chainManager.maxStoredFilterHeight ?? 'none'})',
            );
          }
          final targetHeight =
              _chainManager.bestChainHead.height < resumeFrom + 500
              ? _chainManager.bestChainHead.height
              : resumeFrom + 500;
          final targetHash = _chainManager.bestChainHead
              .getAt(targetHeight)
              .header
              .hash();
          _requestingBlockFiltersCurrentTargetHash = targetHash;
          _requestingBlockFiltersCurrentTargetHeight = targetHeight;
          peer.syncBlockFilters(resumeFrom, targetHash);
        }
      }
    } else if (peer.status == PeerStatus.getInterestingBlocks) {
      if (verbose) {
        _log.info(
          'Received block ${block.header.hashNice()} from peer ${peer.ip}:${peer.port}, delegating to wallet',
        );
      }
      await wallet?.processBlock(block, network, verbose: verbose);
    }
  }

  void _peerBlockFilterReceived(
    Peer peer,
    Uint8List blockHash,
    BasicBlockFilter filter,
  ) {
    if (verbose) {
      _log.info('Block filter received from peer ${peer.ip}:${peer.port}');
    }
    wallet?.processBlockFilter(blockHash, filter, network, verbose: verbose);

    if (peer.status == PeerStatus.blockFilterSyncing) {
      // check if we need to request more filters
      if (compareHashes(blockHash, _requestingBlockFiltersCurrentTargetHash)) {
        if (verbose) {
          _log.info(
            'Reached target block filter hash: ${blockHash.reverse().toHex()}',
          );
        }
        _chainManager.flushBlockFilters();
        final startHeight = _requestingBlockFiltersCurrentTargetHeight + 1;
        final targetHeight =
            _chainManager.bestChainHead.height <
                _requestingBlockFiltersCurrentTargetHeight + 500
            ? _chainManager.bestChainHead.height
            : _requestingBlockFiltersCurrentTargetHeight + 500;
        final targetHash = _chainManager.bestChainHead
            .getAt(targetHeight)
            .header
            .hash();
        _requestingBlockFiltersCurrentTargetHash = targetHash;
        if (targetHeight == _chainManager.bestChainHead.height) {
          if (verbose) {
            _log.info('Completed block filter sync at height $targetHeight');
          }
          final interestingBlockHashes = wallet?.interestingBlockHashes ?? [];
          for (final hash in interestingBlockHashes) {
            _log.info(
              'Interesting block hash: ${hash.reverse().toHex()}',
              color: LogColor.brightMagenta,
            );
          }
          if (interestingBlockHashes.isNotEmpty) {
            peer.requestBlocks(
              interestingBlockHashes,
              PeerStatus.getInterestingBlocks,
            );
          }
          return;
        }
        if (verbose) {
          _log.info(
            'Requesting more block filters from height $_requestingBlockFiltersCurrentTargetHeight, target hash: ${targetHash.reverse().toHex()}',
          );
        }
        _requestingBlockFiltersCurrentTargetHeight = targetHeight;
        peer.syncBlockFilters(startHeight, targetHash);
      }
    }
  }

  void connect({required String ip, required int port}) async {
    final peer = Peer(
      ip: ip,
      port: port,
      network: network,
      onStatusChange: _peerStatusChange,
      onBlockReceived: _peerBlockReceived,
      onBlockFilterReceived: _peerBlockFilterReceived,
      onAddresses: null,
      verbose: verbose,
    );
    _peers.add(peer);
    peer.connect();
  }

  void add({required Peer peer}) {
    if (peer.network != network) {
      throw ArgumentError(
        'Peer network ${peer.network} does not match node network $network',
      );
    }
    if (peer.status != PeerStatus.handshakeComplete) {
      throw ArgumentError(
        'Peer must be in handshakeComplete status to be added to node',
      );
    }
    peer.setPeerStatusChangeCallback(_peerStatusChange);
    peer.setAddressesCallback(null);
    peer.setBlockReceivedCallback(_peerBlockReceived);
    peer.setBlockFilterReceivedCallback(_peerBlockFilterReceived);
    _peers.add(peer);
    // manually trigger status change to handshakeComplete
    _peerStatusChange(peer, PeerStatus.handshakeComplete, peer.status);
  }

  void shutdown() {
    if (verbose) {
      _log.info('Shutting down node...');
    }
    for (final peer in _peers.toList()) {
      peer.disconnect();
    }
    _peers.clear();
    // TODO: in the future, we might want to save the chain state
    //  and save peers to disk
  }

  int blockCount() {
    return _chainManager.bestChainHead.height;
  }

  String bestBlockHash() {
    return _chainManager.bestChainHead.header.hashNice();
  }

  String? blockHashForHeight(int height) {
    final hash = _chainManager.blockHashForHeight(height);
    if (hash == null) {
      return null; // height out of range or not indexed
    }
    return headerHashNice(hash);
  }

  List<ChainEntry> chainHeads() {
    return _chainManager.chainHeads;
  }

  int blockHeaderCount() {
    return _chainManager.bestBlockFilterHead.height;
  }

  String bestBlockFilterHeader() {
    return _chainManager.bestBlockFilterHead.header.reverse().toHex();
  }

  int blockFilterHeaderCount() {
    return _chainManager.bestBlockFilterHead.height;
  }

  String? blockFilterHeaderForHeight(int height) {
    final header = _chainManager.blockFilterHeaderForHeight(height);
    if (header == null) {
      return null; // height out of range or not indexed
    }
    return header.reverse().toHex();
  }

  Future<bool> waitForBlockCount(
    int count, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      if (blockCount() >= count) {
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<bool> waitForBlockFilterHeaderCount(
    int count, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      if (_chainManager.bestBlockFilterHead.height >= count) {
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<bool> waitForPeerStatus(
    String ip,
    int port,
    PeerStatus status, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      final peer = _peers.firstWhereOrNull((p) => p.ip == ip && p.port == port);
      if (peer?.status == status) {
        return true;
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
  }

  Future<bool> waitForHashInChainHeads(
    String hash, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      for (final head in _chainManager.chainHeads) {
        if (headerHashNice(head.header.hash()) == hash) {
          return true;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }
}
