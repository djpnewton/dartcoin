import 'dart:convert';
import 'dart:typed_data';

import 'common.dart';
import 'utils.dart';
import 'result.dart';
import 'block.dart';
import 'transaction.dart';

class MessageHeaderException implements Exception {
  final String message;

  MessageHeaderException(this.message);

  @override
  String toString() => 'MessageHeaderException: $message';
}

class MessageHeaderTooSmallException extends MessageHeaderException {
  MessageHeaderTooSmallException(super.message);
}

class MessageHeaderMagicMismatchException extends MessageHeaderException {
  MessageHeaderMagicMismatchException(super.message);
}

class MessageHeaderChecksumExceedsException extends MessageHeaderException {
  MessageHeaderChecksumExceedsException(super.message);
}

class MessageHeaderPayloadExceedsException extends MessageHeaderException {
  MessageHeaderPayloadExceedsException(super.message);
}

class MessageHeaderChecksumMismatchException extends MessageHeaderException {
  MessageHeaderChecksumMismatchException(super.message);
}

class MessageHeader {
  static const magicMainnet = [0xf9, 0xbe, 0xb4, 0xd9];
  static const magicTestnet = [0x0b, 0x11, 0x09, 0x07];
  static const magicTestnet4 = [0x1c, 0x16, 0x3f, 0x28];
  static const magicRegtest = [0xfa, 0xbf, 0xb5, 0xda];
  static const messageHeaderSize = 24;
  String command;
  Uint8List payload;

  MessageHeader({required this.command, required this.payload});

  static Uint8List checksum(Uint8List data) {
    return hash256(data).sublist(0, 4);
  }

  Uint8List _commandToBytes() {
    final result = utf8.encode(command);
    if (result.length > 12) {
      throw ArgumentError('Command must be at most 12 bytes long');
    }
    return Uint8List.fromList(result + List.filled(12 - result.length, 0));
  }

  Uint8List toBytes(Network network) {
    final magic = switch (network) {
      Network.mainnet => magicMainnet,
      Network.testnet => magicTestnet,
      Network.testnet4 => magicTestnet4,
      Network.regtest => magicRegtest,
    };
    final buffer = BytesBuilder();
    buffer.add(magic);
    buffer.add(_commandToBytes());
    buffer.add(
      Uint8List(4)
        ..buffer.asByteData().setUint32(0, payload.length, Endian.little),
    );
    buffer.add(checksum(payload));
    buffer.add(payload);
    return buffer.toBytes();
  }

  static Result<MessageHeader> parse(Uint8List bytes, Network network) {
    if (bytes.length < messageHeaderSize) {
      return Result.error(
        MessageHeaderTooSmallException(
          'Message bytes must be at least $messageHeaderSize bytes long',
        ),
      );
    }
    final magic = bytes.sublist(0, 4);
    if (!listEquals(magic, switch (network) {
      Network.mainnet => magicMainnet,
      Network.testnet => magicTestnet,
      Network.testnet4 => magicTestnet4,
      Network.regtest => magicRegtest,
    })) {
      return Result.error(
        MessageHeaderMagicMismatchException(
          'Invalid magic number ${magic.toHex()}',
        ),
      );
    }
    final command = utf8.decode(bytes.sublist(4, 16)).split('\x00')[0];
    final payloadSize = bytes.buffer.asByteData().getUint32(16, Endian.little);
    if (24 > bytes.length) {
      return Result.error(
        MessageHeaderChecksumExceedsException(
          ('Checksum field exceeds remaining bytes'),
        ),
      );
    }
    final chksum = bytes.sublist(20, 24);
    if (24 + payloadSize > bytes.length) {
      return Result.error(
        MessageHeaderPayloadExceedsException(
          'Payload field exceeds remaining bytes ($command, $payloadSize))',
        ),
      );
    }
    final payload = bytes.sublist(24, 24 + payloadSize);

    // check checksum
    final expectedChecksum = checksum(payload);
    if (!listEquals(expectedChecksum, chksum)) {
      return Result.error(
        MessageHeaderChecksumMismatchException(
          'Invalid checksum got ${chksum.toHex()}, '
          'expected ${expectedChecksum.toHex()}',
        ),
      );
    }

    // return parsed message header
    return Result.ok(MessageHeader(command: command, payload: payload));
  }
}

class Message {
  static const version = 70015; // Default protocol version
  static const nodeCompactFilters =
      1 << 6; // supports BIP 157 messages for filter type 0x00

  Message();

  static (Message, MessageHeader) fromBytes(Uint8List bytes, Network network) {
    final result = MessageHeader.parse(bytes, network);
    switch (result) {
      case Error():
        throw result.error;
      case Ok():
        switch (result.value.command) {
          case 'version':
            return (
              MessageVersion.fromBytes(result.value.payload),
              result.value,
            );
          case 'verack':
            return (MessageVerack(), result.value);
          case 'ping':
            return (MessagePing.fromBytes(result.value.payload), result.value);
          case 'pong':
            return (MessagePong.fromBytes(result.value.payload), result.value);
          case 'feefilter':
            return (
              MessageFeeFilter.fromBytes(result.value.payload),
              result.value,
            );
          case 'inv':
            return (MessageInv.fromBytes(result.value.payload), result.value);
          case 'getdata':
            return (
              MessageGetData.fromBytes(result.value.payload),
              result.value,
            );
          case 'sendcmpct':
            return (
              MessageSendcmpct.fromBytes(result.value.payload),
              result.value,
            );
          case 'block':
            return (MessageBlock.fromBytes(result.value.payload), result.value);
          case 'tx':
            return (
              MessageTransaction.fromBytes(result.value.payload),
              result.value,
            );
          case 'addr':
            return (
              MessageAddress.fromBytes(result.value.payload),
              result.value,
            );
          case 'getheaders':
            return (
              MessageGetHeaders.fromBytes(result.value.payload),
              result.value,
            );
          case 'headers':
            return (
              MessageHeaders.fromBytes(result.value.payload),
              result.value,
            );
          case 'getcfheaders':
            return (
              MessageGetCfHeaders.fromBytes(result.value.payload),
              result.value,
            );
          case 'cfheaders':
            return (
              MessageCfHeaders.fromBytes(result.value.payload),
              result.value,
            );
          //TODO: more message types
          default:
            return (
              MessageUnknown(
                command: result.value.command,
                payload: result.value.payload,
              ),
              result.value,
            );
        }
    }
  }
}

class MessageVersion extends Message {
  int version;
  int serviceFlags;
  int timestamp;
  int? remoteServiceFlags;
  Uint8List? remoteAddress;
  int? remotePort;
  int? localServiceFlags;
  Uint8List? localAddress;
  int? localPort;
  int? nonce;
  String userAgent;
  int lastBlock;
  bool relay;

  MessageVersion({
    this.version = Message.version, // Default protocol version
    this.serviceFlags = 0,
    required this.timestamp,
    this.remoteServiceFlags,
    this.remoteAddress, // IPv6 address
    this.remotePort,
    this.localServiceFlags,
    this.localAddress, // IPv6 address
    this.localPort,
    this.nonce,
    required this.userAgent,
    required this.lastBlock,
    required this.relay,
  }) {
    if (remoteAddress != null && remoteAddress!.length != 16) {
      throw ArgumentError('Remote address must be 16 bytes (IPv6)');
    }
    if (localAddress != null && localAddress!.length != 16) {
      throw ArgumentError('Local address must be 16 bytes (IPv6)');
    }
  }

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    // protocol version
    payload.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, version, Endian.little),
    );
    // service flags
    payload.add(setUint64JsSafe(serviceFlags, endian: Endian.little));
    // unix epoch timestamp
    payload.add(setUint64JsSafe(timestamp, endian: Endian.little));
    // remote service flags
    payload.add(
      setUint64JsSafe(remoteServiceFlags ?? 0, endian: Endian.little),
    );
    // remote IPv6 address
    if (remoteAddress != null && remoteAddress!.length != 16) {
      throw ArgumentError('Remote address must be 16 bytes (IPv6)');
    }
    payload.add(remoteAddress ?? Uint8List(16));
    // remote port
    payload.add(
      Uint8List(2)
        ..buffer.asByteData().setUint16(0, remotePort ?? 0, Endian.big),
    );
    // local service flags
    payload.add(setUint64JsSafe(localServiceFlags ?? 0, endian: Endian.little));
    // local IPv6 address
    if (localAddress != null && localAddress!.length != 16) {
      throw ArgumentError('Local address must be 16 bytes (IPv6)');
    }
    payload.add(localAddress ?? Uint8List(16));
    // local port
    payload.add(
      Uint8List(2)
        ..buffer.asByteData().setUint16(0, localPort ?? 0, Endian.big),
    );
    // nonce
    payload.add(setUint64JsSafe(nonce ?? 0, endian: Endian.little));
    // user agent
    final userAgentBytes = utf8.encode(userAgent);
    final userAgentSize = compactSize(userAgentBytes.length);
    payload.add(userAgentSize);
    payload.add(Uint8List.fromList(userAgentBytes));
    // last block
    payload.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, lastBlock, Endian.little),
    );
    // relay flag
    payload.add(relay ? Uint8List.fromList([1]) : Uint8List.fromList([0]));
    // generate the message including header
    final msgHeader = MessageHeader(
      command: 'version',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessageVersion.fromBytes(Uint8List bytes) {
    final buffer = ByteData.sublistView(bytes);
    int offset = 0;

    if (offset + 4 > bytes.length) {
      throw FormatException('Version field exceeds remaining bytes');
    }
    final version = buffer.getUint32(offset, Endian.little);
    offset += 4;
    if (offset + 8 > bytes.length) {
      throw FormatException('Service flags field exceeds remaining bytes');
    }
    final services = getUint64JsSafe(
      bytes.sublist(offset),
      endian: Endian.little,
    );

    offset += 8;

    if (offset + 8 > bytes.length) {
      throw FormatException('Timestamp field exceeds remaining bytes');
    }
    final timestamp = getUint64JsSafe(
      bytes.sublist(offset),
      endian: Endian.little,
    );
    offset += 8;

    if (offset + 8 > bytes.length) {
      throw FormatException('Remote services field exceeds remaining bytes');
    }
    final remoteServices = getUint64JsSafe(
      bytes.sublist(offset),
      endian: Endian.little,
    );
    offset += 8;

    if (offset + 16 > bytes.length) {
      throw FormatException('Remote address field exceeds remaining bytes');
    }
    final remoteAddress = bytes.sublist(offset, offset + 16); // IPv6 address
    offset += 16;

    if (offset + 2 > bytes.length) {
      throw FormatException('Remote port field exceeds remaining bytes');
    }
    final remotePort = buffer.getUint16(offset, Endian.big);
    offset += 2;

    if (offset + 8 > bytes.length) {
      throw FormatException('Local services field exceeds remaining bytes');
    }
    final localServices = getUint64JsSafe(
      bytes.sublist(offset),
      endian: Endian.little,
    );
    offset += 8;

    if (offset + 16 > bytes.length) {
      throw FormatException('Local address field exceeds remaining bytes');
    }
    final localAddress = bytes.sublist(offset, offset + 16); // IPv6 address
    offset += 16;

    if (offset + 2 > bytes.length) {
      throw FormatException('Local port field exceeds remaining bytes');
    }
    final localPort = buffer.getUint16(offset, Endian.big);
    offset += 2;

    if (offset + 8 > bytes.length) {
      throw FormatException('Nonce field exceeds remaining bytes');
    }
    final nonce = getUint64JsSafe(bytes.sublist(offset), endian: Endian.little);
    offset += 8;

    final userAgentSize = compactSizeParse(bytes.sublist(offset));
    offset += userAgentSize.bytesRead;
    final userAgentBytes = bytes.sublist(offset, offset + userAgentSize.value);
    final userAgent = utf8.decode(userAgentBytes);
    offset += userAgentSize.value;

    if (offset + 4 > bytes.length) {
      throw FormatException('Last block field exceeds remaining bytes');
    }
    final lastBlock = buffer.getUint32(offset, Endian.little);
    offset += 4;

    if (offset >= bytes.length) {
      throw FormatException('Relay flag field exceeds remaining bytes');
    }
    final relayFlag = bytes[offset] == 1;

    return MessageVersion(
      version: version,
      serviceFlags: services,
      timestamp: timestamp,
      remoteServiceFlags: remoteServices,
      remoteAddress: remoteAddress,
      remotePort: remotePort,
      localServiceFlags: localServices,
      localAddress: localAddress,
      localPort: localPort,
      nonce: nonce,
      userAgent: userAgent,
      lastBlock: lastBlock,
      relay: relayFlag,
    );
  }
}

class MessageVerack extends Message {
  MessageVerack();

  Uint8List toBytes(Network network) {
    // The verack message has no payload, so we just return the header
    final msgHeader = MessageHeader(command: 'verack', payload: Uint8List(0));
    return msgHeader.toBytes(network);
  }
}

class MessageUnknown extends Message {
  String command;
  Uint8List payload;

  MessageUnknown({required this.command, required this.payload});
}

class MessagePing extends Message {
  int nonce;

  MessagePing({required this.nonce});

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(setUint64JsSafe(nonce, endian: Endian.little));
    final msgHeader = MessageHeader(
      command: 'ping',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessagePing.fromBytes(Uint8List bytes) {
    if (bytes.length != 8) {
      throw FormatException('Ping message bytes must be exactly 8 bytes long');
    }
    final nonce = getUint64JsSafe(bytes, endian: Endian.little);
    return MessagePing(nonce: nonce);
  }
}

class MessagePong extends Message {
  int nonce;

  MessagePong({required this.nonce});

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(setUint64JsSafe(nonce, endian: Endian.little));
    final msgHeader = MessageHeader(
      command: 'pong',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessagePong.fromBytes(Uint8List bytes) {
    if (bytes.length != 8) {
      throw FormatException('Pong message bytes must be exactly 8 bytes long');
    }
    final nonce = getUint64JsSafe(bytes, endian: Endian.little);
    return MessagePong(nonce: nonce);
  }
}

class MessageFeeFilter extends Message {
  int feeRate;

  MessageFeeFilter({required this.feeRate}) {
    if (feeRate < 0) {
      throw ArgumentError('Fee rate must be non-negative');
    }
  }

  Uint8List toBytes(Network network) {
    final payload = setUint64JsSafe(feeRate, endian: Endian.little);
    final msgHeader = MessageHeader(command: 'feefilter', payload: payload);
    return msgHeader.toBytes(network);
  }

  factory MessageFeeFilter.fromBytes(Uint8List bytes) {
    if (bytes.length != 8) {
      throw FormatException(
        'FeeFilter message bytes must be exactly 8 bytes long',
      );
    }
    final feeRate = getUint64JsSafe(bytes, endian: Endian.little);
    return MessageFeeFilter(feeRate: feeRate);
  }
}

enum InventoryType { msgTx, msgBlock }

class InventoryItem {
  InventoryType type;
  Uint8List hash;

  InventoryItem({required this.type, required this.hash}) {
    if (hash.length != 32) {
      throw ArgumentError('Hash must be 32 bytes long');
    }
  }

  Uint8List toBytes() {
    int typeValue = switch (type) {
      InventoryType.msgTx => 1,
      InventoryType.msgBlock => 2,
    };
    final typeBuffer = Uint8List(4);
    typeBuffer.buffer.asByteData().setUint32(0, typeValue, Endian.little);
    return Uint8List.fromList(typeBuffer + hash);
  }

  factory InventoryItem.fromBytes(Uint8List bytes) {
    if (bytes.length != 36) {
      throw FormatException(
        'Inventory item bytes must be exactly 36 bytes long',
      );
    }
    final typeValue = bytes.buffer.asByteData().getUint32(0, Endian.little);
    final type = switch (typeValue) {
      1 => InventoryType.msgTx,
      2 => InventoryType.msgBlock,
      _ => throw FormatException('Invalid inventory type: $typeValue'),
    };
    final hash = bytes.sublist(4);
    return InventoryItem(type: type, hash: hash);
  }
}

class MessageInv extends Message {
  List<InventoryItem> inventory;

  MessageInv({required this.inventory}) {
    if (inventory.isEmpty) {
      throw ArgumentError('Inventory cannot be empty');
    }
  }

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(compactSize(inventory.length));
    for (final item in inventory) {
      payload.add(item.toBytes());
    }
    final msgHeader = MessageHeader(command: 'inv', payload: payload.toBytes());
    return msgHeader.toBytes(network);
  }

  factory MessageInv.fromBytes(Uint8List bytes) {
    final cspr = compactSizeParse(bytes);
    var offset = cspr.bytesRead;
    final inventory = <InventoryItem>[];
    while (offset + 36 <= bytes.length) {
      final itemBytes = bytes.sublist(offset, offset + 36);
      inventory.add(InventoryItem.fromBytes(itemBytes));
      offset += 36;
    }
    if (inventory.length != cspr.value) {
      throw FormatException(
        'Expected ${cspr.value} inventory items, but found ${inventory.length}',
      );
    }
    if (inventory.isEmpty) {
      throw FormatException('Inventory cannot be empty');
    }
    return MessageInv(inventory: inventory);
  }
}

class MessageGetData extends MessageInv {
  MessageGetData({required super.inventory});

  @override
  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(compactSize(inventory.length));
    for (final item in inventory) {
      payload.add(item.toBytes());
    }
    final msgHeader = MessageHeader(
      command: 'getdata',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessageGetData.fromBytes(Uint8List bytes) {
    // The payload for getdata is the same as for inv
    final msg = MessageInv.fromBytes(bytes);
    return MessageGetData(inventory: msg.inventory);
  }
}

class MessageSendcmpct extends Message {
  int enabled;
  int version;

  MessageSendcmpct({required this.enabled, required this.version});

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(
      Uint8List.fromList([
        enabled == 1 ? 1 : 0,
        ...setUint64JsSafe(version, endian: Endian.little),
      ]),
    );
    final msgHeader = MessageHeader(
      command: 'sendcmpct',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessageSendcmpct.fromBytes(Uint8List bytes) {
    if (bytes.length != 9) {
      throw FormatException(
        'Sendcmpct message bytes must be exactly 9 bytes long',
      );
    }
    final enabled = bytes[0];
    final version = getUint64JsSafe(bytes.sublist(1), endian: Endian.little);
    return MessageSendcmpct(enabled: enabled, version: version);
  }
}

class MessageBlock extends Message {
  Block block;

  MessageBlock({required this.block});

  Uint8List toBytes(Network network) {
    final payload = block.toBytes();
    final msgHeader = MessageHeader(command: 'block', payload: payload);
    return msgHeader.toBytes(network);
  }

  factory MessageBlock.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw FormatException('Block message bytes cannot be empty');
    }
    return MessageBlock(block: Block.fromBytes(bytes));
  }
}

class MessageTransaction extends Message {
  Transaction transaction;

  MessageTransaction({required this.transaction});

  Uint8List toBytes(Network network) {
    final payload = transaction.toBytes();
    final msgHeader = MessageHeader(command: 'tx', payload: payload);
    return msgHeader.toBytes(network);
  }

  factory MessageTransaction.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw FormatException('Transaction message bytes cannot be empty');
    }
    return MessageTransaction(transaction: Transaction.fromBytes(bytes));
  }
}

class Address {
  int time;
  int services;
  Uint8List ipAddress; // IPv6 address
  int port;

  Address({
    required this.time,
    required this.services,
    required this.ipAddress,
    required this.port,
  }) {
    if (ipAddress.length != 16) {
      throw ArgumentError('IP address must be 16 bytes (IPv6)');
    }
    if (port < 0 || port > 65535) {
      throw ArgumentError('Port must be between 0 and 65535');
    }
  }

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    buffer.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, time, Endian.little),
    );
    buffer.add(setUint64JsSafe(services, endian: Endian.little));
    buffer.add(ipAddress);
    buffer.add(
      Uint8List(2)..buffer.asByteData().setUint16(0, port, Endian.big),
    );
    return buffer.toBytes();
  }

  factory Address.fromBytes(Uint8List bytes) {
    if (bytes.length != 30) {
      throw FormatException('Address bytes must be exactly 30 bytes long');
    }
    final buffer = ByteData.sublistView(bytes);
    int offset = 0;

    final time = buffer.getUint32(offset, Endian.little);
    offset += 4;
    final services = getUint64JsSafe(
      bytes.sublist(offset),
      endian: Endian.little,
    );
    offset += 8;
    final ipAddress = bytes.sublist(offset, offset + 16); // IPv6 address
    offset += 16;
    final port = buffer.getUint16(offset, Endian.big);

    return Address(
      time: time,
      services: services,
      ipAddress: ipAddress,
      port: port,
    );
  }
}

class MessageAddress extends Message {
  List<Address> addresses;

  MessageAddress({required this.addresses}) {
    if (addresses.isEmpty) {
      throw ArgumentError('Addresses cannot be empty');
    }
  }

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(compactSize(addresses.length));
    for (final address in addresses) {
      payload.add(address.toBytes());
    }
    final msgHeader = MessageHeader(
      command: 'addr',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessageAddress.fromBytes(Uint8List bytes) {
    final cspr = compactSizeParse(bytes);
    var offset = cspr.bytesRead;
    final addresses = <Address>[];
    while (offset + 30 <= bytes.length) {
      final addrBytes = bytes.sublist(offset, offset + 30);
      addresses.add(Address.fromBytes(addrBytes));
      offset += 30;
    }
    if (addresses.length != cspr.value) {
      throw FormatException(
        'Expected ${cspr.value} addresses, but found ${addresses.length}',
      );
    }
    if (addresses.isEmpty) {
      throw FormatException('Addresses cannot be empty');
    }
    return MessageAddress(addresses: addresses);
  }
}

class MessageGetHeaders extends Message {
  int version;
  List<Uint8List> headerHashes;

  MessageGetHeaders({
    this.version = Message.version,
    required this.headerHashes,
  }) {
    if (headerHashes.isEmpty) {
      throw ArgumentError('Header hashes cannot be empty');
    }
    if (headerHashes.isNotEmpty && headerHashes.any((h) => h.length != 32)) {
      throw ArgumentError('Each header hash must be 32 bytes long');
    }
  }

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, version, Endian.little),
    );
    payload.add(compactSize(headerHashes.length));
    for (final hash in headerHashes) {
      payload.add(hash);
    }
    payload.add(Uint8List(32)); // Stop hash (32 bytes of zeros)
    final msgHeader = MessageHeader(
      command: 'getheaders',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessageGetHeaders.fromBytes(Uint8List bytes) {
    if (bytes.length < 4 + 1 + 32) {
      throw FormatException(
        'GetHeaders message bytes must be at least 37 bytes long',
      );
    }
    final version = bytes.buffer.asByteData().getUint32(0, Endian.little);
    var offset = 4;
    final cspr = compactSizeParse(bytes);
    offset += cspr.bytesRead;
    final headerHashes = <Uint8List>[];
    while (offset + 32 <= bytes.length) {
      final hashBytes = bytes.sublist(offset, offset + 32);
      headerHashes.add(hashBytes);
      offset += 32;
    }
    if (headerHashes.length != cspr.value + 1) {
      throw FormatException(
        'Expected ${cspr.value} header hashes, but found ${headerHashes.length}',
      );
    }
    // The last hash is the stop hash, which should be 32 bytes of zeros
    if (headerHashes.last.any((b) => b != 0)) {
      throw FormatException('Last header hash must be 32 bytes of zeros');
    }
    headerHashes.removeLast(); // Remove the stop hash
    return MessageGetHeaders(version: version, headerHashes: headerHashes);
  }
}

class MessageHeaders extends Message {
  List<BlockHeader> headers;

  MessageHeaders({required this.headers});

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(compactSize(headers.length));
    for (final header in headers) {
      payload.add(header.toBytes());
      payload.add([0x00]); // additional 0x00 ('transaction count') suffix
    }
    final msgHeader = MessageHeader(
      command: 'headers',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessageHeaders.fromBytes(Uint8List bytes) {
    final cspr = compactSizeParse(bytes);
    var offset = cspr.bytesRead;
    final headers = <BlockHeader>[];
    while (offset + BlockHeader.blockHeaderSize <= bytes.length) {
      final headerBytes = bytes.sublist(
        offset,
        offset + BlockHeader.blockHeaderSize,
      );
      headers.add(BlockHeader.fromBytes(headerBytes));
      offset += BlockHeader.blockHeaderSize;
      offset++; // Skip the additional 0x00 byte
    }
    if (headers.length != cspr.value) {
      throw FormatException(
        'Expected ${cspr.value} headers, but found ${headers.length}',
      );
    }
    return MessageHeaders(headers: headers);
  }
}

class MessageGetCfHeaders extends Message {
  int filterType;
  int startHeight;
  Uint8List stopHash;

  MessageGetCfHeaders({
    required this.filterType,
    required this.startHeight,
    required this.stopHash,
  }) {
    if (stopHash.length != 32) {
      throw ArgumentError('Stop hash must be 32 bytes long');
    }
  }

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add([filterType]);
    payload.add(
      Uint8List(4)
        ..buffer.asByteData().setUint32(0, startHeight, Endian.little),
    );
    payload.add(stopHash);
    final msgHeader = MessageHeader(
      command: 'getcfheaders',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessageGetCfHeaders.fromBytes(Uint8List bytes) {
    if (bytes.length != 37) {
      throw FormatException(
        'GetCfHeaders message bytes must be exactly 37 bytes long',
      );
    }
    final filterType = bytes[0];
    final startHeight = bytes.buffer.asByteData().getUint32(1, Endian.little);
    final stopHash = bytes.sublist(5, 37);
    return MessageGetCfHeaders(
      filterType: filterType,
      startHeight: startHeight,
      stopHash: stopHash,
    );
  }
}

class MessageCfHeaders extends Message {
  int filterType;
  Uint8List stopHash;
  Uint8List previousFilterHeader;
  List<Uint8List> filterHashes;

  MessageCfHeaders({
    required this.filterType,
    required this.stopHash,
    required this.previousFilterHeader,
    required this.filterHashes,
  }) {
    if (stopHash.length != 32) {
      throw ArgumentError('Stop hash must be 32 bytes long');
    }
    if (previousFilterHeader.length != 32) {
      throw ArgumentError('Previous filter hash must be 32 bytes long');
    }
    if (filterHashes.isEmpty) {
      throw ArgumentError('Filter hashes cannot be empty');
    }
    if (filterHashes.any((h) => h.length != 32)) {
      throw ArgumentError('Each filter hash must be 32 bytes long');
    }
  }

  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add([filterType]);
    payload.add(stopHash);
    payload.add(previousFilterHeader);
    payload.add(compactSize(filterHashes.length));
    for (final hash in filterHashes) {
      payload.add(hash);
    }
    final msgHeader = MessageHeader(
      command: 'cfheaders',
      payload: payload.toBytes(),
    );
    return msgHeader.toBytes(network);
  }

  factory MessageCfHeaders.fromBytes(Uint8List bytes) {
    if (bytes.length < 66) {
      throw FormatException(
        'CfHeaders message bytes must be at least 66 bytes long',
      );
    }
    final filterType = bytes[0];
    final stopHash = bytes.sublist(1, 33);
    final previousFilterHash = bytes.sublist(33, 65);
    final cspr = compactSizeParse(bytes.sublist(65));
    if (cspr.value < 1) {
      throw FormatException('At least one filter hash is required');
    }
    var offset = 65 + cspr.bytesRead;
    final filterHashes = <Uint8List>[];
    for (int i = 0; i < cspr.value; i++) {
      if (offset + 32 > bytes.length) {
        throw FormatException(
          'Filter hash exceeds remaining bytes at index $i',
        );
      }
      final hash = bytes.sublist(offset, offset + 32);
      filterHashes.add(hash);
      offset += 32;
    }
    return MessageCfHeaders(
      filterType: filterType,
      stopHash: stopHash,
      previousFilterHeader: previousFilterHash,
      filterHashes: filterHashes,
    );
  }
}
