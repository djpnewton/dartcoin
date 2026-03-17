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
    Network.regtest => 0x6F,
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
    Network.regtest => 0xC4,
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

class AddressType {
  final String prefix;
  final ScriptType scriptType;
  final Network network;
  final int dataLength;
  final AddressEncoding encoding;

  const AddressType({
    required this.prefix,
    required this.scriptType,
    required this.network,
    required this.dataLength,
    required this.encoding,
  });
}

const addressTypes = [
  AddressType(
    prefix: '1',
    scriptType: ScriptType.p2pkh,
    network: Network.mainnet,
    dataLength: 20,
    encoding: AddressEncoding.base58,
  ),
  AddressType(
    prefix: '3',
    scriptType: ScriptType.p2sh,
    network: Network.mainnet,
    dataLength: 20,
    encoding: AddressEncoding.base58,
  ),
  AddressType(
    prefix: 'm',
    scriptType: ScriptType.p2pkh,
    network: Network.testnet,
    dataLength: 20,
    encoding: AddressEncoding.base58,
  ),
  AddressType(
    prefix: 'n',
    scriptType: ScriptType.p2pkh,
    network: Network.testnet,
    dataLength: 20,
    encoding: AddressEncoding.base58,
  ),
  AddressType(
    prefix: '2',
    scriptType: ScriptType.p2sh,
    network: Network.testnet,
    dataLength: 20,
    encoding: AddressEncoding.base58,
  ),
  AddressType(
    prefix: 'bc1q',
    scriptType: ScriptType.p2wpkh,
    network: Network.mainnet,
    dataLength: 20,
    encoding: AddressEncoding.bech32,
  ),
  AddressType(
    prefix: 'tb1q',
    scriptType: ScriptType.p2wpkh,
    network: Network.testnet,
    dataLength: 20,
    encoding: AddressEncoding.bech32,
  ),
  AddressType(
    prefix: 'bcrt1q',
    scriptType: ScriptType.p2wpkh,
    network: Network.regtest,
    dataLength: 20,
    encoding: AddressEncoding.bech32,
  ),
  AddressType(
    prefix: 'bc1q',
    scriptType: ScriptType.p2wsh,
    network: Network.mainnet,
    dataLength: 32,
    encoding: AddressEncoding.bech32,
  ),
  AddressType(
    prefix: 'tb1q',
    scriptType: ScriptType.p2wsh,
    network: Network.testnet,
    dataLength: 32,
    encoding: AddressEncoding.bech32,
  ),
  AddressType(
    prefix: 'bcrt1q',
    scriptType: ScriptType.p2wsh,
    network: Network.regtest,
    dataLength: 32,
    encoding: AddressEncoding.bech32,
  ),
  AddressType(
    prefix: 'bc1p',
    scriptType: ScriptType.p2tr,
    network: Network.mainnet,
    dataLength: 32,
    encoding: AddressEncoding.bech32m,
  ),
  AddressType(
    prefix: 'tb1p',
    scriptType: ScriptType.p2tr,
    network: Network.testnet,
    dataLength: 32,
    encoding: AddressEncoding.bech32m,
  ),
  AddressType(
    prefix: 'bcrt1p',
    scriptType: ScriptType.p2tr,
    network: Network.regtest,
    dataLength: 32,
    encoding: AddressEncoding.bech32m,
  ),
];

class AddressData {
  final AddressType type;
  final Uint8List script;

  AddressData({required this.type, required this.script});

  static Uint8List _addrDecode(String address, AddressEncoding encoding) {
    switch (encoding) {
      case AddressEncoding.base58:
        final decoded = base58DecodeCheck(address);
        return decoded.sublist(1); // remove prefix byte
      case AddressEncoding.bech32:
        return bech32Decode(
          address,
        ).scriptPubKey.sublist(2); // remove version and size byte
      case AddressEncoding.bech32m:
        return bech32Decode(
          address,
        ).scriptPubKey.sublist(2); // remove version and size byte
    }
  }

  static (Uint8List, AddressType) _addrData(String address) {
    for (final addrType in addressTypes) {
      if (address.startsWith(addrType.prefix)) {
        final bytes = _addrDecode(address, addrType.encoding);
        if (bytes.length == addrType.dataLength) {
          return (bytes, addrType);
        }
      }
    }
    throw FormatException('Invalid address: $address');
  }

  static AddressData parseAddress(String address) {
    final (data, type) = _addrData(address);
    assert(data.length == type.dataLength);
    final script = switch (type.scriptType) {
      ScriptType.p2pkh => Uint8List.fromList([
        0x76, // OP_DUP
        0xA9, // OP_HASH160
        0x14, // OP_PUSHBYTES_20
        ...data,
        0x88, // OP_EQUALVERIFY
        0xAC, // OP_CHECKSIG
      ]),
      ScriptType.p2sh => Uint8List.fromList([
        0xA9, // OP_HASH160
        0x14, // OP_PUSHBYTES_20
        ...data,
        0x87, // OP_EQUAL
      ]),
      ScriptType.p2shP2wpkh => throw ArgumentError(
        'P2SH-P2WPKH should be parsed as P2SH script type',
      ),
      ScriptType.p2wpkh => Uint8List.fromList([
        0x00, // OP_0
        0x14, // OP_PUSHBYTES_20
        ...data,
      ]),
      ScriptType.p2wsh => Uint8List.fromList([
        0x00, // OP_0
        0x20, // OP_PUSHBYTES_32
        ...data,
      ]),
      ScriptType.p2tr => Uint8List.fromList([
        0x51, // OP_1
        0x20, // OP_PUSHBYTES_32
        ...data,
      ]),
    };
    return AddressData(type: type, script: script);
  }
}
