import 'dart:async';
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

export 'node_factory_stub.dart'
    if (dart.library.io) 'node_native.dart'
    if (dart.library.js_interop) 'node_web.dart'
    show defaultNodeFactory;

final _log = ColorLogger('Node');

/// Factory that creates a platform-appropriate [Node] with bundled stores.
///
/// [storageLocation] is a file-system directory path on native platforms and
/// an IndexedDB database-name prefix on web.  When omitted a sensible default
/// is derived from the [network] name.
typedef NodeFactory =
    Node Function({
      required Network network,
      String? storageLocation,
      bool verbose,
      bool syncBlockHeaders,
      bool syncBlockFilterHeaders,
      Wallet? wallet,
      required TxProvider txProvider,
    });

class Node {
  final Network network;
  final List<Peer> _peers = [];
  late final ChainManager _chainManager;
  late final BlockStore _blockStore;
  final bool verbose;
  final bool syncBlockHeaders;
  final bool syncBlockFilterHeaders;
  final Wallet? wallet;
  late final int? _startBlock = wallet?.birthdayBlock;

  int _requestingBestBlockNumber = 0;
  Uint8List _requestingBestBlockHash = Uint8List(0);
  Uint8List _requestingBlockFiltersCurrentTargetHash = Uint8List(0);
  int _requestingBlockFiltersCurrentTargetHeight = 0;

  /// Blocks received out-of-order while in [PeerStatus.getInterestingBlocks].
  final Map<String, Block> _pendingInterestingBlocks = {};
  int _interestingBlocksProcessedCount = 0;
  bool _isDrainingInterestingBlocks = false;

  /// Timeout guard for [PeerStatus.blockFilterGetLatestBlock].
  Timer? _latestBlockTimer;

  Node({
    required this.network,
    this.verbose = false,
    this.syncBlockHeaders = true,
    this.syncBlockFilterHeaders = true,
    this.wallet,
    required TxProvider txProvider,
    required ChainStore blockHeadersChainStore,
    required ChainStore blockFilterHeadersChainStore,
    required ChainStore blockFiltersChainStore,
    required BlockStore blockStore,
  }) {
    if (syncBlockFilterHeaders && !syncBlockHeaders) {
      throw ArgumentError(
        'Cannot sync block filter headers without syncing block headers',
      );
    }
    if (wallet != null &&
        wallet!.addresses.isNotEmpty &&
        !syncBlockFilterHeaders) {
      throw ArgumentError(
        'Cannot scan addresses without syncing block filter headers',
      );
    }
    _blockStore = blockStore;
    _chainManager = ChainManager(
      network: network,
      blockHeadersChainStore: blockHeadersChainStore,
      blockFilterHeadersChainStore: blockFilterHeadersChainStore,
      blockFiltersChainStore: blockFiltersChainStore,
      txProvider: txProvider,
      verbose: verbose,
    );
  }

  Future<void> init() async {
    await _blockStore.init();
    await _chainManager.init();
  }

  Future<void> _peerStatusChange(
    Peer peer,
    PeerStatus status,
    PeerStatus prevStatus, {
    PeerStatusChangeReason? reason,
  }) async {
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
            await _chainManager.activate();
          }
          // start syncing block filters
          if (syncBlockFilterHeaders) {
            // Only let one peer sync filter headers at a time.  If another
            // peer is already in the syncing state, both would send independent
            // GetCfHeaders requests for the same startHeight.  When the second
            // response arrives it would appear as an invalid previousFilterHash
            // because the first peer already advanced _bestBlockFilterHead.
            final alreadySyncing = _peers.any(
              (p) => p.status == PeerStatus.blockFilterHeaderSyncing,
            );
            if (!alreadySyncing) {
              peer.syncBlockFilterHeaders(_chainManager);
            } else if (verbose) {
              _log.info(
                'Peer ${peer.ip}:${peer.port} ready but another peer is already '
                'syncing filter headers; will start after that peer finishes',
              );
            }
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
          // More block headers arrived during the sync; do another round.
          if (syncBlockFilterHeaders) {
            // Guard: same as above – only one peer syncs at a time.
            final alreadySyncing = _peers.any(
              (p) =>
                  p != peer && p.status == PeerStatus.blockFilterHeaderSyncing,
            );
            if (!alreadySyncing) {
              peer.syncBlockFilterHeaders(_chainManager);
            }
          }
          break;
        }
        // start getting latest block
        _requestingBestBlockHash = _chainManager.bestChainHead.header.hash();
        _requestingBestBlockNumber = _chainManager.bestChainHead.height;
        peer.requestBlocks([
          _requestingBestBlockHash,
        ], PeerStatus.blockFilterGetLatestBlock);
        // Arm a timeout – if the peer never sends the block we skip
        // validation and proceed directly to filter sync.
        _latestBlockTimer?.cancel();
        _latestBlockTimer = Timer(const Duration(seconds: 30), () {
          if (peer.status == PeerStatus.blockFilterGetLatestBlock) {
            //TODO: disconnect and try another peer instead of skipping validation
            _log.warning(
              'Timeout waiting for best block from ${peer.ip}:${peer.port}; '
              'skipping filter-chain validation and proceeding',
            );
            _beginFilterSync(peer);
          }
        });
        break;
      case PeerStatus.blockFilterGetLatestBlock:
        break;
      case PeerStatus.blockFilterSyncing:
        break;
      case PeerStatus.blockFilterSynced:
        break;
      case PeerStatus.getInterestingBlocks:
        // Reset ordering state whenever a new batch of interesting blocks is requested.
        _pendingInterestingBlocks.clear();
        _interestingBlocksProcessedCount = 0;
        _isDrainingInterestingBlocks = false;
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
          _latestBlockTimer?.cancel();
          _latestBlockTimer = null;
          await _beginFilterSync(peer);
        }
      }
    } else if (peer.status == PeerStatus.getInterestingBlocks) {
      // Buffer the block and process in interestingBlockHashes (height) order.
      _pendingInterestingBlocks[block.header.hash().toHex()] = block;

      // Guard against re-entrancy: if an await inside the loop below suspends
      // this function, a newly arrived block will be buffered above and the
      // already-running loop will pick it up on its next iteration.
      if (_isDrainingInterestingBlocks) return;
      _isDrainingInterestingBlocks = true;
      try {
        final ordered = wallet?.interestingBlockHashes ?? [];
        while (_interestingBlocksProcessedCount < ordered.length) {
          final nextHash = ordered[_interestingBlocksProcessedCount];
          final nextBlock = _pendingInterestingBlocks[nextHash.toHex()];
          if (nextBlock == null) break; // not yet received
          _pendingInterestingBlocks.remove(nextHash.toHex());
          _interestingBlocksProcessedCount++;
          final startTime = DateTime.now();
          if (verbose) {
            _log.info(
              'Processing interesting block ${nextBlock.header.hashNice()} ($_interestingBlocksProcessedCount/${ordered.length}) from peer ${peer.ip}:${peer.port}',
              color: LogColor.brightCyan,
            );
          }
          await wallet?.processBlock(nextBlock, network, verbose: verbose);
          if (verbose) {
            _log.info(
              'Finished processing interesting block ${nextBlock.header.hashNice()} ($_interestingBlocksProcessedCount/${ordered.length}) from peer ${peer.ip}:${peer.port}',
              color: LogColor.brightCyan,
            );
            _log.info(
              'Time since starting processing block: ${DateTime.now().difference(startTime)}',
            );
          }
        }
      } finally {
        _isDrainingInterestingBlocks = false;
      }
    }
  }

  /// Replay stored filters, then either request interesting blocks (if all
  /// filters are already downloaded) or kick off the next filter batch.
  /// Called both on successful filter-chain validation and on timeout.
  Future<void> _beginFilterSync(Peer peer) async {
    if (_startBlock == null) return;

    // 1) Replay already-stored filters so interestingBlockHashes is populated
    //    for blocks we downloaded on a previous run.
    await _chainManager.replayStoredFilters(_startBlock, (
      height,
      blockHash,
      filterBytes,
    ) {
      final filter = BasicBlockFilter.fromBytes(filterBytes: filterBytes);
      wallet?.processBlockFilter(blockHash, filter, network, verbose: verbose);
    });

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
        peer.requestBlocks(interesting, PeerStatus.getInterestingBlocks);
      }
      return;
    }

    // 3) Request remaining filters from resumeFrom.
    if (verbose) {
      _log.info(
        'Resuming block filter download from height $resumeFrom (stored up to ${_chainManager.maxStoredFilterHeight ?? 'none'})',
      );
    }
    final targetHeight = _chainManager.bestChainHead.height < resumeFrom + 500
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

  Future<void> _peerBlockFilterReceived(
    Peer peer,
    Uint8List blockHash,
    BasicBlockFilter filter,
  ) async {
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
        await _chainManager.flushBlockFilters();
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
      blockStore: _blockStore,
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
    peer.setBlockStoreCallback(_blockStore);
    _peers.add(peer);
    // manually trigger status change to handshakeComplete
    _peerStatusChange(peer, PeerStatus.handshakeComplete, peer.status);
  }

  void shutdown() {
    if (verbose) {
      _log.info('Shutting down node...');
    }
    _latestBlockTimer?.cancel();
    _latestBlockTimer = null;
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

  int? blockHeightForHash(String hash) {
    return _chainManager.blockHeightForHash(hash.toBytes().reverse());
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

  int blockFilterCount() {
    return _chainManager.maxStoredFilterHeight ?? 0;
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
    Duration timeout = const Duration(seconds: 10),
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
    Duration timeout = const Duration(seconds: 10),
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
    Duration timeout = const Duration(seconds: 10),
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
    Duration timeout = const Duration(seconds: 10),
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
