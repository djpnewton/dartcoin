import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'utils.dart';
import 'p2p_messages.dart';
import 'common.dart';
import 'result.dart';
import 'chain.dart';

final _log = Logger('Node');

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
  String ip;
  int port;

  Peer({required this.ip, required this.port});
}

class Node {
  static const int maxBlockHeaders = 2000;

  Map<Peer, Socket> connections = {};
  String userAgent = '/dartcoin:0.1/';
  Network network;
  late String dataDir;
  late ChainManager chainManager;

  Node({required this.network}) {
    // initialize the data directory
    dataDir = initDataDir(network);
    // initialize the chain manager
    chainManager = ChainManager(
      network: network,
      blockHeadersFilePath: blockHeadersFilePath,
    );
  }

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
    return '$dataDir/headers.json';
  }

  void logMessage(Peer peer, Message message, MessageHeader msgHeader) {
    if (message is MessageVersion) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, Version: ${message.version}, User Agent: ${message.userAgent}, Last Block: ${message.lastBlock}',
      );
    } else if (message is MessageVerack) {
      _log.info('<<<<<: ${peer.ip}:${peer.port}, Verack');
    } else if (message is MessagePing) {
      _log.info('<<<<<: ${peer.ip}:${peer.port}, Ping: ${message.nonce}');
    } else if (message is MessagePong) {
      _log.info('<<<<<: ${peer.ip}:${peer.port}, Pong: ${message.nonce}');
    } else if (message is MessageInv) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, Inv: ${message.inventory.length}',
      );
      for (final inv in message.inventory) {
        _log.info(
          '       Inventory: Type: ${inv.type.name}, Hash: ${inv.hash.toHex()}',
        );
      }
    } else if (message is MessageGetData) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, GetData: ${message.inventory.length}',
      );
      for (final inv in message.inventory) {
        _log.info(
          '       Inventory: Type: ${inv.type.name}, Hash: ${inv.hash.toHex()}',
        );
      }
    } else if (message is MessageBlock) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, Block: ${message.block.header.previousBlockHeaderHash.toHex()}',
      );
      _log.info('       Transactions: ${message.block.transactions.length}');
      //for (final tx in message.block.transactions) {
      //  _log.info('       Transaction: ${tx.txid()}');
      //}
    } else if (message is MessageTransaction) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, Transaction: ${message.transaction.toBytes().toHex()}',
      );
    } else if (message is MessageFeeFilter) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, FeeFilter: ${message.feeRate} sats/kB',
      );
    } else if (message is MessageSendcmpct) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, Sendcmpct: Enabled: ${message.enabled}, Version: ${message.version}',
      );
    } else if (message is MessageAddress) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, Address: ${message.addresses.length} addresses',
      );
      for (final addr in message.addresses) {
        _log.info(
          '       IP Addr: ${_ipv6ToIpv4(addr.ipAddress)}, Port: ${addr.port}, Time: ${addr.time}',
        );
      }
    } else if (message is MessageGetHeaders) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, GetHeaders: ${message.headerHashes.length} hashes',
      );
    } else if (message is MessageHeaders) {
      _log.info(
        '<<<<<: ${peer.ip}:${peer.port}, Headers: ${message.headers.length} headers',
      );
      //for (final header in message.headers) {
      //  _log.info(
      //    '       Header: Version: ${header.version}, Previous Block: ${header.previousBlockHeaderHash.toHex()}, Merkle Root: ${header.merkleRootHash.toHex()}, Time: ${header.time}, nBits: ${header.nBits}, Nonce: ${header.nonce}',
      //  );
      //}
    } else if (message is MessageUnknown) {
      _log.info('<<<<<: ${peer.ip}:${peer.port}, Unknown: ${message.command}');
    }

    _log.info(
      '       Command:  ${msgHeader.command}\n'
      '                                         Size:     ${msgHeader.payload.length} bytes\n'
      '                                         Checksum: ${MessageHeader.checksum(msgHeader.payload).toHex()}\n',
      //'                                         Payload:  ${msgHeader.payload.toHex()}',
    );
  }

  void handleMessage(Peer peer, Message message, Socket socket) {
    if (message is MessageVersion) {
    } else if (message is MessageVerack) {
      // send a verack message back to the peer
      _log.info('>>>>>: ${peer.ip}:${peer.port}, Verack');
      socket.add(MessageVerack().toBytes(network));
      // also start requesting block headers
      _log.info(
        '>>>>>: ${peer.ip}:${peer.port}, GetHeaders: ${reverseHash(chainManager.best.header.hash()).toHex()}',
      );
      socket.add(
        MessageGetHeaders(
          headerHashes: chainManager.recentBlockHeadersHashes,
        ).toBytes(network),
      );
    } else if (message is MessagePing) {
      _log.info('>>>>>: ${peer.ip}:${peer.port}, Pong');
      socket.add(MessagePong(nonce: message.nonce).toBytes(network));
    } else if (message is MessageInv) {
      _log.info('>>>>>: ${peer.ip}:${peer.port}, GetData');
      socket.add(MessageGetData(inventory: message.inventory).toBytes(network));
    } else if (message is MessageGetData) {
      // TODO: handle getdata message if we can?
    } else if (message is MessageBlock) {
      // add the block to the block headers
      chainManager.addHeaders([message.block.header]);
    } else if (message is MessageHeaders) {
      // add the headers to the blockHeaders list
      if (chainManager.addHeaders(message.headers) &&
          message.headers.length == maxBlockHeaders) {
        // request next batch of block headers
        _log.info(
          '>>>>>: ${peer.ip}:${peer.port}, GetHeaders: ${reverseHash(chainManager.best.header.hash()).toHex()}',
        );
        socket.add(
          MessageGetHeaders(
            headerHashes: chainManager.recentBlockHeadersHashes,
          ).toBytes(network),
        );
      }
    }
  }

  void connectPeer(Peer peer) async {
    final localPort = defaultPort(network);
    final localIp = '127.0.0.1';

    // connect to the peer
    _log.info('Connecting to peer: ${peer.ip}:${peer.port}');
    try {
      final socket = await Socket.connect(peer.ip, peer.port);
      connections[peer] = socket;
      _log.info('Connected to peer: ${peer.ip}:${peer.port}');
      // send version message
      final versionBytes = MessageVersion(
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        remoteAddress: _ipv4ToIpv6(peer.ip),
        remotePort: peer.port,
        localAddress: _ipv4ToIpv6(localIp),
        localPort: localPort,
        nonce: 0,
        userAgent: userAgent,
        lastBlock: 0,
        relay: false,
      ).toBytes(network);
      _log.info('>>>>>: ${peer.ip}:${peer.port}, Version');
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
                  logMessage(peer, message, msgHeader);
                  handleMessage(peer, message, socket);
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
              'Error parsing message from peer: ${peer.ip}:${peer.port}, Error: $e',
            );
          }
        },
        onDone: () {
          // Handle socket closure
          connections.remove(peer);
          _log.info('Disconnected from peer: ${peer.ip}:${peer.port}');
          socket.destroy();
        },
        onError: (Object error) {
          _log.severe(
            'Error occurred while communicating with peer: ${peer.ip}:${peer.port}, Error: $error',
          );
        },
      );
    } catch (error) {
      _log.severe(
        'Failed to connect to peer: ${peer.ip}:${peer.port}, Error: $error',
      );
    }
  }
}
