import 'dart:typed_data';

import 'utils.dart';

// TODO: find all uint8list txid fields in the codebase and rename them to txidRaw and add a txid() function that returns the reversed hex string for easier debugging and readability. This includes the txid field in the Coin class, and any txid fields in the transaction.dart file.

// TODO: move the logic around scanaddresses and startblock from node to wallet
// this means that the wallet will get block filter and block notifications

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
  final List<Coin> _coins = [];

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

  @override
  String toString() =>
      'Wallet(${unspentCoins.length} unspent, ${spentCoins.length} spent, balance: ${balance}sat)';
}
