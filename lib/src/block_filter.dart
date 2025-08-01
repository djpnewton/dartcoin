import 'dart:math';
import 'dart:typed_data';

import 'block.dart';
import 'utils.dart';
import 'siphash.dart';
import 'bits.dart';

//
// BasicBlockFilter implmements the bip 158 block filter
//
class BasicBlockFilter {
  static const int filterType = 0x00;
  static const int M = 784931;
  static const int P = 19;
  // ignore: constant_identifier_names
  static const int OP_RETURN = 0x6a;

  static final genesisPreviousHeader = Uint8List(32);

  late final Uint8List filterBytes;
  late final Uint8List filterHash;

  BasicBlockFilter({required Block block}) {
    // get the key for the block
    final key = Uint8List.fromList(block.header.hash().take(16).toList());
    // collect items skipping coinbase transaction
    final initialItems = <Uint8List>[];
    for (int i = 0; i < block.transactions.length; i++) {
      final tx = block.transactions[i];
      // collect all scriptPubKeys from outputs
      for (final output in tx.outputs) {
        // skip empty scriptPubKeys or OP_RETURNs
        if (output.scriptPubKey.isEmpty) continue;
        if (output.scriptPubKey[0] == OP_RETURN) continue;
        initialItems.add(output.scriptPubKey);
      }
      // skip coinbase transaction inputs
      if (i == 0) continue;
      // collect scriptPubKeys spent by inputs
      for (final _ in tx.inputs) {
        throw UnimplementedError(
          'Collecting spent scriptPubKeys from input.txid & input.vout not implemented yet',
        );
      }
    }
    // hash items to the range [0, N*M)
    final hashedItems = <BigInt>[];
    final n = initialItems.length;
    final f = BigInt.from(n) * BigInt.from(M);
    for (final item in initialItems) {
      hashedItems.add((siphash(item, key) * f) >> 64);
    }
    // sort the items
    hashedItems.sort((BigInt a, BigInt b) => a.compareTo(b));
    // remove any duplicates
    for (int i = 1; i < hashedItems.length; i++) {
      if (hashedItems[i] == hashedItems[i - 1]) {
        hashedItems.removeAt(i);
        i--;
      }
    }
    // convert to list of differences
    final differences = <int>[];
    for (int i = 0; i < hashedItems.length; i++) {
      final value = hashedItems[i].toInt();
      if (i == 0) {
        differences.add(value);
      } else {
        differences.add(value - hashedItems[i - 1].toInt());
      }
    }
    // for each difference, calculate the quotient and remainder after dividing by 2^P
    // we will use these values to construct the filter
    final twoP = pow(2, P).toInt();
    final filter = BitsWriter();
    for (final d in differences) {
      final quotient = (d / twoP).floor();
      final remainder = d - (twoP * quotient);
      // add the quotient and remainder to the filter bytes
      for (int i = 0; i < quotient; i++) {
        filter.writeBit(true);
      }
      filter.writeBit(false);
      filter.writeBits(remainder, P);
    }
    // final filter bytes has 'n' as compactSize followed by the filter bits
    final bb = BytesBuilder()
      ..add(compactSize(n))
      ..add(filter.toBytes());
    filterBytes = bb.toBytes();
    // calculate the filter header
    filterHash = hash256(filterBytes);
  }

  static Uint8List filterHeader(
    Uint8List filterHash,
    Uint8List previousFilterHeader,
  ) {
    return Uint8List.fromList(
      hash256(Uint8List.fromList(filterHash + previousFilterHeader)),
    );
  }

  static String filterHeaderNice(Uint8List filterHeader) {
    return Uint8List.fromList(filterHeader.reversed.toList()).toHex();
  }
}
