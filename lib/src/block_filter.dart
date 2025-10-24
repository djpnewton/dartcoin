import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'block.dart';
import 'transaction.dart';
import 'utils.dart';
import 'siphash.dart';
import 'bits.dart';
import 'common.dart';

abstract class TxProvider {
  Future<Transaction> fromTxid(String txid);
}

class BlockDnTxProvider implements TxProvider {
  late final Map<String, Transaction> _txMap;
  late final String _txEndpoint;

  BlockDnTxProvider(Network network) {
    _txMap = {};
    switch (network) {
      case Network.mainnet:
        _txEndpoint = 'https://block-dn.org/tx/raw/';
        break;
      case Network.testnet4:
        _txEndpoint = 'https://testnet4.block-dn.org/tx/raw/';
        break;
      case Network.testnet:
        _txEndpoint = 'https://testnet3.block-dn.org/tx/raw/';
        break;
      case Network.regtest:
        throw Exception('BlockDnTxProvider does not support regtest network');
    }
  }

  @override
  Future<Transaction> fromTxid(String txid) async {
    final tx = _txMap[txid] ?? await _fetchTx(txid);
    if (tx == null) {
      throw Exception(
        'Transaction with txid $txid not found in BlockDnTxProvider',
      );
    }
    return tx;
  }

  Future<Transaction?> _fetchTx(String txid) async {
    // fetch the transaction from blockdn and parse it
    final url = '$_txEndpoint$txid';
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      return null;
    }
    final txBytes = response.bodyBytes;
    final tx = Transaction.fromBytes(txBytes);
    // cache and return the transaction
    _txMap[txid] = tx;
    return tx;
  }
}

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

  BasicBlockFilter({
    required Block block,
    required List<Uint8List> prevOutputScripts,
  }) {
    // get the key for the block
    final key = Uint8List.fromList(block.header.hash().take(16).toList());
    // collect items (use map to avoid duplicates)
    final initialItems = <String, Uint8List>{};
    for (final tx in block.transactions) {
      // collect all scriptPubKeys from outputs
      for (final output in tx.outputs) {
        // skip empty scriptPubKeys or OP_RETURNs
        if (output.scriptPubKey.isEmpty) continue;
        if (output.scriptPubKey[0] == OP_RETURN) continue;
        initialItems[output.scriptPubKey.toHex()] = output.scriptPubKey;
      }
    }
    for (final script in prevOutputScripts) {
      if (script.isEmpty) continue; // skip empty scripts
      initialItems[script.toHex()] = script;
    }
    // hash items to the range [0, N*M)
    final hashedItems = <BigInt>[];
    final n = initialItems.length;
    final f = BigInt.from(n) * BigInt.from(M);
    for (final item in initialItems.values) {
      hashedItems.add((siphash(item, key) * f) >> 64);
    }
    // sort the items
    hashedItems.sort((BigInt a, BigInt b) => a.compareTo(b));
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

  static Future<List<Uint8List>> prevOutputScripts(
    Block block,
    TxProvider txProvider,
  ) async {
    final scripts = <Uint8List>[];
    final txCache = <String, Transaction>{};
    for (var i = 0; i < block.transactions.length; i++) {
      if (i == 0) continue; // skip coinbase
      final tx = block.transactions[i];
      for (final input in tx.inputs) {
        final prevTxid = input.txid.reversed.toList().toHex();
        final spentTx =
            txCache[prevTxid] ??
            await txProvider.fromTxid(input.txid.reversed.toList().toHex());
        txCache[prevTxid] = spentTx;
        final output = spentTx.outputs[input.vout];
        scripts.add(output.scriptPubKey);
      }
    }
    return scripts;
  }
}
