import 'dart:typed_data';

import 'common.dart';
import 'base58.dart';

class Wif {
  final Network network;
  final Uint8List privateKey;
  final bool compressed;

  Wif(this.network, this.privateKey, this.compressed) {
    if (privateKey.length != 32) {
      throw ArgumentError('Private key must be 32 bytes long.');
    }
  }

  /// Encodes Wallet Import Format (WIF) string.
  String toWifString() {
    final prefix = Uint8List.fromList([
      switch (network) {
        Network.mainnet => 0x80,
        Network.testnet => 0xEF,
        Network.testnet4 => 0xEF,
      },
    ]);
    final suffix = compressed ? Uint8List.fromList([0x01]) : Uint8List(0);
    final payload = Uint8List.fromList([...prefix, ...privateKey, ...suffix]);
    return base58EncodeCheck(payload);
  }

  /// Converts a WIF string back to a private key.
  factory Wif.fromWifString(String wif) {
    final payload = base58DecodeCheck(wif);
    if (payload.length < 33 || payload.length > 34) {
      throw FormatException('Invalid WIF format.');
    }
    final network = payload[0] == 0x80
        ? Network.mainnet
        : payload[0] == 0xEF
        ? Network.testnet
        : throw FormatException('Invalid WIF prefix.');
    final privateKey = payload.sublist(1, 33);
    final compressed = payload.length == 34 && payload[33] == 0x01;
    return Wif(network, privateKey, compressed);
  }
}
