import 'dart:typed_data';

import 'common.dart';
import 'base58.dart';
import 'bech32.dart';
import 'utils.dart';

// Implementation for generating a P2PKH address from a public key
String p2pkhAddress(Uint8List publicKey, {Network network = Network.mainnet}) {
  // The public key should be a valid compressed or uncompressed format
  if (!isValidPublicKey(publicKey)) {
    throw ArgumentError('Invalid public key: $publicKey');
  }
  final prefix = switch (network) {
    Network.mainnet => 0x00,
    Network.testnet => 0x6F,
    Network.testnet4 => 0x6F,
  };
  final hash = hash160(publicKey);
  return base58EncodeCheck(Uint8List.fromList([prefix, ...hash]));
}

// Implementation for generating a P2SH-P2WPKH address from a public key
String p2shP2wpkhAddress(
  Uint8List publicKey, {
  Network network = Network.mainnet,
}) {
  // The public key should be a valid compressed format
  if (!isValidCompressedPublicKey(publicKey)) {
    throw ArgumentError('Invalid compressed public key: $publicKey');
  }
  final prefix = switch (network) {
    Network.mainnet => 0x05,
    Network.testnet => 0xC4,
    Network.testnet4 => 0xC4,
  };
  // The P2SH-P2WPKH address is a script hash of the P2WPKH script
  final script = Uint8List.fromList([
    0x00, // OP_0
    0x14, // OP_PUSHBYTES_20
    ...hash160(publicKey), // 20-byte hash of the public key
  ]);
  final scriptHash = hash160(script);
  return base58EncodeCheck(Uint8List.fromList([prefix, ...scriptHash]));
}

// Implementation for generating a P2WPKH address from a public key
String p2wpkhAddress(Uint8List publicKey, {Network network = Network.mainnet}) {
  // The public key should be a valid compressed format
  if (!isValidCompressedPublicKey(publicKey)) {
    throw ArgumentError('Invalid compressed public key: $publicKey');
  }
  // The P2WPKH address is a standardised scriptPubKey
  final scriptPubKey = Uint8List.fromList([
    0x00, // OP_0
    0x14, // OP_PUSHBYTES_20
    ...hash160(publicKey), // 20-byte hash of the public key
  ]);
  // Encode the scriptPubKey using Bech32
  return bech32Encode(scriptPubKey, network: network);
}
