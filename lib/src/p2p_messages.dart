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

class Message {
  static const magicMainnet = [0xf9, 0xbe, 0xb4, 0xd9];
  static const magicTestnet = [0x0b, 0x11, 0x09, 0x07];
  static const messageHeaderSize = 24;
  String command;
  Uint8List payload;

  Message({required this.command, required this.payload});

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
    final magic = network == Network.mainnet ? magicMainnet : magicTestnet;
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

  static Result<Message> parse(Uint8List bytes, Network network) {
    if (bytes.length < messageHeaderSize) {
      return Result.error(
        MessageHeaderTooSmallException(
          'Message bytes must be at least $messageHeaderSize bytes long',
        ),
      );
    }
    final magic = bytes.sublist(0, 4);
    if (!listEquals(
      magic,
      network == Network.mainnet ? magicMainnet : magicTestnet,
    )) {
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
    return Result.ok(Message(command: command, payload: payload));
  }

  factory Message.fromBytes(Uint8List bytes, Network network) {
    final result = parse(bytes, network);
    switch (result) {
      case Error():
        throw result.error;
      case Ok():
        switch (result.value.command) {
          case 'version':
            return MessageVersion.fromBytes(result.value.payload);
          case 'verack':
            return MessageVerack();
          case 'ping':
            return MessagePing.fromBytes(result.value.payload);
          case 'pong':
            return MessagePong.fromBytes(result.value.payload);
          case 'feefilter':
            return MessageFeeFilter.fromBytes(result.value.payload);
          case 'inv':
            return MessageInv.fromBytes(result.value.payload);
          case 'getdata':
            return MessageGetData.fromBytes(result.value.payload);
          case 'sendcmpct':
            return MessageSendcmpct.fromBytes(result.value.payload);
          case 'block':
            return MessageBlock.fromBytes(result.value.payload);
          case 'tx':
            return MessageTransaction.fromBytes(result.value.payload);
          //TODO: more message types
          default:
            return MessageUnknown(
              command: result.value.command,
              payload: result.value.payload,
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
    this.version = 70014, // Default protocol version
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
    required super.payload,
  }) : super(command: 'version') {
    if (remoteAddress != null && remoteAddress!.length != 16) {
      throw ArgumentError('Remote address must be 16 bytes (IPv6)');
    }
    if (localAddress != null && localAddress!.length != 16) {
      throw ArgumentError('Local address must be 16 bytes (IPv6)');
    }
  }

  @override
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
    // set the payload
    this.payload = payload.toBytes();
    return super.toBytes(network);
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
      payload: bytes,
    );
  }
}

class MessageVerack extends Message {
  MessageVerack() : super(command: 'verack', payload: Uint8List(0));
}

class MessageUnknown extends Message {
  MessageUnknown({required super.command, required super.payload});
}

class MessagePing extends Message {
  int nonce;

  MessagePing({required this.nonce, required super.payload})
    : super(command: 'ping');

  @override
  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(setUint64JsSafe(nonce, endian: Endian.little));
    this.payload = payload.toBytes();
    return super.toBytes(network);
  }

  factory MessagePing.fromBytes(Uint8List bytes) {
    if (bytes.length != 8) {
      throw FormatException('Ping message bytes must be exactly 8 bytes long');
    }
    final nonce = getUint64JsSafe(bytes, endian: Endian.little);
    return MessagePing(nonce: nonce, payload: bytes);
  }
}

class MessagePong extends Message {
  int nonce;

  MessagePong({required this.nonce, required super.payload})
    : super(command: 'pong');

  @override
  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(setUint64JsSafe(nonce, endian: Endian.little));
    this.payload = payload.toBytes();
    return super.toBytes(network);
  }

  factory MessagePong.fromBytes(Uint8List bytes) {
    if (bytes.length != 8) {
      throw FormatException('Pong message bytes must be exactly 8 bytes long');
    }
    final nonce = getUint64JsSafe(bytes, endian: Endian.little);
    return MessagePong(nonce: nonce, payload: bytes);
  }
}

class MessageFeeFilter extends Message {
  int feeRate;

  MessageFeeFilter({required this.feeRate, required super.payload})
    : super(command: 'feefilter') {
    if (feeRate < 0) {
      throw ArgumentError('Fee rate must be non-negative');
    }
  }

  @override
  Uint8List toBytes(Network network) {
    payload = setUint64JsSafe(feeRate, endian: Endian.little);
    return super.toBytes(network);
  }

  factory MessageFeeFilter.fromBytes(Uint8List bytes) {
    if (bytes.length != 8) {
      throw FormatException(
        'FeeFilter message bytes must be exactly 8 bytes long',
      );
    }
    final feeRate = getUint64JsSafe(bytes, endian: Endian.little);
    return MessageFeeFilter(feeRate: feeRate, payload: bytes);
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

  MessageInv({required this.inventory, required super.payload})
    : super(command: 'inv') {
    if (inventory.isEmpty) {
      throw ArgumentError('Inventory cannot be empty');
    }
  }

  @override
  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(compactSize(inventory.length));
    for (final item in inventory) {
      payload.add(item.toBytes());
    }
    this.payload = payload.toBytes();
    return super.toBytes(network);
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
    return MessageInv(inventory: inventory, payload: bytes);
  }
}

class MessageGetData extends MessageInv {
  MessageGetData({required super.inventory, required super.payload}) {
    command = 'getdata';
  }

  @override
  Uint8List toBytes(Network network) {
    // The payload for getdata is the same as for inv
    return super.toBytes(network);
  }

  factory MessageGetData.fromBytes(Uint8List bytes) {
    // The payload for getdata is the same as for inv
    final msg = MessageInv.fromBytes(bytes);
    return MessageGetData(inventory: msg.inventory, payload: msg.payload);
  }
}

class MessageSendcmpct extends Message {
  int enabled;
  int version;

  MessageSendcmpct({
    required this.enabled,
    required this.version,
    required super.payload,
  }) : super(command: 'sendcmpct');

  @override
  Uint8List toBytes(Network network) {
    final payload = BytesBuilder();
    payload.add(
      Uint8List.fromList([
        enabled == 1 ? 1 : 0,
        ...setUint64JsSafe(version, endian: Endian.little),
      ]),
    );
    this.payload = payload.toBytes();
    return super.toBytes(network);
  }

  factory MessageSendcmpct.fromBytes(Uint8List bytes) {
    if (bytes.length != 9) {
      throw FormatException(
        'Sendcmpct message bytes must be exactly 9 bytes long',
      );
    }
    final enabled = bytes[0];
    final version = getUint64JsSafe(bytes.sublist(1), endian: Endian.little);
    return MessageSendcmpct(enabled: enabled, version: version, payload: bytes);
  }
}

class MessageBlock extends Message {
  Block block;

  MessageBlock({required this.block, required super.payload})
    : super(command: 'block');

  @override
  Uint8List toBytes(Network network) {
    payload = block.toBytes();
    return super.toBytes(network);
  }

  factory MessageBlock.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw FormatException('Block message bytes cannot be empty');
    }
    return MessageBlock(block: Block.fromBytes(bytes), payload: bytes);
  }
}

class MessageTransaction extends Message {
  Transaction transaction;

  MessageTransaction({required this.transaction, required super.payload})
    : super(command: 'tx');

  @override
  Uint8List toBytes(Network network) {
    payload = transaction.toBytes();
    return super.toBytes(network);
  }

  factory MessageTransaction.fromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      throw FormatException('Transaction message bytes cannot be empty');
    }
    return MessageTransaction(
      transaction: Transaction.fromBytes(bytes),
      payload: bytes,
    );
  }
}
