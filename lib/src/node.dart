import 'dart:io';

import 'package:logging/logging.dart';
import 'package:collection/collection.dart';

import 'common.dart';
import 'utils.dart';
import 'chain.dart';
import 'chain_store.dart';
import 'block.dart';
import 'peer.dart';

final _log = Logger('Node');

class Node {
  final Network network;
  final List<Peer> _peers = [];
  late final String _dataDir;
  late final ChainManager _chainManager;
  final bool verbose;
  final bool syncBlockHeaders;
  final bool syncBlockFilterHeaders;

  Node({
    required this.network,
    String? dataDir,
    this.verbose = false,
    this.syncBlockHeaders = true,
    this.syncBlockFilterHeaders = true,
  }) {
    // initialize the data directory
    _dataDir = _initDataDir(network, dataDir: dataDir);
    // initialize the chain manager
    _chainManager = ChainManager(
      network: network,
      blockHeadersFilePath: blockHeadersFilePath,
      blockFilterHeadersFilePath: blockFilterHeadersFilePath,
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
        if (!_chainManager.hasValidFilterChain()) {
          _log.warning(
            'Invalid block filter headers from peer ${peer.ip}:${peer.port}',
          );
          peer.disconnect();
          _peers.remove(peer);
          // TODO:
          //  - connect to another peer
          //  - reset the chain
        }
        break;
      case PeerStatus.disconnected:
        _peers.remove(peer);
        break;
      case PeerStatus.connecting:
        break;
    }
  }

  void connect({required String ip, required int port}) async {
    final peer = Peer(
      ip: ip,
      port: port,
      network: network,
      onStatusChange: _peerStatusChange,
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
