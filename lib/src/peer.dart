import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

import 'logc.dart';
import 'p2p_messages.dart';
import 'block.dart';
import 'block_filter.dart';
import 'chain.dart';
import 'chain_store.dart';
import 'utils.dart';
import 'common.dart';
import 'result.dart';

final _log = ColorLogger('Peer');

enum PeerStatus {
  connecting,
  connected,
  handshakeComplete,
  requestAddrs,
  blockHeadersSyncing,
  blockHeadersSynced,
  blockFilterHeaderSyncing,
  blockFilterHeaderSynced,
  blockFilterGetLatestBlock,
  blockFilterSyncing,
  blockFilterSynced,
  getInterestingBlocks,
  disconnected,
}

enum PeerStatusChangeReason {
  socketConnectSuccess,
  socketConnectFailed,
  verackMessageReceived,
  headersMessageLessThanMax,
  cfHeadersMessageStopHashReachedBestChainHead,
  disconnectCalled,
  syncBlockHeadersCalled,
  syncBlockFilterHeadersCalled,
  syncBlockFilterHeadersCalledButAlreadySynced,
  requestAddrsCalled,
  requestBlocksCalled,
  syncBlockFiltersCalled,
  invalidBlockHeader,
  noChainHead,
  newBlockHeader,
  socketClosed,
}

typedef PeerStatusEvent =
    void Function(
      Peer peer,
      PeerStatus status,
      PeerStatus previousStatus, {
      PeerStatusChangeReason? reason,
    });

typedef PeerAddressesEvent = void Function(Peer peer, List<Address> addresses);

typedef PeerBlockReceivedEvent = void Function(Peer peer, Block block);

typedef PeerBlockFilterReceivedEvent =
    void Function(Peer peer, Uint8List blockHash, BasicBlockFilter filter);

class RequestedBlocks {
  final Map<String, DateTime> requestedBlocks = {};

  void _expireOldRequests() {
    final now = DateTime.now();
    requestedBlocks.removeWhere(
      (blockHash, requestTime) =>
          now.difference(requestTime) > const Duration(minutes: 10),
    );
  }

  void addRequestedBlock(Uint8List blockHash) {
    _expireOldRequests();
    requestedBlocks[blockHash.toHex()] = DateTime.now();
  }

  void addRequestedBlocks(List<Uint8List> blockHashes) {
    _expireOldRequests();
    final now = DateTime.now();
    for (final blockHash in blockHashes) {
      requestedBlocks[blockHash.toHex()] = now;
    }
  }

  bool isBlockRequested(Uint8List blockHash) {
    _expireOldRequests();
    final result = requestedBlocks.containsKey(blockHash.toHex());
    if (result) requestedBlocks.remove(blockHash.toHex());
    return result;
  }
}

Uint8List _ipv4ToIpv6(String ipv4) {
  final parts = ipv4.split('.');
  if (parts.length != 4) {
    throw FormatException('Invalid IPv4 address');
  }
  return Uint8List.fromList(
    '00000000000000000000ffff'.toBytes() +
        [
          int.parse(parts[0]),
          int.parse(parts[1]),
          int.parse(parts[2]),
          int.parse(parts[3]),
        ],
  );
}

bool _isIpv6(Uint8List address) {
  // check size
  if (address.length != 16) {
    return false;
  }
  // check if ipv4-mapped
  if (address.sublist(0, 10).every((byte) => byte == 0) &&
      address[10] == 0xff &&
      address[11] == 0xff) {
    return false;
  }
  return true;
}

String _ipv6ToString(Uint8List ipv6) {
  if (ipv6.length != 16) {
    throw FormatException('Invalid IPv6 address length');
  }
  final parts = <String>[];
  for (var i = 0; i < 16; i += 2) {
    final part = (ipv6[i] << 8) | ipv6[i + 1];
    parts.add(part.toRadixString(16));
  }
  return parts.join(':');
}

String _ipv6ToIpv4(Uint8List ipv6) {
  if (ipv6.length != 16) {
    throw FormatException('Invalid IPv6 address length');
  }
  if (ipv6.sublist(0, 10).every((byte) => byte == 0) &&
      ipv6[10] == 0xff &&
      ipv6[11] == 0xff) {
    return '${ipv6[12]}.${ipv6[13]}.${ipv6[14]}.${ipv6[15]}';
  }
  throw FormatException('Not a valid IPv4-mapped IPv6 address ${ipv6.toHex()}');
}

String parseIpAddress(Uint8List address) {
  if (_isIpv6(address)) {
    return _ipv6ToString(address);
  } else {
    return _ipv6ToIpv4(address);
  }
}

class Peer {
  static const int maxBlockHeaders = 2000;

  final String ip;
  final int port;
  final Network network;
  final String userAgent = '/dartcoin:0.1/';
  final bool verbose;

  PeerStatusEvent _onStatusChange;
  PeerAddressesEvent? _onAddresses;
  PeerBlockReceivedEvent? _onBlockReceived;
  PeerBlockFilterReceivedEvent? _onBlockFilterReceived;
  Socket? _socket;
  PeerStatus _status = PeerStatus.connecting;
  ChainManager? _chainManager;
  FullBlockStore? _blockStore;
  Timer? _bfHeadersTimer;
  int _bfHeadersTimeoutCount = 0;
  int? _serviceFlags;
  final _requestedBlocks = RequestedBlocks();

  PeerStatus get status => _status;
  int? get serviceFlags => _serviceFlags;
  bool get nodeCompactFiltersSupport =>
      (_serviceFlags != null) &&
      ((_serviceFlags! & Message.nodeCompactBlockFilters) != 0);

  Peer({
    required this.ip,
    required this.port,
    required this.network,
    required PeerStatusEvent onStatusChange,
    required PeerAddressesEvent? onAddresses,
    required PeerBlockReceivedEvent? onBlockReceived,
    required PeerBlockFilterReceivedEvent? onBlockFilterReceived,
    required this.verbose,
    FullBlockStore? blockStore,
  }) : _onStatusChange = onStatusChange,
       _onAddresses = onAddresses,
       _onBlockReceived = onBlockReceived,
       _onBlockFilterReceived = onBlockFilterReceived,
       _blockStore = blockStore;

  void setPeerStatusChangeCallback(PeerStatusEvent callback) {
    // set the callback for status changes
    _onStatusChange = callback;
  }

  void setAddressesCallback(PeerAddressesEvent? callback) {
    // set the callback for receiving addresses
    _onAddresses = callback;
  }

  void setBlockReceivedCallback(PeerBlockReceivedEvent? callback) {
    // set the callback for receiving blocks
    _onBlockReceived = callback;
  }

  void setBlockFilterReceivedCallback(PeerBlockFilterReceivedEvent? callback) {
    // set the callback for receiving block filters
    _onBlockFilterReceived = callback;
  }

  void setBlockStoreCallback(FullBlockStore? blockStore) {
    _blockStore = blockStore;
  }

  static int defaultPort(Network network) {
    return switch (network) {
      Network.mainnet => 8333,
      Network.testnet => 18333,
      Network.testnet4 => 48333,
      Network.regtest => 18444,
    };
  }

  static Future<String> ipFromDnsSeed(
    Network network, {
    bool verbose = false,
  }) async {
    final seeds = switch (network) {
      Network.mainnet => [
        'seed.bitcoin.sipa.be',
        'dnsseed.bluematt.me',
        'dnsseed.bitcoin.dashjr.org',
        'seed.bitcoin.sprovoost.nl',
        'seed.bitcoinstats.com',
        'seed.bitnodes.io',
      ],
      Network.testnet => [
        'testnet-seed.bitcoin.jonasschnelli.ch',
        'testnet-seed.bluematt.me',
        'seed.tbtc.petertodd.org',
        'seed.testnet.bitcoin.sprovoost.nl',
        'seed.testnet.achownodes.xyz',
      ],
      Network.testnet4 => [
        'seed.testnet4.bitcoin.sprovoost.nl',
        'seed.testnet4.achownodes.xyz',
      ],
      Network.regtest => throw UnsupportedError(
        'No DNS seeds available for regtest network',
      ),
    };
    final randomSeed =
        seeds[DateTime.now().millisecondsSinceEpoch % seeds.length];
    if (verbose) {
      _log.info('Using DNS seed: $randomSeed');
    }
    try {
      final addresses = await InternetAddress.lookup(
        randomSeed,
        type: InternetAddressType.IPv4,
      );
      if (addresses.isNotEmpty && addresses[0].rawAddress.isNotEmpty) {
        if (verbose) {
          _log.info('Found ${addresses.length} addresses for seed $randomSeed');
        }
        final randomAddress =
            addresses[DateTime.now().millisecondsSinceEpoch % addresses.length];
        _log.info('Random address: ${randomAddress.address}');
        return randomAddress.address;
      }
    } catch (e) {
      _log.severe('Error occurred while looking up DNS seed: $e');
      rethrow;
    }
    throw Exception('No valid IP address found for DNS seed: $randomSeed');
  }

  void _doStatusChange(PeerStatus newStatus, PeerStatusChangeReason reason) {
    // TEMP:TODO: log status change/reason
    if (verbose) {
      _log.info(
        'Peer status changing: $newStatus, Reason: $reason',
        color: LogColor.brightBlue,
      );
    }

    // reset any timers
    _clearBfHeadersTimer();
    // check if the status is already the same
    if (_status == newStatus) {
      //throw StateError(
      //  'Peer status is already $newStatus, cannot change to the same status',
      //);
    }
    // change the status
    final previousStatus = _status;
    _status = newStatus;
    _onStatusChange(this, newStatus, previousStatus, reason: reason);
  }

  void connect() async {
    final localPort = defaultPort(network);
    final localIp = '127.0.0.1';

    // connect to the peer
    if (verbose) {
      _log.info('Connecting to peer: $ip:$port');
    }
    try {
      _socket = await Socket.connect(
        ip,
        port,
        timeout: const Duration(seconds: 5),
      );
      final socket = _socket!;
      _doStatusChange(
        PeerStatus.connected,
        PeerStatusChangeReason.socketConnectSuccess,
      );
      if (verbose) {
        _log.info('Connected to peer: $ip:$port');
      }
      // send version message
      final versionBytes = MessageVersion(
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        remoteAddress: _ipv4ToIpv6(ip),
        remotePort: port,
        localAddress: _ipv4ToIpv6(localIp),
        localPort: localPort,
        nonce: 0,
        userAgent: userAgent,
        lastBlock: 0,
        relay: false,
      ).toBytes(network);
      if (verbose) {
        _log.info('>>>>>: $ip:$port, Version');
      }
      socket.add(versionBytes);
      // listen for incoming messages
      var msgBuffer = Uint8List(0);
      socket.listen(
        (data) {
          // Handle incoming data
          //_log.info('<<<<<: ${peer.ip}:${peer.port}, Data: ${data.toHex()}');
          msgBuffer = Uint8List.fromList(msgBuffer + data);
          // check what message type is received
          try {
            var breakLoop = false;
            while (msgBuffer.isNotEmpty && !breakLoop) {
              // test if msgBuffer has full message data
              final result = MessageHeader.parse(msgBuffer, network);
              switch (result) {
                case Ok():
                  final (message, msgHeader) = Message.fromBytes(
                    msgBuffer,
                    network,
                  );
                  logMessage(message, msgHeader);
                  handleMessage(message, socket);
                  // reset msgBuffer
                  msgBuffer = msgBuffer.sublist(
                    MessageHeader.messageHeaderSize +
                        result.value.payload.length,
                  );
                case Error():
                  // still waiting for data to complete payload
                  if (result.error is MessageHeaderPayloadExceedsException) {
                    breakLoop = true;
                  } else {
                    throw result.error; // no point parsing twice
                  }
              }
            }
          } catch (e) {
            _log.severe(
              'Error parsing message from peer: $ip:$port, Error: $e',
            );
          }
        },
        onDone: () {
          // Handle socket closure
          if (verbose) {
            _log.info('Disconnected from peer: $ip:$port');
          }
          socket.destroy();
          _socket = null;
          _doStatusChange(
            PeerStatus.disconnected,
            PeerStatusChangeReason.socketClosed,
          );
        },
        onError: (Object error) {
          _log.severe(
            'Error occurred while communicating with peer: $ip:$port, Error: $error',
          );
        },
      );
    } catch (error) {
      _log.severe('Failed to connect to peer: $ip:$port, Error: $error');
      _doStatusChange(
        PeerStatus.disconnected,
        PeerStatusChangeReason.socketConnectFailed,
      );
    }
  }

  void logMessage(Message message, MessageHeader msgHeader) {
    if (!verbose) return; // skip logging if verbose is false
    if (message is MessageVersion) {
      _log.info(
        '<<<<<: $ip:$port, Version: ${message.version}, User Agent: ${message.userAgent}, Last Block: ${message.lastBlock}',
      );
    } else if (message is MessageVerack) {
      _log.info('<<<<<: $ip:$port, Verack');
    } else if (message is MessagePing) {
      _log.info('<<<<<: $ip:$port, Ping: ${message.nonce}');
    } else if (message is MessagePong) {
      _log.info('<<<<<: $ip:$port, Pong: ${message.nonce}');
    } else if (message is MessageInv) {
      _log.info('<<<<<: $ip:$port, Inv: ${message.inventory.length}');
      for (final inv in message.inventory) {
        _log.info(
          '       Inventory: Type: ${inv.type.name}, Hash: ${inv.hash.toHex()}',
        );
      }
    } else if (message is MessageGetData) {
      _log.info('<<<<<: $ip:$port, GetData: ${message.inventory.length}');
      for (final inv in message.inventory) {
        _log.info(
          '       Inventory: Type: ${inv.type.name}, Hash: ${inv.hash.toHex()}',
        );
      }
    } else if (message is MessageBlock) {
      _log.info('<<<<<: $ip:$port, Block: ${message.block.header.hashNice()}');
      _log.info('       Transactions: ${message.block.transactions.length}');
      //for (final tx in message.block.transactions) {
      //  _log.info('       Transaction: ${tx.txid()}');
      //}
    } else if (message is MessageTransaction) {
      _log.info(
        '<<<<<: $ip:$port, Transaction: ${message.transaction.toBytes().toHex()}',
      );
    } else if (message is MessageFeeFilter) {
      _log.info('<<<<<: $ip:$port, FeeFilter: ${message.feeRate} sats/kB');
    } else if (message is MessageSendcmpct) {
      _log.info(
        '<<<<<: $ip:$port, Sendcmpct: Enabled: ${message.enabled}, Version: ${message.version}',
      );
    } else if (message is MessageAddress) {
      _log.info(
        '<<<<<: $ip:$port, Address: ${message.addresses.length} addresses',
      );
      //for (final addr in message.addresses) {
      //  final services = addr.services.toRadixString(16).padLeft(8, '0');
      //  final nodeCompactBlockFiltersSupport =
      //      (addr.services & Message.nodeCompactBlockFilters) != 0;
      //  final ipAddr = parseIpAddress(addr.ipAddress);
      //  _log.info(
      //    '       Services: $services, Block Filters: $nodeCompactBlockFiltersSupport, IP Addr: $ipAddr, Port: ${addr.port}, Time: ${addr.time}',
      //  );
      //}
    } else if (message is MessageGetHeaders) {
      _log.info(
        '<<<<<: $ip:$port, GetHeaders: ${message.headerHashes.length} hashes',
      );
    } else if (message is MessageHeaders) {
      _log.info('<<<<<: $ip:$port, Headers: ${message.headers.length} headers');
      //for (final header in message.headers) {
      //  _log.info(
      //    '       Header: Version: ${header.version}, Previous Block: ${header.previousBlockHeaderHash.toHex()}, Merkle Root: ${header.merkleRootHash.toHex()}, Time: ${header.time}, nBits: ${header.nBits}, Nonce: ${header.nonce}',
      //  );
      //}
    } else if (message is MessageGetCfHeaders) {
      _log.info(
        '<<<<<: $ip:$port, GetCfHeaders: ${message.filterType} type, ${message.startHeight} start height, ${message.stopHash.toHex()} stop hash',
      );
    } else if (message is MessageCfHeaders) {
      _log.info(
        '<<<<<: $ip:$port, CfHeaders: ${message.filterType} type, ${message.stopHash.toHex()} stop hash, ${message.previousFilterHeader.toHex()} previous filter hash, ${message.filterHashes.length} hashes',
      );
    } else if (message is MessageCFilter) {
      if (_chainManager == null) {
        _log.warning(
          'ChainManager is not initialized, cannot log block filter message',
        );
        return;
      }
      final chainManager = _chainManager!;
      final height = chainManager.bestChainHead
          .getAtHash(message.blockHash)
          .height;
      _log.info(
        '<<<<<: $ip:$port, CFilter: ${message.filterType} type, ${message.blockHash.reverse().toHex()} block hash ($height), ${message.filterBytes.length} bytes',
      );
    } else if (message is MessageUnknown) {
      _log.info('<<<<<: $ip:$port, Unknown: ${message.command}');
    }

    _log.info(
      '       Command:  ${msgHeader.command}\n'
      '                                         Size:     ${msgHeader.payload.length} bytes\n'
      '                                         Checksum: ${MessageHeader.checksum(msgHeader.payload).toHex()}\n',
      //'                                         Payload:  ${msgHeader.payload.toHex()}',
    );
  }

  bool _statusAtLeast(PeerStatus status) {
    return _status.index >= status.index;
  }

  void handleMessage(Message message, Socket socket) {
    if (message is MessageVersion) {
      // save peer data
      _serviceFlags = message.serviceFlags;
    } else if (message is MessageVerack) {
      // send a verack message back to the peer
      if (verbose) {
        _log.info('>>>>>: $ip:$port, Verack');
      }
      socket.add(MessageVerack().toBytes(network));
      // set status to handshake complete
      _doStatusChange(
        PeerStatus.handshakeComplete,
        PeerStatusChangeReason.verackMessageReceived,
      );
    } else if (message is MessagePing) {
      if (verbose) {
        _log.info('>>>>>: $ip:$port, Pong');
      }
      socket.add(MessagePong(nonce: message.nonce).toBytes(network));
    } else if (message is MessageInv) {
      if (verbose) {
        _log.info('>>>>>: $ip:$port, GetData');
      }
      socket.add(MessageGetData(inventory: message.inventory).toBytes(network));
    } else if (message is MessageAddress) {
      if (_status == PeerStatus.requestAddrs && _onAddresses != null) {
        _onAddresses!(this, message.addresses);
      }
    } else if (message is MessageGetData) {
      // TODO: handle getdata message if we can?
    } else if (message is MessageBlock) {
      // Store every arriving block.
      _blockStore?.store(message.block);
      if (_onBlockReceived != null) {
        _onBlockReceived!(this, message.block);
      }
      //print('##Received block from peer: $ip:$port (${message.block.header.hashNice()})');
      if (_status == PeerStatus.blockFilterGetLatestBlock) {
        ///return;
      }
      if (_requestedBlocks.isBlockRequested(message.block.header.hash())) {
        if (verbose) {
          _log.info(
            'Received requested block: ${message.block.header.hashNice()}',
          );
        }
        // we should already have the header for this block if we requested if
        return;
      }
      // add the block to the block headers
      if (_statusAtLeast(PeerStatus.blockHeadersSynced)) {
        if (_chainManager == null) {
          _log.warning('ChainManager is not initialized, cannot process block');
          return;
        }
        switch (_chainManager!.addBlockHeaders([message.block.header])) {
          case AddBlockHeadersResult.success:
            if (_status == PeerStatus.blockFilterHeaderSynced) {
              // we now need to resync to get the new block filter headers
              _doStatusChange(
                PeerStatus.blockHeadersSynced,
                PeerStatusChangeReason.newBlockHeader,
              );
            }
            break; // block added successfully
          case AddBlockHeadersResult.invalidBlockHeader:
            // TODO: disconnect peer?
            break; // invalid header,
          case AddBlockHeadersResult.noChainHead:
            // if the block is not part of any of our known chains, we need to request more headers
            _doStatusChange(
              PeerStatus.handshakeComplete,
              PeerStatusChangeReason.noChainHead,
            );
            break;
        }
        if (_bfHeadersTimer?.isActive ?? false) {
          // reset the timer to request block filter headers again
          _startOrResetCfHeadersTimer();
        }
        if (_status == PeerStatus.blockFilterHeaderSynced) {
          if (_chainManager == null) {
            _log.warning(
              'ChainManager is not initialized, cannot process block',
            );
            return;
          }
          // TODO: create the compact block filter from the block
          //_chainManager!.addBlockFilterHeaders();
        }
      }
    } else if (message is MessageHeaders) {
      if (_status != PeerStatus.blockHeadersSyncing) {
        _log.warning('recieved headers when not syncing');
        return;
      }
      if (_chainManager == null) {
        _log.warning('ChainManager is not initialized, cannot process headers');
        return;
      }
      final chainManager = _chainManager!;
      // add the headers to the blockHeaders list
      switch (chainManager.addBlockHeaders(message.headers)) {
        case AddBlockHeadersResult.success:
          break; // headers added successfully
        case AddBlockHeadersResult.invalidBlockHeader:
          _log.warning(
            'Failed to add invalid headers: ${message.headers.length}',
          );
          _doStatusChange(
            PeerStatus.handshakeComplete,
            PeerStatusChangeReason.invalidBlockHeader,
          );
          return;
        case AddBlockHeadersResult.noChainHead:
          _log.warning('Failed to add headers, no chain head found');
          _doStatusChange(
            PeerStatus.handshakeComplete,
            PeerStatusChangeReason.noChainHead,
          );
          return;
      }
      if (message.headers.length < maxBlockHeaders) {
        _doStatusChange(
          PeerStatus.blockHeadersSynced,
          PeerStatusChangeReason.headersMessageLessThanMax,
        );
      } else {
        // request next batch of block headers
        if (verbose) {
          _log.info(
            '>>>>>: $ip:$port, GetHeaders: ${headerHashNice(chainManager.bestChainHead.header.hash())}',
          );
        }
        socket.add(
          MessageGetHeaders(
            headerHashes: chainManager.recentBlockHeadersHashes,
          ).toBytes(network),
        );
      }
    } else if (message is MessageCfHeaders) {
      _clearBfHeadersTimer();
      if (_status != PeerStatus.blockFilterHeaderSyncing) {
        _log.warning('Received block filter headers when not syncing');
        return;
      }
      if (_chainManager == null) {
        _log.warning(
          'ChainManager is not initialized, cannot process block filter headers',
        );
        return;
      }
      final chainManager = _chainManager!;
      // add the headers to the block filter list
      if (message.filterType != BasicBlockFilter.filterType) {
        _log.warning(
          'Unsupported block filter type: ${message.filterType}, expected 0',
        );
        return;
      }
      switch (chainManager.addBlockFilterHeaders(
        message.previousFilterHeader,
        message.filterHashes,
        message.stopHash,
      )) {
        case AddBlockFilterHeadersResult.success:
          break;
        case AddBlockFilterHeadersResult.invalidBlockFilterHeader:
          _log.warning(
            'Failed to add invalid filter headers: ${message.filterHashes.length}',
          );
          break;
      }
      if (compareHashes(
        message.stopHash,
        chainManager.bestChainHead.header.hash(),
      )) {
        _doStatusChange(
          PeerStatus.blockFilterHeaderSynced,
          PeerStatusChangeReason.cfHeadersMessageStopHashReachedBestChainHead,
        );
      } else {
        // request next batch of block filter headers
        _sendGetCfHeaders(socket, chainManager);
      }
    } else if (message is MessageCFilter) {
      if (status != PeerStatus.blockFilterSyncing) {
        _log.warning('Received block filter when not syncing');
        return;
      }
      if (_chainManager == null) {
        _log.warning(
          'ChainManager is not initialized, cannot process block filters',
        );
        return;
      }
      final chainManager = _chainManager!;
      // add the headers to the block filter list
      if (message.filterType != BasicBlockFilter.filterType) {
        _log.warning(
          'Unsupported block filter type: ${message.filterType}, expected 0',
        );
        return;
      }
      // Store the filter in the chain manager.
      chainManager.addBlockFilter(message.blockHash, message.filterBytes);

      if (_onBlockFilterReceived != null) {
        _onBlockFilterReceived!(
          this,
          message.blockHash,
          BasicBlockFilter.fromBytes(filterBytes: message.filterBytes),
        );
      }
    }
  }

  void _startOrResetCfHeadersTimer() {
    _clearBfHeadersTimer();
    if (_socket == null) {
      _log.warning(
        'No active socket connection to start block filter headers timer',
      );
      return;
    }
    if (_chainManager == null) {
      _log.warning(
        'ChainManager is not initialized, cannot start block filter headers timer',
      );
      return;
    }
    _bfHeadersTimer = Timer(
      const Duration(seconds: 2),
      () => _sendGetCfHeaders(_socket!, _chainManager!),
    );
  }

  void _clearBfHeadersTimer() {
    _bfHeadersTimer?.cancel();
    _bfHeadersTimer = null;
    _bfHeadersTimeoutCount = 0;
  }

  void disconnect() {
    _clearBfHeadersTimer();
    if (_socket == null) {
      _log.warning('No active connection to disconnect from: $ip:$port');
      return;
    }
    if (verbose) {
      _log.info('Disconnecting from peer: $ip:$port');
    }
    _socket?.destroy();
    _socket = null;
    _doStatusChange(
      PeerStatus.disconnected,
      PeerStatusChangeReason.disconnectCalled,
    );
  }

  void syncBlockHeaders(ChainManager chainManager) {
    if (_status != PeerStatus.handshakeComplete) {
      _log.warning(
        'Cannot start syncing, peer is not in handshake complete state: $ip:$port',
      );
      return;
    }
    if (_socket == null) {
      _log.warning('No active socket connection to sync with: $ip:$port');
      return;
    }
    final socket = _socket!;
    _chainManager = chainManager;
    //  start requesting block headers
    _doStatusChange(
      PeerStatus.blockHeadersSyncing,
      PeerStatusChangeReason.syncBlockHeadersCalled,
    );
    if (verbose) {
      _log.info(
        '>>>>>: $ip:$port, GetHeaders: ${headerHashNice(chainManager.bestChainHead.header.hash())}',
      );
    }
    socket.add(
      MessageGetHeaders(
        headerHashes: chainManager.recentBlockHeadersHashes,
      ).toBytes(network),
    );
  }

  void _sendGetCfHeaders(Socket socket, ChainManager chainManager) {
    final startHeight = chainManager.bestBlockFilterHead.height + 1;
    var endHeight = startHeight + 1999;
    endHeight = endHeight > chainManager.bestChainHead.height
        ? chainManager.bestChainHead.height
        : endHeight;
    final stopHash = chainManager.blockHashForHeight(endHeight);
    if (stopHash == null) {
      _log.warning(
        'No block hash found for height $endHeight, cannot sync compact filters',
      );
      return;
    }
    if (verbose) {
      _log.info(
        '>>>>>: $ip:$port, GetCfHeaders: $startHeight-${headerHashNice(stopHash)} ($endHeight)',
      );
    }
    socket.add(
      MessageGetCfHeaders(
        filterType: BasicBlockFilter.filterType,
        startHeight: startHeight,
        stopHash: stopHash,
      ).toBytes(network),
    );
    // set timer because the peer might not have processed the block filters yet
    if (_bfHeadersTimeoutCount < 5) {
      _bfHeadersTimer = Timer(const Duration(seconds: 1), _bfHeadersTimeout);
    }
  }

  void _bfHeadersTimeout() {
    _bfHeadersTimeoutCount++;
    _bfHeadersTimer = null;
    if (_bfHeadersTimeoutCount >= 5) {
      _log.warning(
        'block filter header sync timed out after 5 attempts, peer: $ip:$port',
      );
      return;
    }
    if (_status != PeerStatus.blockFilterHeaderSyncing) {
      _log.warning(
        'block filter header sync timed out, peer is not in block filter header syncing state: $ip:$port',
      );
      return;
    }
    if (_socket == null) {
      _log.warning('No active socket connection to sync with: $ip:$port');
      return;
    }
    if (_chainManager == null) {
      _log.warning('ChainManager is not initialized, cannot sync headers');
      return;
    }
    // request block filter headers again
    _sendGetCfHeaders(_socket!, _chainManager!);
  }

  void syncBlockFilterHeaders(ChainManager chainManager) {
    if (!_statusAtLeast(PeerStatus.blockHeadersSynced)) {
      _log.warning(
        'Cannot start syncing, peer is not in block headers synced state: $ip:$port',
      );
      return;
    }
    if (chainManager.bestBlockFilterHead.height <
        chainManager.bestChainHead.height) {
      //  start requesting block filter headers
      _doStatusChange(
        PeerStatus.blockFilterHeaderSyncing,
        PeerStatusChangeReason.syncBlockFilterHeadersCalled,
      );
      _startOrResetCfHeadersTimer();
    } else {
      if (verbose) {
        _log.info(
          'block filter headers are already synced for peer: $ip:$port',
        );
      }
      _doStatusChange(
        PeerStatus.blockFilterHeaderSynced,
        PeerStatusChangeReason.syncBlockFilterHeadersCalledButAlreadySynced,
      );
    }
  }

  void requestAddrs() {
    if (_socket == null) {
      _log.warning(
        'No active socket connection to request addrs from: $ip:$port',
      );
      return;
    }
    _doStatusChange(
      PeerStatus.requestAddrs,
      PeerStatusChangeReason.requestAddrsCalled,
    );
    final socket = _socket!;
    if (verbose) {
      _log.info('>>>>>: $ip:$port, GetAddr');
    }
    socket.add(MessageGetAddr().toBytes(network));
  }

  void requestBlocks(List<Uint8List> blockHashes, PeerStatus targetStatus) {
    assert(
      targetStatus == PeerStatus.blockFilterGetLatestBlock ||
          targetStatus == PeerStatus.getInterestingBlocks,
    );
    if (_socket == null) {
      _log.warning(
        'No active socket connection to request block from: $ip:$port',
      );
      return;
    }
    _doStatusChange(targetStatus, PeerStatusChangeReason.requestBlocksCalled);
    // Serve any already-cached blocks immediately.
    final uncached = <Uint8List>[];
    for (final hash in blockHashes) {
      final cached = _blockStore?.read(hash);
      if (cached != null) {
        if (verbose) {
          _log.info(
            'Serving cached block from store: ${hash.reverse().toHex()}',
          );
        }
        _onBlockReceived?.call(this, cached);
      } else {
        uncached.add(hash);
      }
    }
    if (uncached.isEmpty) return;
    _requestedBlocks.addRequestedBlocks(uncached);
    final socket = _socket!;
    if (verbose) {
      _log.info(
        '>>>>>: $ip:$port, GetData - Blocks: ${uncached.map((hash) => hash.reverse().toHex()).join(', ')}',
      );
    }
    socket.add(
      MessageGetData(
        inventory: uncached
            .map(
              (hash) => InventoryItem(type: InventoryType.msgBlock, hash: hash),
            )
            .toList(),
      ).toBytes(network),
    );
  }

  void syncBlockFilters(int startHeight, Uint8List stopHash) {
    if (!_statusAtLeast(PeerStatus.blockFilterHeaderSynced)) {
      _log.warning(
        'Cannot start syncing, peer is not in block filter header synced state: $ip:$port',
      );
      return;
    }
    if (status != PeerStatus.blockFilterSyncing) {
      _doStatusChange(
        PeerStatus.blockFilterSyncing,
        PeerStatusChangeReason.syncBlockFiltersCalled,
      );
    }
    final socket = _socket!;
    if (verbose) {
      _log.info(
        '>>>>>: $ip:$port, GetCFilters - Start Height: $startHeight, Stop Hash: ${stopHash.reverse().toHex()}',
      );
    }
    socket.add(
      MessageGetCFilters(
        filterType: BasicBlockFilter.filterType,
        startHeight: startHeight,
        stopHash: stopHash,
      ).toBytes(network),
    );
  }
}
