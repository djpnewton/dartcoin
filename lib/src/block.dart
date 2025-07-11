import 'dart:typed_data';

import 'utils.dart';
import 'transaction.dart';

class BlockHeader {
  int version;
  Uint8List previousBlockHeaderHash;
  Uint8List merkleRootHash;
  int time;
  int nBits;
  int nonce;

  BlockHeader({
    required this.version,
    required this.previousBlockHeaderHash,
    required this.merkleRootHash,
    required this.time,
    required this.nBits,
    required this.nonce,
  });

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    buffer.add(
      Uint8List(4)..buffer.asByteData().setInt32(0, version, Endian.little),
    );
    buffer.add(previousBlockHeaderHash);
    buffer.add(merkleRootHash);
    buffer.add(
      Uint8List(4)..buffer.asByteData().setInt32(0, time, Endian.little),
    );
    buffer.add(
      Uint8List(4)..buffer.asByteData().setInt32(0, nBits, Endian.little),
    );
    buffer.add(
      Uint8List(4)..buffer.asByteData().setInt32(0, nonce, Endian.little),
    );
    return buffer.toBytes();
  }

  factory BlockHeader.fromBytes(Uint8List bytes) {
    if (bytes.length != 80) {
      throw FormatException('Block header must be exactly 80 bytes long');
    }
    final buffer = ByteData.sublistView(bytes);
    int offset = 0;

    final version = buffer.getInt32(offset, Endian.little);
    offset += 4;
    final previousBlockHeaderHash = bytes.sublist(offset, offset + 32);
    offset += 32;
    final merkleRootHash = bytes.sublist(offset, offset + 32);
    offset += 32;
    final time = buffer.getInt32(offset, Endian.little);
    offset += 4;
    final nBits = buffer.getInt32(offset, Endian.little);
    offset += 4;
    final nonce = buffer.getInt32(offset, Endian.little);

    return BlockHeader(
      version: version,
      previousBlockHeaderHash: previousBlockHeaderHash,
      merkleRootHash: merkleRootHash,
      time: time,
      nBits: nBits,
      nonce: nonce,
    );
  }
}

class Block {
  BlockHeader header;
  List<Transaction> transactions;

  Block({required this.header, required this.transactions});

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    buffer.add(header.toBytes());
    buffer.add(compactSize(transactions.length));
    for (final tx in transactions) {
      buffer.add(tx.toBytes());
    }
    return buffer.toBytes();
  }

  factory Block.fromBytes(Uint8List bytes) {
    if (bytes.length < 81) {
      throw FormatException('Block bytes must be at least 81 bytes long');
    }
    final header = BlockHeader.fromBytes(bytes.sublist(0, 80));
    final cspr = compactSizeParse(bytes.sublist(80));
    final transactionCount = cspr.value;
    final transactions = <Transaction>[];
    int offset = 80 + cspr.bytesRead;
    for (int i = 0; i < transactionCount; i++) {
      final tx = Transaction.fromBytes(bytes.sublist(offset));
      transactions.add(tx);
      offset += tx.toBytes().length;
    }
    return Block(header: header, transactions: transactions);
  }
}
