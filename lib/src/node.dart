import 'dart:io';

import 'package:logging/logging.dart';
import 'package:collection/collection.dart';

import 'common.dart';
import 'chain.dart';
import 'peer.dart';

final _log = Logger('Node');

class Node {
  final Network network;
  final List<Peer> _peers = [];
  late final String _dataDir;
  late final ChainManager _chainManager;
  final bool verbose;
  bool _shuttingDown = false;

  Node({required this.network, String? dataDir, this.verbose = false}) {
    // initialize the data directory
    _dataDir = _initDataDir(network, dataDir: dataDir);
    // initialize the chain manager
    _chainManager = ChainManager(
      network: network,
      blockHeadersFilePath: blockHeadersFilePath,
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
        if (reason == PeerStatusChangeReason.invalidHeader) {
          _log.warning(
            'Invalid headers received from peer ${peer.ip}:${peer.port}',
          );
          if (!_shuttingDown) {
            peer.disconnect();
            _peers.remove(peer);
          }
          // TODO: connect to another peer
          return;
        } else if (prevStatus == PeerStatus.headersSyncing &&
            reason == PeerStatusChangeReason.noChainHead) {
          if (verbose) {
            _log.info(
              'Peer ${peer.ip}:${peer.port} headers syncing, but no chain head found',
            );
          }
          if (!_shuttingDown) {
            peer.disconnect();
            _peers.remove(peer);
          }
          // TODO: connect to another peer
          return;
        }
        // return chain to headerSync status
        if (_chainManager.status == ChainStatus.active) {
          _chainManager.sync();
        }
        // Start syncing headers
        peer.sync(_chainManager);
        break;
      case PeerStatus.headersSyncing:
        break;
      case PeerStatus.headersSynced:
        // check if sufficient chain work
        if (_chainManager.hasMinimumChainWork()) {
          if (verbose) {
            _log.info(
              'chain headers from ${peer.ip}:${peer.port} has sufficient chain work',
            );
          }
          // activate chain (and write to disk)
          _chainManager.activate();
          // TODO:
          //  - add new peers and wait for txs/blocks
        } else {
          _log.warning(
            'Insufficient chain work from peer headers ${peer.ip}:${peer.port}',
          );
          if (!_shuttingDown) {
            peer.disconnect();
            _peers.remove(peer);
          }
          // TODO:
          //  - connect to another peer
          //  - reset the chain
        }
        break;
      case PeerStatus.disconnected:
        if (!_shuttingDown) {
          _peers.remove(peer);
        }
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
      verbose: verbose,
    );
    _peers.add(peer);
    peer.connect();
  }

  void shutdown() {
    _shuttingDown = true;
    if (verbose) {
      _log.info('Shutting down node...');
    }
    for (final peer in _peers) {
      peer.disconnect();
    }
    _peers.clear();
    _shuttingDown = false;
    // TODO: in the future, we might want to save the chain state
    //  and save peers to disk
  }

  int blockCount() {
    return _chainManager.bestChainHead.height;
  }

  String bestBlockHash() {
    return headerHashNice(_chainManager.bestChainHead.header.hash());
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
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }
}
