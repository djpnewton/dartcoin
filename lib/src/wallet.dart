import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'address.dart';
import 'block.dart';
import 'block_filter.dart';
import 'common.dart';
import 'logc.dart';
import 'transaction.dart';
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

class WalletTx {
  final Transaction tx;
  final List<Coin> coinsAdded;
  final List<Coin> coinsSpent;
  final String? blockHash;

  WalletTx(this.tx, this.coinsAdded, this.coinsSpent, this.blockHash);

  int get netAmount =>
      coinsAdded.fold(0, (sum, c) => sum + c.amount) -
      coinsSpent.fold(0, (sum, c) => sum + c.amount);
}

class Wallet {
  /// Addresses to scan for incoming and outgoing transactions.
  final List<String> addresses;

  /// Block height before which no transactions need scanning (wallet birthday).
  /// Required when [addresses] is non-empty.
  final int? birthdayBlock;

  /// TxProvider to fetch transaction details for inputs when processing blocks.
  final TxProvider txProvider;

  /// Block hashes whose compact filter matched [addresses].
  /// Populated by [processBlockFilter]; consumed by the node to request full blocks.
  final List<Uint8List> interestingBlockHashes = [];

  final List<Coin> _coins = [];
  final List<WalletTx> _transactions = [];

  Wallet({
    this.addresses = const [],
    this.birthdayBlock,
    required this.txProvider,
  }) {
    assert(
      !(addresses.isNotEmpty && birthdayBlock == null),
      'birthdayBlock must be provided when addresses is not empty',
    );
  }

  List<Coin> get coins => List.unmodifiable(_coins);
  List<Coin> get unspentCoins => _coins.where((c) => !c.spent).toList();
  List<Coin> get spentCoins => _coins.where((c) => c.spent).toList();
  List<WalletTx> get transactions => List.unmodifiable(_transactions);

  /// Total of all unspent coins in satoshis.
  int get balance => unspentCoins.fold(0, (sum, c) => sum + c.amount);

  /// Total of all coins (spent + unspent) in satoshis.
  int get totalReceived => _coins.fold(0, (sum, c) => sum + c.amount);

  void _addCoin(Coin coin) {
    if (_coins.any((c) => c.outpoint == coin.outpoint)) {
      throw ArgumentError('Coin ${coin.outpoint} already tracked');
    }
    _coins.add(coin);
  }

  /// Mark a coin as spent. Returns false if the coin was not found.
  bool _spendCoin(String txid, int vout) {
    final outpoint = '$txid:$vout';
    final coin = _coins.where((c) => c.outpoint == outpoint).firstOrNull;
    if (coin == null) return false;
    if (coin.spent) throw StateError('Coin $outpoint is already spent');
    coin.spent = true;
    return true;
  }

  void addTx(
    Transaction tx,
    List<Coin> coinsAdded,
    List<Coin> coinsSpent,
    String blockHash,
  ) {
    // ensure tx is not already tracked
    if (_transactions.any((t) => t.tx.txid() == tx.txid())) {
      throw ArgumentError('Transaction ${tx.txid()} already tracked');
    }

    _transactions.add(WalletTx(tx, coinsAdded, coinsSpent, blockHash));
    for (final coin in coinsAdded) {
      _addCoin(coin);
    }
    for (final coin in coinsSpent) {
      if (!_spendCoin(coin.txid, coin.vout)) {
        throw StateError('Attempting to spend unknown coin ${coin.outpoint}');
      }
    }
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
          color: LogColor.brightCyan,
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

    final blockHash = block.header.hash();
    if (!interestingBlockHashes.any((hash) => listEquals(hash, blockHash))) {
      return;
    }

    // Build an outpoint->coin map to identify coins spent by our transactions.
    final coinsByOutpoint = <String, Coin>{
      for (final c in _coins) c.outpoint: c,
    };
    final blockHashNice = block.header.hashNice();

    for (var i = 0; i < block.transactions.length; i++) {
      final tx = block.transactions[i];
      final txid = tx.txid();
      final coinsAdded = <Coin>[];
      final coinsSpent = <Coin>[];

      // Check outputs for coins received.
      for (var vout = 0; vout < tx.outputs.length; vout++) {
        final output = tx.outputs[vout];
        if (scripts.any((script) => listEquals(script, output.scriptPubKey))) {
          final outpoint = '$txid:$vout';
          if (!coinsByOutpoint.containsKey(outpoint)) {
            final coin = Coin(txid: txid, vout: vout, amount: output.value);
            coinsAdded.add(coin);
            // Make the new coin visible to inputs later in the same block.
            coinsByOutpoint[outpoint] = coin;
            if (verbose) {
              _log.info(
                'Found interesting transaction $txid with matching output script. +${output.value} sats',
              );
              _log.info(
                'coin details [txid:vout:amount]: $txid:$vout:${output.value}',
                color: LogColor.brightGreen,
              );
            }
          }
        }
      }

      // Skip coinbase; check inputs for coins spent.
      if (i != 0) {
        for (final input in tx.inputs) {
          final outpoint = '${input.txid}:${input.vout}';
          final coin = coinsByOutpoint[outpoint];
          if (coin != null) {
            coinsSpent.add(coin);
            if (verbose) {
              _log.info(
                'Found interesting transaction $txid with matching input script. -${coin.amount} sats',
              );
              _log.info(
                'coin details [txid:vout:amount]: ${coin.txid}:${coin.vout}:${coin.amount}',
                color: LogColor.brightRed,
              );
            }
          }
        }
      }

      // If any coins were added or spent, track the transaction.
      if (coinsAdded.isNotEmpty || coinsSpent.isNotEmpty) {
        addTx(tx, coinsAdded, coinsSpent, blockHashNice);
        _log.info(
          'wallet: totalReceived=${totalReceived}sat, balance=${balance}sat',
          color: LogColor.brightBlue,
        );
      }
    }
  }

  @override
  String toString() =>
      'Wallet(${unspentCoins.length} unspent, ${spentCoins.length} spent, balance: ${balance}sat)';
}
