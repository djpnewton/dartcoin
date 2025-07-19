import 'dart:typed_data';

enum Network {
  mainnet, // Main Bitcoin network
  testnet, // Bitcoin test network 3
  testnet4, // Bitcoin test network 4
}

enum ScriptType {
  p2pkh, // 'Pay to Public Key Hash'
  p2shP2wpkh, // 'Pay to Witness Public Key Hash' wrapped in 'Pay to Script Hash'
  p2wpkh, // 'Pay to Witness Public Key Hash'
}

bool isValidCompressedPublicKey(Uint8List publicKey) {
  // Check if the public key is a valid compressed format
  return publicKey.length == 33 &&
      (publicKey[0] == 0x02 || publicKey[0] == 0x03);
}

bool isValidPublicKey(Uint8List publicKey) {
  // Check if the public key is a valid compressed or uncompressed format
  if (isValidCompressedPublicKey(publicKey)) {
    // Compressed public key
    return true;
  } else if (publicKey.length == 65) {
    // Uncompressed public key
    return publicKey[0] == 0x04;
  }
  return false;
}

Uint8List publicKeyToCompressed(Uint8List publicKey) {
  if (!isValidPublicKey(publicKey)) {
    throw ArgumentError('Invalid public key format.');
  }
  if (publicKey.length == 33) {
    // already compressed
    return publicKey;
  } else if (publicKey.length == 65) {
    // uncompressed, convert to compressed
    return Uint8List.fromList([
      publicKey[64] % 2 == 0 ? 0x02 : 0x03,
      ...publicKey.sublist(1, 33),
    ]);
  }
  throw ArgumentError('Invalid public key length.');
}
