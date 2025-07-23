import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'p2p_messages.dart';
import 'chain.dart';
import 'utils.dart';
import 'common.dart';
import 'result.dart';

final _log = Logger('Peer');

enum PeerStatus {
  connecting,
  connected,
  handshakeComplete,
  headersSyncing,
  headersSynced,
  disconnected,
}

enum PeerStatusChangeReason { invalidHeaders, socketClosed }

typedef PeerStatusEvent =
    void Function(
      Peer peer,
      PeerStatus status, {
      PeerStatusChangeReason? reason,
    });

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

String _ipv6ToIpv4(Uint8List ipv6) {
  if (ipv6.length != 16) {
    throw FormatException('Invalid IPv6 address length');
  }
  if (ipv6.sublist(0, 10).every((byte) => byte == 0) &&
      ipv6[10] == 0xff &&
      ipv6[11] == 0xff) {
    return '${ipv6[12]}.${ipv6[13]}.${ipv6[14]}.${ipv6[15]}';
  }
  throw FormatException('Not a valid IPv4-mapped IPv6 address');
}

class Peer {
  static const int maxBlockHeaders = 2000;

  final String ip;
  final int port;
  final Network network;
  final String userAgent = '/dartcoin:0.1/';

  final PeerStatusEvent _onStatusChange;
  Socket? _socket;
  PeerStatus _status = PeerStatus.connecting;
  ChainManager? _chainManager;

  PeerStatus get status => _status;

  Peer({
    required this.ip,
    required this.port,
    required this.network,
    required PeerStatusEvent onStatusChange,
  }) : _onStatusChange = onStatusChange;

  static int defaultPort(Network network) {
    return switch (network) {
      Network.mainnet => 8333,
      Network.testnet => 18333,
      Network.testnet4 => 48333,
    };
  }

  static Future<String> ipFromDnsSeed(Network network) async {
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
    };
    final randomSeed =
        seeds[DateTime.now().millisecondsSinceEpoch % seeds.length];
    _log.info('Using DNS seed: $randomSeed');
    try {
      final addresses = await InternetAddress.lookup(
        randomSeed,
        type: InternetAddressType.IPv4,
      );
      if (addresses.isNotEmpty && addresses[0].rawAddress.isNotEmpty) {
        _log.info('Found ${addresses.length} addresses for seed $randomSeed');
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

  void connect() async {
    final localPort = defaultPort(network);
    final localIp = '127.0.0.1';

    // connect to the peer
    _log.info('Connecting to peer: $ip:$port');
    try {
      _socket = await Socket.connect(ip, port);
      final socket = _socket!;
      _status = PeerStatus.connected;
      _onStatusChange(this, _status);
      _log.info('Connected to peer: $ip:$port');
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
      _log.info('>>>>>: $ip:$port, Version');
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
          _log.info('Disconnected from peer: $ip:$port');
          socket.destroy();
          _socket = null;
          _status = PeerStatus.disconnected;
          _onStatusChange(
            this,
            _status,
            reason: PeerStatusChangeReason.socketClosed,
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
    }
  }

  void logMessage(Message message, MessageHeader msgHeader) {
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
      _log.info(
        '<<<<<: $ip:$port, Block: ${message.block.header.previousBlockHeaderHash.toHex()}',
      );
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
      for (final addr in message.addresses) {
        _log.info(
          '       IP Addr: ${_ipv6ToIpv4(addr.ipAddress)}, Port: ${addr.port}, Time: ${addr.time}',
        );
      }
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

  void handleMessage(Message message, Socket socket) {
    if (message is MessageVersion) {
    } else if (message is MessageVerack) {
      // send a verack message back to the peer
      _log.info('>>>>>: $ip:$port, Verack');
      socket.add(MessageVerack().toBytes(network));
      // set status to handshake complete
      _status = PeerStatus.handshakeComplete;
      _onStatusChange(this, _status);
    } else if (message is MessagePing) {
      _log.info('>>>>>: $ip:$port, Pong');
      socket.add(MessagePong(nonce: message.nonce).toBytes(network));
    } else if (message is MessageInv) {
      _log.info('>>>>>: $ip:$port, GetData');
      socket.add(MessageGetData(inventory: message.inventory).toBytes(network));
    } else if (message is MessageGetData) {
      // TODO: handle getdata message if we can?
    } else if (message is MessageBlock) {
      // add the block to the block headers
      if (_status == PeerStatus.headersSynced) {
        if (_chainManager == null) {
          _log.warning('ChainManager is not initialized, cannot process block');
          return;
        }
        _chainManager!.addHeaders([message.block.header]);
      }
    } else if (message is MessageHeaders) {
      if (_status != PeerStatus.headersSyncing) {
        _log.warning('recieved headers when not syncing');
        return;
      }
      if (_chainManager == null) {
        _log.warning('ChainManager is not initialized, cannot process headers');
        return;
      }
      final chainManager = _chainManager!;
      // add the headers to the blockHeaders list
      if (!chainManager.addHeaders(message.headers)) {
        _log.warning('Failed to add headers: ${message.headers.length}');
        _status = PeerStatus.handshakeComplete;
        _onStatusChange(
          this,
          _status,
          reason: PeerStatusChangeReason.invalidHeaders,
        );
        return;
      }
      if (message.headers.length < maxBlockHeaders) {
        _status = PeerStatus.headersSynced;
        _onStatusChange(this, _status);
      } else {
        // request next batch of block headers
        _log.info(
          '>>>>>: $ip:$port, GetHeaders: ${reverseHash(chainManager.bestChainHead.header.hash()).toHex()}',
        );
        socket.add(
          MessageGetHeaders(
            headerHashes: chainManager.recentBlockHeadersHashes,
          ).toBytes(network),
        );
      }
    }
  }

  void disconnect() {
    if (_socket == null) {
      _log.warning('No active connection to disconnect from: $ip:$port');
      return;
    }
    _log.info('Disconnecting from peer: $ip:$port');
    _socket?.destroy();
    _socket = null;
    _status = PeerStatus.disconnected;
    _onStatusChange(this, _status);
  }

  void sync(ChainManager chainManager) {
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
    _status = PeerStatus.headersSyncing;
    _onStatusChange(this, _status);
    _log.info(
      '>>>>>: $ip:$port, GetHeaders: ${reverseHash(chainManager.bestChainHead.header.hash()).toHex()}',
    );
    socket.add(
      MessageGetHeaders(
        headerHashes: chainManager.recentBlockHeadersHashes,
      ).toBytes(network),
    );
  }
}
