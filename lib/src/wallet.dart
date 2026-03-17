import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'address.dart';
import 'block.dart';
import 'block_filter.dart';
import 'common.dart';
import 'logc.dart';
import 'utils.dart';

final _log = ColorLogger('Wallet');

class Coin {
  final String txid;
  final int vout;
  final int amount; // in satoshis
  bool spent;

  Coin({
    required this.txid,
    required this.vout,
    required this.amount,
    this.spent = false,
  });

  String get outpoint => '$txid:$vout';

  @override
  String toString() =>
      'Coin($outpoint, ${amount}sat, ${spent ? 'spent' : 'unspent'})';
}

class Wallet {
  /// Addresses to scan for incoming and outgoing transactions.
  final List<String> addresses;

  /// Block height before which no transactions need scanning (wallet birthday).
  /// Required when [addresses] is non-empty.
  final int? birthdayBlock;

  /// Block hashes whose compact filter matched [addresses].
  /// Populated by [processBlockFilter]; consumed by the node to request full blocks.
  final List<Uint8List> interestingBlockHashes = [];

  final List<Coin> _coins = [];

  Wallet({
    this.addresses = const [],
    this.birthdayBlock,
  }) {
    assert(
      !(addresses.isNotEmpty && birthdayBlock == null),
      'birthdayBlock must be provided when addresses is not empty',
    );
  }

  List<Coin> get coins => List.unmodifiable(_coins);
  List<Coin> get unspentCoins => _coins.where((c) => !c.spent).toList();
  List<Coin> get spentCoins => _coins.where((c) => c.spent).toList();

  /// Total of all unspent coins in satoshis.
  int get balance => unspentCoins.fold(0, (sum, c) => sum + c.amount);

  /// Total of all coins (spent + unspent) in satoshis.
  int get totalReceived => _coins.fold(0, (sum, c) => sum + c.amount);

  void addCoin(Coin coin) {
    if (_coins.any((c) => c.outpoint == coin.outpoint)) {
      throw ArgumentError('Coin ${coin.outpoint} already tracked');
    }
    _coins.add(coin);
  }

  /// Mark a coin as spent. Returns false if the coin was not found.
  bool spendCoin(String txid, int vout) {
    final outpoint = '$txid:$vout';
    final coin = _coins.where((c) => c.outpoint == outpoint).firstOrNull;
    if (coin == null) return false;
    if (coin.spent) throw StateError('Coin $outpoint is already spent');
    coin.spent = true;
    return true;
  }

  List<Uint8List> _addressesToScripts(Network network) {
    final scripts = <Uint8List>[];
    for (final address in addresses) {
      try {
        scripts.add(AddressData.parseAddress(address).script);
      } catch (e) {
        _log.warning('Invalid address $address for network $network: $e');
      }
    }
    return scripts;
  }

  /// Test a compact block filter against [addresses].
  /// If it matches, [blockHash] is added to [interestingBlockHashes] and true is returned.
  bool processBlockFilter(
    Uint8List blockHash,
    BasicBlockFilter filter,
    Network network, {
    bool verbose = false,
  }) {
    final scripts = _addressesToScripts(network);
    if (scripts.isEmpty) return false;
    if (filter.match(blockHash, scripts)) {
      if (verbose) {
        _log.info(
          'Block filter matches monitored scripts for block hash: ${blockHash.reverse().toHex()}',
        );
      }
      interestingBlockHashes.add(blockHash);
      return true;
    }
    return false;
  }

  /// Process a full block, tracking coins received to and spent from [addresses].
  /// No-ops if the block hash is not in [interestingBlockHashes].
  Future<void> processBlock(
    Block block,
    Network network, {
    bool verbose = false,
  }) async {
    final scripts = _addressesToScripts(network);
    if (scripts.isEmpty) return;
    if (!interestingBlockHashes.any(
      (hash) => listEquals(hash, block.header.hash()),
    )) {
      return;
    }

    // Check outputs – coins received
    for (final tx in block.transactions) {
      for (final output in tx.outputs) {
        if (scripts.any((script) => listEquals(script, output.scriptPubKey))) {
          final vout = tx.outputs.indexOf(output);
          final coin = Coin(txid: tx.txid(), vout: vout, amount: output.value);
          if (!_coins.any((c) => c.outpoint == coin.outpoint)) {
            addCoin(coin);
            if (verbose) {
              _log.info(
                'Found interesting transaction ${tx.txid()} with matching output script. +${output.value} sats',
              );
              _log.info(
                'coin details [txid:vout:amount]: ${tx.txid()}:$vout:${output.value}',
                color: LogColor.brightGreen,
              );
              _log.info(
                'wallet: totalReceived=${totalReceived}sat, balance=${balance}sat',
                color: LogColor.brightBlue,
              );
            }
          }
        }
      }
    }

    // Check inputs – coins spent (skip coinbase)
    final txProvider = BlockDnTxProvider(network);
    for (final tx in block.transactions.skip(1)) {
      for (final input in tx.inputs) {
        final prevTx = await txProvider.fromTxid(input.txid);
        if (scripts.any(
          (script) =>
              listEquals(script, prevTx.outputs[input.vout].scriptPubKey),
        )) {
          spendCoin(prevTx.txid(), input.vout);
          if (verbose) {
            _log.info(
              'Found interesting transaction ${tx.txid()} with matching input script. -${prevTx.outputs[input.vout].value} sats',
            );
            _log.info(
              'coin details [txid:vout:amount]: ${prevTx.txid()}:${input.vout}:${prevTx.outputs[input.vout].value}',
              color: LogColor.brightRed,
            );
            _log.info(
              'wallet: totalReceived=${totalReceived}sat, balance=${balance}sat',
              color: LogColor.brightBlue,
            );
          }
        }
      }
    }
  }

  @override
  String toString() =>
      'Wallet(${unspentCoins.length} unspent, ${spentCoins.length} spent, balance: ${balance}sat)';
}
