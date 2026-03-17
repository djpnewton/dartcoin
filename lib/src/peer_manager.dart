import 'dart:async';

import 'logc.dart';
import 'common.dart';
import 'peer.dart';
import 'p2p_messages.dart';

final _log = ColorLogger('PeerManager');

class PeerCandidate {
  final String ip;
  final int port;

  PeerCandidate({required this.ip, required this.port});
}

class PeerManager {
  final Network network;
  final bool verbose;
  final bool preferentialPeering;

  PeerManager({
    required this.network,
    this.verbose = false,
    this.preferentialPeering = false,
  });

  static const int _maxAttempts = 5;
  int _count = 0;
  List<PeerCandidate> _peerCandidates = [];

  void _peerStatusChange(
    Peer peer,
    PeerStatus status,
    PeerStatus prevStatus, {
    PeerStatusChangeReason? reason,
  }) {
    // Handle peer status changes
  }

  Future<Peer> _connectPeer(PeerCandidate candidate) async {
    final peer = Peer(
      ip: candidate.ip,
      port: candidate.port,
      network: network,
      onStatusChange: _peerStatusChange,
      onAddresses: _peerAddressesReceived,
      onBlockReceived: null,
      onBlockFilterReceived: null,
      verbose: verbose,
    );
    peer.connect();
    final startTime = DateTime.now();
    while (peer.status != PeerStatus.disconnected &&
        peer.status != PeerStatus.handshakeComplete &&
        DateTime.now().difference(startTime) < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    return peer;
  }

  Future<void> _peerAddressesReceived(
    Peer peer,
    List<Address> addresses,
  ) async {
    // search for peers that support compact block filters
    final suitableAddrs = addresses.where((addr) {
      return (addr.services & Message.nodeCompactBlockFilters) != 0;
    }).toList();
    if (suitableAddrs.isNotEmpty) {
      // get up to 5 random suitable addresses
      final randomAddrs = <PeerCandidate>[];
      for (var i = 0; i < 5 && suitableAddrs.isNotEmpty; i++) {
        final randomAddr =
            suitableAddrs[DateTime.now().millisecondsSinceEpoch %
                suitableAddrs.length];
        suitableAddrs.remove(randomAddr);
        randomAddrs.add(
          PeerCandidate(
            ip: parseIpAddress(randomAddr.ipAddress),
            port: randomAddr.port,
          ),
        );
      }
      if (verbose) {
        _log.info(
          'Found addrs supporting compact block filters: ${randomAddrs.map((addr) => '${addr.ip}:${addr.port}').join(', ')}',
        );
      }
      // set candidate peer info
      _peerCandidates = randomAddrs;
      // stop processing further addresses
      peer.setAddressesCallback(null);
    }
  }

  Future<Peer?> connectPeer(PeerCandidate candidate) async {
    final peer = await _connectPeer(candidate);
    if (peer.status == PeerStatus.handshakeComplete &&
        peer.nodeCompactFiltersSupport) {
      return peer;
    }
    if (verbose) {
      _log.info(
        'Peer ${candidate.ip}:${candidate.port} status: ${peer.status}, ${peer.nodeCompactFiltersSupport ? 'supports' : 'does not support'} compact block filters.',
      );
    }
    if (peer.status != PeerStatus.disconnected) {
      peer.disconnect();
    }
    return null;
  }

  Future<List<PeerCandidate>> _requestPeerCandidates(Peer peer) async {
    if (verbose) {
      _log.info('Requesting more peers from ${peer.ip}:${peer.port}...');
    }
    _peerCandidates.clear();
    peer.requestAddrs();
    final startTime = DateTime.now();
    while (_peerCandidates.isEmpty &&
        DateTime.now().difference(startTime) < const Duration(seconds: 10)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_peerCandidates.isNotEmpty) {
      if (verbose) {
        _log.info(
          'Found new candidates: ${_peerCandidates.map((addr) => '${addr.ip}:${addr.port}').join(', ')}.',
        );
      }
    }
    return _peerCandidates;
  }

  Future<Peer?> findPeer() async {
    _count += 1;
    // get peer info from dns seed if not provided
    final ip = await Peer.ipFromDnsSeed(network, verbose: true);
    final port = Peer.defaultPort(network);
    // try and handshake with the peer
    final peer = await _connectPeer(PeerCandidate(ip: ip, port: port));
    if (peer.status == PeerStatus.handshakeComplete) {
      if (verbose) {
        _log.info('Peer $ip:$port handshake complete.');
      }
      if (peer.nodeCompactFiltersSupport) {
        return peer;
      }
      if (verbose) {
        _log.info('Peer $ip:$port does not support compact block filters.');
      }
      // ask for more peers if preferential peering is enabled
      if (preferentialPeering) {
        final newPeerCandidates = await _requestPeerCandidates(peer);
        if (peer.status != PeerStatus.disconnected) {
          peer.disconnect();
        }
        for (final newPeerCandidate in newPeerCandidates) {
          if (verbose) {
            _log.info(
              'Attempting connection to new candidate ${newPeerCandidate.ip}:${newPeerCandidate.port}...',
            );
          }
          final newPeer = await _connectPeer(newPeerCandidate);
          if (newPeer.status == PeerStatus.handshakeComplete &&
              newPeer.nodeCompactFiltersSupport) {
            if (verbose) {
              _log.info(
                'Connected to new peer ${newPeer.ip}:${newPeer.port} supporting compact block filters.',
              );
            }
            return newPeer;
          }
          if (newPeer.status != PeerStatus.disconnected) {
            newPeer.disconnect();
          }
        }
      }
    }
    if (peer.status != PeerStatus.disconnected) {
      peer.disconnect();
    }
    // failed, try again if attempts remain
    if (_count < _maxAttempts) {
      return findPeer();
    } else {
      _log.warning('Max attempts reached. Giving up.');
      return null;
    }
  }
}
