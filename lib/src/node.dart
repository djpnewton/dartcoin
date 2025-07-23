import 'dart:io';

import 'package:logging/logging.dart';

import 'common.dart';
import 'chain.dart';
import 'peer.dart';

final _log = Logger('Node');

class Node {
  final Network network;
  final List<Peer> _peers = [];
  late final String _dataDir;
  late final ChainManager _chainManager;

  Node({required this.network}) {
    // initialize the data directory
    _dataDir = initDataDir(network);
    // initialize the chain manager
    _chainManager = ChainManager(
      network: network,
      blockHeadersFilePath: blockHeadersFilePath,
    );
  }

  String initDataDir(Network network) {
    final baseDir = '.';
    final dirName = switch (network) {
      Network.mainnet => '.dartcoin/mainnet',
      Network.testnet => '.dartcoin/testnet',
      Network.testnet4 => '.dartcoin/testnet4',
    };
    final dataDir = '$baseDir/$dirName';
    Directory(dataDir).createSync(recursive: true);
    _log.info('Data directory initialized at: $dataDir');
    return dataDir;
  }

  String get blockHeadersFilePath {
    return '$_dataDir/headers.csv';
  }

  void _peerStatusChange(
    Peer peer,
    PeerStatus status, {
    PeerStatusChangeReason? reason,
  }) {
    _log.info(
      'Peer ${peer.ip}:${peer.port} status changed to $status${reason != null ? ' due to $reason' : ''}',
    );
    switch (status) {
      case PeerStatus.connected:
        break;
      case PeerStatus.handshakeComplete:
        if (reason == PeerStatusChangeReason.invalidHeaders) {
          _log.warning(
            'Invalid headers received from peer ${peer.ip}:${peer.port}',
          );
          peer.disconnect();
          _peers.remove(peer);
          // TODO: connect to another peer
          return;
        }
        // Start syncing headers
        peer.sync(_chainManager);
        break;
      case PeerStatus.headersSyncing:
        break;
      case PeerStatus.headersSynced:
        // check if sufficient chain work
        if (_chainManager.hasMinimumChainWork()) {
          _log.info(
            'chain headers from ${peer.ip}:${peer.port} has sufficient chain work',
          );
          // activate chain (and write to disk)
          _chainManager.activate();
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
    );
    _peers.add(peer);
    peer.connect();
  }
}
