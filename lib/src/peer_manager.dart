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

  PeerManager({required this.network, this.verbose = false});

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
    List<PeerAddress> addresses,
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

  // Number of candidates to attempt concurrently in each batch.
  static const int _concurrency = 6;

  /// Tries [candidates] concurrently in batches of [_concurrency]. Returns the
  /// first [Peer] that completes a handshake and supports compact block
  /// filters, disconnecting all losers. Returns `null` if all fail.
  Future<Peer?> _raceConnections(List<PeerCandidate> candidates) async {
    for (var i = 0; i < candidates.length; i += _concurrency) {
      final batch = candidates.sublist(
        i,
        (i + _concurrency).clamp(0, candidates.length),
      );
      if (verbose) {
        _log.info(
          'Racing batch of ${batch.length} connection(s): '
          '${batch.map((c) => '${c.ip}:${c.port}').join(', ')}',
        );
      }

      // Launch all connections in the batch concurrently.
      final futures = batch.map((c) => _connectPeer(c)).toList();
      final peers = await Future.wait(futures);

      Peer? winner;
      for (final peer in peers) {
        if (winner == null &&
            peer.status == PeerStatus.handshakeComplete &&
            peer.nodeCompactFiltersSupport) {
          winner = peer;
        } else {
          // Disconnect any peer we are not keeping.
          if (peer.status != PeerStatus.disconnected) {
            peer.disconnect();
          }
        }
      }

      if (winner != null) {
        if (verbose) {
          _log.info(
            'Connected to peer ${winner.ip}:${winner.port} supporting compact block filters.',
          );
        }
        return winner;
      }
    }
    return null;
  }

  /// Discovers peers by querying all DNS seeds concurrently, then attempts up
  /// to [_concurrency] connections at a time until a suitable peer is found.
  /// If no suitable peer found, a secondary sweep is made using
  /// addresses advertised by peers that completed the handshake but lack
  /// compact-filter support. Retries up to [_maxAttempts] times.
  Future<Peer?> findPeer() async {
    _count += 1;
    final port = Peer.defaultPort(network);

    // query every DNS seed concurrently
    if (verbose) {
      _log.info(
        'Querying all DNS seeds concurrently (attempt $_count/$_maxAttempts)...',
      );
    }
    final List<String> seedIps;
    try {
      seedIps = await Peer.ipsFromDnsSeeds(network, verbose: verbose);
    } catch (e) {
      _log.warning('Failed to gather DNS seed candidates: $e');
      if (_count < _maxAttempts) return findPeer();
      return null;
    }

    if (seedIps.isEmpty) {
      _log.warning('No seed IPs discovered.');
      if (_count < _maxAttempts) return findPeer();
      return null;
    }

    final seedCandidates = seedIps
        .map((ip) => PeerCandidate(ip: ip, port: port))
        .toList();

    // race seed candidates
    final winner = await _raceConnections(seedCandidates);
    if (winner != null) return winner;

    // peers of a peer
    if (verbose) {
      _log.info(
        'No suitable peer found in seed batch. '
        'Attempting to expand list of peers...',
      );
    }
    // reconnect to any one seed peer just enough to get an addr list.
    for (final candidate in seedCandidates.take(_concurrency)) {
      final probe = await _connectPeer(candidate);
      if (probe.status == PeerStatus.handshakeComplete) {
        final newCandidates = await _requestPeerCandidates(probe);
        if (probe.status != PeerStatus.disconnected) {
          probe.disconnect();
        }
        if (newCandidates.isNotEmpty) {
          final expandedWinner = await _raceConnections(newCandidates);
          if (expandedWinner != null) return expandedWinner;
        }
        break;
      }
      if (probe.status != PeerStatus.disconnected) {
        probe.disconnect();
      }
    }

    // retry
    if (_count < _maxAttempts) {
      if (verbose) {
        _log.info('No suitable peer found. Retrying...');
      }
      return findPeer();
    }
    _log.warning('Max attempts reached. Giving up.');
    return null;
  }
}
