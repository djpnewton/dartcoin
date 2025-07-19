import 'dart:typed_data';

import 'common.dart';
import 'utils.dart';
import 'transaction.dart';

class BlockHeader {
  int version;
  Uint8List previousBlockHeaderHash;
  Uint8List merkleRootHash;
  int time;
  int nBits;
  int nonce;

  static const int blockHeaderSize = 80;

  BlockHeader({
    required this.version,
    required this.previousBlockHeaderHash,
    required this.merkleRootHash,
    required this.time,
    required this.nBits,
    required this.nonce,
  });

  Uint8List hash() => hash256(toBytes());

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
    if (bytes.length != blockHeaderSize) {
      throw FormatException(
        'Block header must be exactly $blockHeaderSize bytes long',
      );
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
    if (bytes.length < BlockHeader.blockHeaderSize + 1) {
      throw FormatException(
        'Block bytes must be at least ${BlockHeader.blockHeaderSize + 1} bytes long',
      );
    }
    final header = BlockHeader.fromBytes(
      bytes.sublist(0, BlockHeader.blockHeaderSize),
    );
    final cspr = compactSizeParse(bytes.sublist(BlockHeader.blockHeaderSize));
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

  static Block genesisBlock(Network network) {
    final blockData = hexToBytes(switch (network) {
      Network.mainnet =>
        '0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a29ab5f49ffff001d1dac2b7c0101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4d04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73ffffffff0100f2052a01000000434104678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5fac00000000',
      Network.testnet =>
        '0100000000000000000000000000000000000000000000000000000000000000000000003ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4adae5494dffff001d1aa4ae180101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff4d04ffff001d0104455468652054696d65732030332f4a616e2f32303039204368616e63656c6c6f72206f6e206272696e6b206f66207365636f6e64206261696c6f757420666f722062616e6b73ffffffff0100f2052a01000000434104678afdb0fe5548271967f1a67130b7105cd6a828e03909a67962e0ea1f61deb649f6bc3f4cef38c4f35504e51ec112de5c384df7ba0b8d578a4c702b6bf11d5fac00000000',
      Network.testnet4 =>
        '0100000000000000000000000000000000000000000000000000000000000000000000004e7b2b9128fe0291db0693af2ae418b767e657cd407e80cb1434221eaea7a07a046f3566ffff001dbb0c78170101000000010000000000000000000000000000000000000000000000000000000000000000ffffffff5504ffff001d01044c4c30332f4d61792f323032342030303030303030303030303030303030303030303165626435386332343439373062336161396437383362623030313031316662653865613865393865303065ffffffff0100f2052a010000002321000000000000000000000000000000000000000000000000000000000000000000ac00000000',
    });
    return Block.fromBytes(blockData);
  }
}
