import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import 'utils.dart';
import 'p2p_messages.dart';
import 'block.dart';
import 'common.dart';
import 'result.dart';

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
  static const int difficultyAdjustmentInterval = 2016;
  static const int maxTimewarp = 600;
  static const int maxBlockHeaders = 2000;

  Map<Peer, Socket> connections = {};
  List<BlockHeader> blockHeaders = [];
  String userAgent = '/dartcoin:0.1/';
  Network network;

  Node({required this.network}) {
    // initialize with the genesis block header
    blockHeaders = <BlockHeader>[Block.genesisBlock(network).header];
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

  void logMessage(Peer peer, Message message) {
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
      '       Command:  ${message.command}\n'
      '                                         Size:     ${message.payload.length} bytes\n'
      '                                         Checksum: ${Message.checksum(message.payload).toHex()}\n',
      //'                                         Payload:  ${message.payload.toHex()}',
    );
  }

  void replyMessage(Peer peer, Message message, Socket socket) {
    if (message is MessageVersion) {
    } else if (message is MessageVerack) {
      // send a verack message back to the peer
      _log.info('>>>>>: ${peer.ip}:${peer.port}, Verack');
      socket.add(MessageVerack().toBytes(network));
      // also start requesting block headers
      _log.info('>>>>>: ${peer.ip}:${peer.port}, GetHeaders');
      socket.add(
        MessageGetHeaders(
          headerHashes: [blockHeaders.last.hash()],
          payload: Uint8List(
            0,
          ), // TODO: not nice to need to put this dummy value here
        ).toBytes(network),
      );
    } else if (message is MessagePing) {
      _log.info('>>>>>: ${peer.ip}:${peer.port}, Pong');
      socket.add(
        MessagePong(
          nonce: message.nonce,
          payload: Uint8List(0),
        ).toBytes(network),
      );
    } else if (message is MessageInv) {
      _log.info('>>>>>: ${peer.ip}:${peer.port}, GetData');
      socket.add(
        MessageGetData(
          inventory: message.inventory,
          payload: message.payload,
        ).toBytes(network),
      );
    } else if (message is MessageGetData) {
      // TODO: handle getdata message if we can?
    } else if (message is MessageHeaders) {
      if (addHeaders(message.headers) &&
          message.headers.length == maxBlockHeaders) {
        // request next batch of block headers
        _log.info('>>>>>: ${peer.ip}:${peer.port}, GetHeaders');
        socket.add(
          MessageGetHeaders(
            headerHashes: [blockHeaders.last.hash()],
            payload: Uint8List(
              0,
            ), // TODO: not nice to need to put this dummy value here
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
        payload: Uint8List(
          0,
        ), // TODO: not nice to need to put this dummy value here
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
              final result = Message.parse(msgBuffer, network);
              switch (result) {
                case Ok():
                  final message = Message.fromBytes(msgBuffer, network);
                  logMessage(peer, message);
                  replyMessage(peer, message, socket);
                  // reset msgBuffer
                  msgBuffer = msgBuffer.sublist(
                    Message.messageHeaderSize + message.payload.length,
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

  bool checkMedianTimePast(BlockHeader header) {
    // block time must be greater then the median time of the last 11 blocks
    if (blockHeaders.length < 11) {
      return true; // not enough headers to check median time
    }
    final last11Headers = blockHeaders.sublist(
      blockHeaders.length - 11,
      blockHeaders.length,
    );
    last11Headers.sort((a, b) => a.time.compareTo(b.time));
    final medianTime = last11Headers[5].time; // 6th element is the median
    if (header.time <= medianTime) {
      _log.warning(
        'Received header with invalid timestamp: ${header.time}, median time: $medianTime',
      );
      return false;
    }
    return true;
  }

  int calcNextWorkRequired(BlockHeader header) {
    // convert bits to target
    var currentBits = blockHeaders.last.nBits;
    if (network == Network.testnet4) {
      // bip 94 rule on testnet4
      currentBits =
          blockHeaders[blockHeaders.length - difficultyAdjustmentInterval]
              .nBits;
    }
    final target = BlockHeader.bitsToTarget(currentBits);
    // recalculate the difficulty
    var actualTimespan =
        blockHeaders.last.time -
        blockHeaders[blockHeaders.length - difficultyAdjustmentInterval].time;
    final expectedTimespan = 14 * 24 * 60 * 60; // 14 days in seconds
    if (actualTimespan < expectedTimespan ~/ 4) {
      _log.info(
        'Actual timespan is less than 1/4 of expected: $actualTimespan < ${expectedTimespan ~/ 4}',
      );
      actualTimespan = expectedTimespan ~/ 4;
    }
    if (actualTimespan > expectedTimespan * 4) {
      _log.info(
        'Actual timespan is more than 4x of expected: $actualTimespan > ${expectedTimespan * 4}',
      );
      actualTimespan = expectedTimespan * 4;
    }
    final ratio = actualTimespan / expectedTimespan;
    _log.info(
      'Ratio: $ratio, Actual Timespan: $actualTimespan, Expected Timespan: $expectedTimespan',
    );
    final newTarget =
        (target * BigInt.from(actualTimespan)) ~/ BigInt.from(expectedTimespan);
    final newBits = BlockHeader.targetToBits(newTarget);
    _log.info(
      'Recalculating difficulty: Old Bits: ${currentBits.toRadixString(16)}, New Bits: ${newBits.toRadixString(16)}',
    );
    // check newBits is not greater than the genesis block's nBits
    final genesisTarget = BlockHeader.bitsToTarget(blockHeaders.first.nBits);
    if (newTarget > genesisTarget) {
      _log.warning(
        'New target is greater than genesis target: $newTarget > $genesisTarget',
      );
      return blockHeaders.first.nBits;
    }
    return newBits;
  }

  int getWork(BlockHeader header) {
    // calculate new work on new epoch
    if (blockHeaders.length % difficultyAdjustmentInterval == 0) {
      return calcNextWorkRequired(header);
    }
    // reset the work required on testnet if the time between blocks is more than 20 minutes
    if (network == Network.testnet || network == Network.testnet4) {
      final lastTime = blockHeaders.last.time;
      const resetTime = 20 * 60; // 20 minutes in seconds
      var blockInterval = header.time - lastTime;
      if (blockInterval > resetTime) {
        _log.info(
          'Resetting work required on testnet due to long time since last block: $blockInterval seconds',
        );
        return blockHeaders.first.nBits; // reset to the first block's nBits
      } else if (blockHeaders.length > 2) {
        // use the last non special minimum difficulty block
        var blkIndex = blockHeaders.length - 1;
        while (blkIndex > 0 &&
            (blkIndex + 1) % difficultyAdjustmentInterval != 0 &&
            blockHeaders[blkIndex].nBits == blockHeaders.first.nBits) {
          blkIndex--;
        }
        return blockHeaders[blkIndex].nBits;
      }
    }
    // otherwise, use the last block's nBits
    return blockHeaders.last.nBits;
  }

  bool addHeaders(List<BlockHeader> headers) {
    if (blockHeaders.isEmpty) {
      _log.warning('No block headers available to validate against');
      return false; // no headers to validate against
    }
    for (final header in headers) {
      final headerHash = header.hash();
      final headerHashReversed = Uint8List.fromList(
        headerHash.reversed.toList(),
      );
      _log.info(
        'Received header: ${headerHashReversed.toHex().padLeft(64, '0')}, height: ${blockHeaders.length}, time: ${header.time - blockHeaders.last.time}s',
      );
      _log.info('header bits:     ${header.nBits.toRadixString(16)}');
      _log.info(
        'header target:   ${BlockHeader.bitsToTarget(header.nBits).toRadixString(16).padLeft(64, '0')}',
      );

      // check the previous block header hash
      if (blockHeaders.last.hash().toHex() !=
          header.previousBlockHeaderHash.toHex()) {
        _log.warning(
          'Received header with previous hash mismatch: ${header.previousBlockHeaderHash.toHex()}',
        );
        return false; // abort adding headers
      }
      // check the median time past
      if (!checkMedianTimePast(header)) {
        return false; // abort adding headers
      }
      // check testnet4 timewarp rule (bip 94)
      if (network == Network.testnet4) {
        if (blockHeaders.length % difficultyAdjustmentInterval == 0 &&
            blockHeaders.length > 1) {
          if (header.time < blockHeaders.last.time - maxTimewarp) {
            _log.warning(
              'Received header with invalid time: ${header.time}, expected greater then or equal to ${blockHeaders.last.time - maxTimewarp}',
            );
            return false; // abort adding headers
          }
        }
      }
      // get the work required
      final bits = getWork(header);
      _log.info('Work required:   ${bits.toRadixString(16).padLeft(8, '0')}');
      // check the work
      if (bits != header.nBits) {
        _log.warning(
          'Received header with different nBits: ${header.nBits.toRadixString(16)}, expected: ${bits.toRadixString(16)}',
        );
        return false; // abort adding headers
      }
      final target = BlockHeader.bitsToTarget(bits);
      final headerWork = bytesToBigInt(headerHashReversed);
      if (headerWork > target) {
        _log.warning(
          'Received header with insufficient work: ${headerHashReversed.toHex().padLeft(64, '0')} (needed: ${target.toRadixString(16).padLeft(64, '0')})',
        );
        return false; // abort adding headers
      }
      blockHeaders.add(header);
    }
    _log.info('Added ${headers.length} headers, total: ${blockHeaders.length}');
    return true;
  }
}
