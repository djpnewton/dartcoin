import 'dart:convert';
import 'dart:typed_data';

import 'secp256k1.dart';
import 'utils.dart';
import 'base58.dart';
import 'common.dart';
import 'address.dart';
import 'hmac.dart';
import 'wif.dart';

const _prefixDict = {
  'xprv': '0488ade4', // Mainnet - P2PKH or P2SH  - m/44'/0'
  'yprv': '049d7878', // Mainnet - P2WPKH in P2SH - m/49'/0'
  'zprv': '04b2430c', // Mainnet - P2WPKH         - m/84'/0'
  'Yprv': '0295b005', // Mainnet - Multi-signature P2WSH in P2SH
  'Zprv': '02aa7a99', // Mainnet - Multi-signature P2WSH
  'tprv': '04358394', // Testnet - P2PKH or P2SH  - m/44'/1'
  'uprv': '044a4e28', // Testnet - P2WPKH in P2SH - m/49'/1'
  'vprv': '045f18bc', // Testnet - P2WPKH         - m/84'/1'
  'Uprv': '024285b5', // Testnet - Multi-signature P2WSH in P2SH
  'Vprv': '02575048', // Testnet - Multi-signature P2WSH

  'xpub': '0488b21e', // Mainnet - P2PKH or P2SH  - m/44'/0'
  'ypub': '049d7cb2', // Mainnet - P2WPKH in P2SH - m/49'/0'
  'zpub': '04b24746', // Mainnet - P2WPKH         - m/84'/0'
  'Ypub': '0295b43f', // Mainnet - Multi-signature P2WSH in P2SH
  'Zpub': '02aa7ed3', // Mainnet - Multi-signature P2WSH
  'tpub': '043587cf', // Testnet - P2PKH or P2SH  - m/44'/1'
  'upub': '044a5262', // Testnet - P2WPKH in P2SH - m/49'/1'
  'vpub': '045f1cf6', // Testnet - P2WPKH         - m/84'/1'
  'Upub': '024289ef', // Testnet - Multi-signature P2WSH in P2SH
  'Vpub': '02575483', // Testnet - Multi-signature P2WSH
};

Network networkFromPrefix(String prefix) {
  // Convert the prefix to Network
  return switch (prefix) {
    'xprv' => Network.mainnet,
    'yprv' => Network.mainnet,
    'zprv' => Network.mainnet,
    'Yprv' => Network.mainnet,
    'Zprv' => Network.mainnet,
    'tprv' => Network.testnet,
    'uprv' => Network.testnet,
    'vprv' => Network.testnet,
    'Uprv' => Network.testnet,
    'Vprv' => Network.testnet,

    'xpub' => Network.mainnet,
    'ypub' => Network.mainnet,
    'zpub' => Network.mainnet,
    'Ypub' => Network.mainnet,
    'Zpub' => Network.mainnet,
    'tpub' => Network.testnet,
    'upub' => Network.testnet,
    'vpub' => Network.testnet,
    'Upub' => Network.testnet,
    'Vpub' => Network.testnet,
    _ => throw ArgumentError('Unknown prefix: $prefix'),
  };
}

ScriptType scriptTypeFromPrefix(String prefix) {
  // Convert the prefix to ScriptType
  return switch (prefix) {
    'xprv' => ScriptType.p2pkh,
    'yprv' => ScriptType.p2shP2wpkh,
    'zprv' => ScriptType.p2wpkh,
    'tprv' => ScriptType.p2pkh,
    'uprv' => ScriptType.p2shP2wpkh,
    'vprv' => ScriptType.p2wpkh,

    'xpub' => ScriptType.p2pkh,
    'ypub' => ScriptType.p2shP2wpkh,
    'zpub' => ScriptType.p2wpkh,
    'tpub' => ScriptType.p2pkh,
    'upub' => ScriptType.p2shP2wpkh,
    'vpub' => ScriptType.p2wpkh,
    _ => throw ArgumentError('Unknown prefix: $prefix'),
  };
}

YParity? pubkeyPrefixToYParity(int prefix) {
  // Convert the public key prefix to YParity
  return switch (prefix) {
    0x02 => YParity.even, // Compressed public key with even y-coordinate
    0x03 => YParity.odd, // Compressed public key with odd y-coordinate
    _ => null, // Invalid prefix
  };
}

String yParityToPubkeyPrefix(YParity yParity) {
  // Convert YParity to public key prefix
  return switch (yParity) {
    YParity.even => '02', // Compressed public key with even y-coordinate
    YParity.odd => '03', // Compressed public key with odd y-coordinate
  };
}

class PublicKey {
  int depth; // Depth in the key hierarchy, 0 for master key
  int parentFingerprint; // Fingerprint of the parent key, 0 for master key
  int childNumber; // child index of the key, 0 for master key
  // The public key and chain code
  Uint8List publicKey;
  Uint8List chainCode;
  // extended or basic public key
  bool extended;

  Network defaultNetwork;
  ScriptType defaultScriptType;

  PublicKey(
    this.depth,
    this.parentFingerprint,
    this.childNumber,
    this.publicKey,
    this.chainCode, {
    this.defaultNetwork = Network.mainnet,
    this.defaultScriptType = ScriptType.p2pkh,
    this.extended = true,
  });

  PublicKey.basic(
    this.publicKey, {
    this.defaultNetwork = Network.mainnet,
    this.defaultScriptType = ScriptType.p2pkh,
  }) : depth = 0,
       parentFingerprint = 0,
       childNumber = 0,
       chainCode = Uint8List(0),
       extended = false;

  factory PublicKey.fromXPub(String xpub) {
    // Parse the xpub string and return a PublicKey object
    final bytes = base58Decode(xpub);
    if (bytes.length != 82) {
      throw FormatException('Invalid length: ${bytes.length}');
    }
    // check the prefix is for a public key
    final prefix = xpub.substring(0, 4);
    if (!prefix.endsWith('pub')) {
      throw ArgumentError('Invalid prefix: $prefix');
    }
    // set the default network and script type based on the prefix
    final network = networkFromPrefix(prefix);
    final scriptType = scriptTypeFromPrefix(prefix);
    // check checksum
    final checksum = bytes.sublist(78, 82);
    final calculatedChecksum = hash256(bytes.sublist(0, 78)).sublist(0, 4);
    if (!listEquals(checksum, calculatedChecksum)) {
      throw FormatException('Invalid checksum');
    }
    // Extract the fields from the bytes
    final depth = bytes[4];
    final parentFingerprint = bytesToBigInt(bytes.sublist(5, 9)).toInt();
    final childNumber = bytesToBigInt(bytes.sublist(9, 13)).toInt();
    final chainCode = bytes.sublist(13, 45);
    final publicKey = bytes.sublist(45, 78);
    // Validate the prefix
    if (!_prefixDict.containsKey(prefix)) {
      throw FormatException('Prefix not found: $prefix');
    }
    // validate the parent fingerprint
    if (depth == 0 && parentFingerprint != 0) {
      throw FormatException('Parent fingerprint must be 0 for master key');
    }
    // validate the child number
    if (depth == 0 && childNumber != 0) {
      throw FormatException('Child number must be 0 for master key');
    }
    // validate the public key prefix
    final pubkeyPrefix = publicKey[0];
    final yParity = pubkeyPrefixToYParity(pubkeyPrefix);
    if (yParity == null) {
      throw FormatException(
        'Invalid public key prefix: ${pubkeyPrefix.toRadixString(16).padLeft(2, '0')}',
      );
    }
    // validate the public key value
    final publicKeyX = bytesToBigInt(publicKey.sublist(1));
    if (publicKeyX <= BigInt.zero || publicKeyX >= Secp256k1Point.n) {
      throw FormatException(
        'Invalid public key value: ${bytesToHex(publicKey)}',
      );
    }
    // check we can derive the point from the x coordinate
    try {
      Secp256k1Point.fromX(publicKeyX, yParity);
    } catch (e) {
      throw FormatException(
        'Invalid public key value: ${bytesToHex(publicKey)}',
      );
    }
    return PublicKey(
      depth,
      parentFingerprint,
      childNumber,
      publicKey,
      chainCode,
      defaultNetwork: network,
      defaultScriptType: scriptType,
    );
  }

  factory PublicKey.fromPublicKey(
    Uint8List publicKey, {
    Network defaultNetwork = Network.mainnet,
    ScriptType defaultScriptType = ScriptType.p2pkh,
  }) {
    return PublicKey.basic(
      publicKeyToCompressed(publicKey),
      defaultNetwork: defaultNetwork,
      defaultScriptType: defaultScriptType,
    );
  }

  factory PublicKey.fromPoint(
    Secp256k1Point point, {
    Network defaultNetwork = Network.mainnet,
    ScriptType defaultScriptType = ScriptType.p2pkh,
  }) {
    // Convert the point to a compressed public key
    final publicKey = pubkeyFromPoint(point);
    return PublicKey.basic(
      publicKey,
      defaultNetwork: defaultNetwork,
      defaultScriptType: defaultScriptType,
    );
  }

  static Uint8List pubkeyFromPoint(Secp256k1Point point) {
    // Convert the point to bytes (compressed format)
    final x = point.x.toRadixString(16).padLeft(64, '0');
    // Compressed public key format: 0x02 or 0x03 + x
    final prefix = yParityToPubkeyPrefix(
      point.y.isEven ? YParity.even : YParity.odd,
    );
    return Uint8List.fromList(hexToBytes(prefix + x));
  }

  static Secp256k1Point _pointFromData(Uint8List data) {
    assert(data.length == 32, 'data must be 32 bytes long');
    // Derive the point from the data using secp256k1
    final point = Secp256k1Point.generator.multiply(bytesToBigInt(data));
    return point;
  }

  Secp256k1Point _compressedPublicKeyToPoint(Uint8List publicKey) {
    // Convert a compressed public key to an integer
    if (!isValidCompressedPublicKey(publicKey)) {
      throw ArgumentError('Invalid compressed public key: $publicKey');
    }
    // get Y parity from the first byte
    final yParity = pubkeyPrefixToYParity(publicKey[0]);
    if (yParity == null) {
      throw ArgumentError(
        'Invalid public key prefix: ${publicKey[0].toRadixString(16).padLeft(2, '0')}',
      );
    }
    // extract x coordinate from the public key
    final hex = bytesToHex(publicKey.sublist(1));
    final x = BigInt.parse(hex, radix: 16);
    return Secp256k1Point.fromX(x, yParity);
  }

  int fingerprint() {
    if (!extended) {
      throw StateError('Cannot calculate fingerprint for basic public key');
    }
    // fingerprint is the first 4 bytes of the hash160 of the public key
    final hash = hash160(publicKey);
    return bytesToBigInt(hash.sublist(0, 4)).toInt();
  }

  PublicKey childPublicKey(int index) {
    if (!extended) {
      throw StateError('Cannot calculate child key for basic public key');
    }
    // Check if the index is valid
    if (index < 0 || index > 0x7FFFFFFF) {
      throw ArgumentError(
        'Index ($index) must be in the range [0, 0x7FFFFFFF)',
      );
    }
    // Create a new key from the parent key and the index
    final hexData =
        bytesToHex(publicKey) + index.toRadixString(16).padLeft(8, '0');
    final data = hexToBytes(hexData); // parent pubkey + 4 byte index
    final digest = hmac(Hash.sha512, chainCode, data);
    // The first 32 bytes are the child public key input, the next 32 bytes are the chain code
    final publicKeyInput = Uint8List.fromList(digest.sublist(0, 32));
    final childChainCode = Uint8List.fromList(digest.sublist(32, 64));
    // calculate the child public key
    final childPublicKeyPoint = _pointFromData(
      publicKeyInput,
    ).add(_compressedPublicKeyToPoint(publicKey));
    // compressed public key prefix: 0x02 or 0x03
    final prefix = yParityToPubkeyPrefix(
      childPublicKeyPoint.y.isEven ? YParity.even : YParity.odd,
    );
    final childPublicKey = Uint8List.fromList(
      hexToBytes(
        prefix + childPublicKeyPoint.x.toRadixString(16).padLeft(64, '0'),
      ),
    );
    return PublicKey(
      depth + 1,
      fingerprint(),
      index,
      childPublicKey,
      childChainCode,
    );
  }

  String xpub({Network? network, ScriptType? scriptType}) {
    if (!extended) {
      throw StateError('Cannot calculate xpub for basic public key');
    }
    // Use the default network and script type if not provided
    network ??= defaultNetwork;
    scriptType ??= defaultScriptType;
    // Return the public key in xpub format
    final prefix = switch (network) {
      Network.mainnet => switch (scriptType) {
        ScriptType.p2pkh => _prefixDict['xpub']!,
        ScriptType.p2sh => throw UnimplementedError(
          'xpub generation for P2SH is not implemented yet',
        ),
        ScriptType.p2shP2wpkh => _prefixDict['ypub']!,
        ScriptType.p2wpkh => _prefixDict['zpub']!,
        ScriptType.p2wsh => throw UnimplementedError(
          'xpub generation for P2WSH is not implemented yet',
        ),
        ScriptType.p2tr => throw UnimplementedError(
          'xpub generation for Taproot is not implemented yet',
        ),
      },
      Network.testnet => switch (scriptType) {
        ScriptType.p2pkh => _prefixDict['tpub']!,
        ScriptType.p2sh => throw UnimplementedError(
          'xpub generation for P2SH is not implemented yet',
        ),
        ScriptType.p2shP2wpkh => _prefixDict['upub']!,
        ScriptType.p2wpkh => _prefixDict['vpub']!,
        ScriptType.p2wsh => throw UnimplementedError(
          'xpub generation for P2WSH is not implemented yet',
        ),
        ScriptType.p2tr => throw UnimplementedError(
          'xpub generation for Taproot is not implemented yet',
        ),
      },
      Network.testnet4 => switch (scriptType) {
        ScriptType.p2pkh => _prefixDict['tpub']!,
        ScriptType.p2sh => throw UnimplementedError(
          'xpub generation for P2SH is not implemented yet',
        ),
        ScriptType.p2shP2wpkh => _prefixDict['upub']!,
        ScriptType.p2wpkh => _prefixDict['vpub']!,
        ScriptType.p2wsh => throw UnimplementedError(
          'xpub generation for P2WSH is not implemented yet',
        ),
        ScriptType.p2tr => throw UnimplementedError(
          'xpub generation for Taproot is not implemented yet',
        ),
      },
      Network.regtest => switch (scriptType) {
        ScriptType.p2pkh => _prefixDict['tpub']!,
        ScriptType.p2sh => throw UnimplementedError(
          'xpub generation for P2SH is not implemented yet',
        ),
        ScriptType.p2shP2wpkh => _prefixDict['upub']!,
        ScriptType.p2wpkh => _prefixDict['vpub']!,
        ScriptType.p2wsh => throw UnimplementedError(
          'xpub generation for P2WSH is not implemented yet',
        ),
        ScriptType.p2tr => throw UnimplementedError(
          'xpub generation for Taproot is not implemented yet',
        ),
      },
    };
    final depthHex = depth.toRadixString(16).padLeft(2, '0');
    final parentFingerprintHex = parentFingerprint
        .toRadixString(16)
        .padLeft(8, '0');
    final childNumberHex = childNumber.toRadixString(16).padLeft(8, '0');
    final chainCodeHex = bytesToHex(chainCode);
    final keyHex = bytesToHex(publicKey);
    final serialized = hexToBytes(
      '$prefix$depthHex$parentFingerprintHex$childNumberHex$chainCodeHex$keyHex',
    );
    // Calculate the checksum
    final checksum = hash256(serialized).sublist(0, 4);
    // Return the xpub in base58 format
    final xpubBytes = Uint8List.fromList(serialized + checksum);
    return base58Encode(xpubBytes);
  }

  String address({Network? network, ScriptType? scriptType}) {
    // Use the default network and script type if not provided
    network ??= defaultNetwork;
    scriptType ??= defaultScriptType;
    /*
    // dont allow master keys to be used for addresses
    if (extended && depth == 0) {
      throw ArgumentError('Master keys cannot be used for addresses');
    }
    */
    // Return the address in the specified format
    return switch (scriptType) {
      ScriptType.p2pkh => p2pkhAddress(publicKey, network: network),
      ScriptType.p2sh => throw UnimplementedError(
        'P2SH address generation is not implemented yet',
      ),
      ScriptType.p2shP2wpkh => p2shP2wpkhAddress(publicKey, network: network),
      ScriptType.p2wpkh => p2wpkhAddress(publicKey, network: network),
      ScriptType.p2wsh => throw UnimplementedError(
        'P2WSH address generation is not implemented yet',
      ),
      ScriptType.p2tr => throw UnimplementedError(
        'Taproot address generation is not implemented yet',
      ),
    };
  }

  Secp256k1Point point() {
    return _compressedPublicKeyToPoint(publicKey);
  }
}

class PrivateKey extends PublicKey {
  Uint8List privateKey;

  PrivateKey(
    super.depth,
    super.parentFingerprint,
    super.childNumber,
    super.publicKey,
    super.chainCode,
    this.privateKey, {
    super.defaultNetwork,
    super.defaultScriptType,
  });

  PrivateKey.basic(
    super.publicKey,
    this.privateKey, {
    super.defaultNetwork = Network.mainnet,
    super.defaultScriptType = ScriptType.p2pkh,
  }) : super.basic();

  static Uint8List pubkeyFromPrivateKey(Uint8List privateKey) {
    // Derive the public key from the private key using secp256k1
    final point = PublicKey._pointFromData(privateKey);
    return PublicKey.pubkeyFromPoint(point);
  }

  /// Derive the master key from the seed
  factory PrivateKey.fromSeed(
    Uint8List seed, {
    Network defaultNetwork = Network.mainnet,
    ScriptType defaultScriptType = ScriptType.p2pkh,
  }) {
    // hmac sha512 seed with 'Bitcoin seed' to get the master key
    final digest = hmac(Hash.sha512, utf8.encode('Bitcoin seed'), seed);
    // The first 32 bytes are the private key, the next 32 bytes are the chain code
    final privateKey = Uint8List.fromList(digest.sublist(0, 32));
    final chainCode = Uint8List.fromList(digest.sublist(32, 64));
    // The public key is derived from the private key using secp256k1
    final publicKey = pubkeyFromPrivateKey(privateKey);
    return PrivateKey(
      0,
      0,
      0,
      publicKey,
      chainCode,
      privateKey,
      defaultNetwork: defaultNetwork,
      defaultScriptType: defaultScriptType,
    );
  }

  factory PrivateKey.fromXPrv(String xprv) {
    // Parse the xpriv string and return a PrivateKey object
    final bytes = base58Decode(xprv);
    if (bytes.length != 82) {
      throw FormatException('Invalid length: ${bytes.length}');
    }
    // check the prefix is for a private key
    final prefix = xprv.substring(0, 4);
    if (!prefix.endsWith('prv')) {
      throw ArgumentError('Invalid prefix: $prefix');
    }
    // set the default network and script type based on the prefix
    final network = networkFromPrefix(prefix);
    final scriptType = scriptTypeFromPrefix(prefix);
    // check checksum
    final checksum = bytes.sublist(78, 82);
    final calculatedChecksum = hash256(bytes.sublist(0, 78)).sublist(0, 4);
    if (!listEquals(checksum, calculatedChecksum)) {
      throw FormatException('Invalid checksum');
    }
    // Extract the fields from the bytes
    final depth = bytes[4];
    final parentFingerprint = bytesToBigInt(bytes.sublist(5, 9)).toInt();
    final childNumber = bytesToBigInt(bytes.sublist(9, 13)).toInt();
    final chainCode = bytes.sublist(13, 45);
    final privateKeyPrefix = bytes[45];
    final privateKey = bytes.sublist(46, 78);
    // Validate the prefix
    if (!_prefixDict.containsKey(prefix)) {
      throw FormatException('Prefix not found: $prefix');
    }
    // validate the parent fingerprint
    if (depth == 0 && parentFingerprint != 0) {
      throw FormatException('Parent fingerprint must be 0 for master key');
    }
    // validate the child number
    if (depth == 0 && childNumber != 0) {
      throw FormatException('Child number must be 0 for master key');
    }
    // validate the private key prefix
    if (privateKeyPrefix != 0x00) {
      throw FormatException(
        'Invalid private key prefix: ${privateKeyPrefix.toRadixString(16).padLeft(2, '0')}',
      );
    }
    // validate the private key value
    final privateKeyInt = bytesToBigInt(privateKey);
    if (privateKeyInt <= BigInt.zero || privateKeyInt >= Secp256k1Point.n) {
      throw FormatException(
        'Invalid private key value: ${bytesToHex(privateKey)}',
      );
    }
    // Ensure the private key is 32 bytes long
    if (privateKey.length != 32) {
      throw FormatException('Private key must be 32 bytes long');
    }
    // The public key is derived from the private key using secp256k1
    final publicKey = pubkeyFromPrivateKey(privateKey);
    return PrivateKey(
      depth,
      parentFingerprint,
      childNumber,
      publicKey,
      chainCode,
      privateKey,
      defaultNetwork: network,
      defaultScriptType: scriptType,
    );
  }

  factory PrivateKey.fromPrivateKey(
    Uint8List privateKey, {
    Network defaultNetwork = Network.mainnet,
    ScriptType defaultScriptType = ScriptType.p2pkh,
  }) {
    // create PrivateKey from a raw private key
    if (privateKey.length != 32) {
      throw ArgumentError('Private key must be 32 bytes long');
    }
    // The public key is derived from the private key using secp256k1
    final publicKey = pubkeyFromPrivateKey(privateKey);
    return PrivateKey.basic(
      publicKey,
      privateKey,
      defaultNetwork: defaultNetwork,
      defaultScriptType: defaultScriptType,
    );
  }

  factory PrivateKey.fromWif(
    String wifString, {
    ScriptType defaultScriptType = ScriptType.p2pkh,
  }) {
    final wif = Wif.fromWifString(wifString);
    final pubkey = pubkeyFromPrivateKey(wif.privateKey);
    return PrivateKey.basic(
      pubkey,
      wif.privateKey,
      defaultNetwork: wif.network,
      defaultScriptType: defaultScriptType,
    );
  }

  Uint8List _intToKey(BigInt value) {
    // Convert a BigInt to a 32-byte private key
    final bytes = bigIntToBytes(value, minLength: 32);
    if (bytes.length > 32) {
      throw ArgumentError('Value is too large for a private key');
    }
    return bytes;
  }

  PrivateKey childPrivateKey(int index, {bool hardened = true}) {
    // Check if the index is valid
    if (hardened) {
      if (index < 0x80000000 || index > 0xFFFFFFFF) {
        throw ArgumentError(
          'Index ($index) must be in the range [0x80000000, 0xFFFFFFFF)',
        );
      }
    } else if (index < 0 || index > 0x7FFFFFFF) {
      throw ArgumentError(
        'Index ($index) must be in the range [0, 0x7FFFFFFF)',
      );
    }
    // Create a new key from the master key and the index
    final data = hardened
        ? hexToBytes(
            '00${bytesToHex(privateKey)}${index.toRadixString(16).padLeft(8, '0')}',
          ) // '00' + master privkey + 4 byte index
        : hexToBytes(
            bytesToHex(publicKey) + index.toRadixString(16).padLeft(8, '0'),
          ); // master pubkey + 4 byte index
    final digest = hmac(Hash.sha512, chainCode, data);
    // The first 32 bytes are the child private key input, the next 32 bytes are the chain code
    final privateKeyInput = Uint8List.fromList(digest.sublist(0, 32));
    final childChainCode = Uint8List.fromList(digest.sublist(32, 64));
    // calculate the child private key
    final childPrivateKeyInt =
        (bytesToBigInt(privateKeyInput) + bytesToBigInt(privateKey)) %
        Secp256k1Point.n;
    final childPrivateKey = _intToKey(childPrivateKeyInt);
    // The public key is derived from the private key using secp256k1
    final childPublicKey = pubkeyFromPrivateKey(childPrivateKey);
    return PrivateKey(
      depth + 1,
      fingerprint(),
      index,
      childPublicKey,
      childChainCode,
      childPrivateKey,
    );
  }

  PrivateKey childFromDerivationPath(String path) {
    // Derive a child key from the derivation path
    final parts = path.toLowerCase().replaceAll('h', "'").split('/');
    if (parts[0] != 'm') {
      throw FormatException('Derivation path must start with "m/"');
    }
    var currentKey = this;
    for (var part in parts.sublist(1)) {
      if (part.isEmpty) {
        throw FormatException('Invalid part in derivation path: $part');
      }
      // check if hardened
      var hardened = part.endsWith("'");
      if (hardened) {
        part = part.substring(0, part.length - 1); // remove the trailing '
      }
      // parse the index
      var index = int.tryParse(part);
      if (index == null) {
        throw FormatException('Invalid index in derivation path: $part');
      }
      if (index < 0 || index > 0x7FFFFFFF) {
        throw FormatException(
          'Index ($index) must be in the range [0, 0x7FFFFFFF)',
        );
      }
      // If hardened, add 0x80000000 to the index
      if (hardened) {
        index += 0x80000000;
      }
      // Derive the child public key
      currentKey = currentKey.childPrivateKey(index, hardened: hardened);
    }
    return currentKey;
  }

  String xprv({Network? network, ScriptType? scriptType}) {
    // Use the default network and script type if not provided
    network ??= defaultNetwork;
    scriptType ??= defaultScriptType;
    // Return the private key in xprv format
    final prefix = switch (network) {
      Network.mainnet => switch (scriptType) {
        ScriptType.p2pkh => _prefixDict['xprv']!,
        ScriptType.p2sh => throw UnimplementedError(
          'xprv generation for P2SH is not implemented yet',
        ),
        ScriptType.p2shP2wpkh => _prefixDict['yprv']!,
        ScriptType.p2wpkh => _prefixDict['zprv']!,
        ScriptType.p2wsh => throw UnimplementedError(
          'xprv generation for P2WSH is not implemented yet',
        ),
        ScriptType.p2tr => throw UnimplementedError(
          'xprv generation for Taproot is not implemented yet',
        ),
      },
      Network.testnet => switch (scriptType) {
        ScriptType.p2pkh => _prefixDict['tprv']!,
        ScriptType.p2sh => throw UnimplementedError(
          'xprv generation for P2SH is not implemented yet',
        ),
        ScriptType.p2shP2wpkh => _prefixDict['uprv']!,
        ScriptType.p2wpkh => _prefixDict['vprv']!,
        ScriptType.p2wsh => throw UnimplementedError(
          'xprv generation for P2WSH is not implemented yet',
        ),
        ScriptType.p2tr => throw UnimplementedError(
          'xprv generation for Taproot is not implemented yet',
        ),
      },
      Network.testnet4 => switch (scriptType) {
        ScriptType.p2pkh => _prefixDict['tprv']!,
        ScriptType.p2sh => throw UnimplementedError(
          'xprv generation for P2SH is not implemented yet',
        ),
        ScriptType.p2shP2wpkh => _prefixDict['uprv']!,
        ScriptType.p2wpkh => _prefixDict['vprv']!,
        ScriptType.p2wsh => throw UnimplementedError(
          'xprv generation for P2WSH is not implemented yet',
        ),
        ScriptType.p2tr => throw UnimplementedError(
          'xprv generation for Taproot is not implemented yet',
        ),
      },
      Network.regtest => switch (scriptType) {
        ScriptType.p2pkh => _prefixDict['tprv']!,
        ScriptType.p2sh => throw UnimplementedError(
          'xprv generation for P2SH is not implemented yet',
        ),
        ScriptType.p2shP2wpkh => _prefixDict['uprv']!,
        ScriptType.p2wpkh => _prefixDict['vprv']!,
        ScriptType.p2wsh => throw UnimplementedError(
          'xprv generation for P2WSH is not implemented yet',
        ),
        ScriptType.p2tr => throw UnimplementedError(
          'xprv generation for Taproot is not implemented yet',
        ),
      },
    };
    final depthHex = depth.toRadixString(16).padLeft(2, '0');
    final parentFingerprintHex = parentFingerprint
        .toRadixString(16)
        .padLeft(8, '0');
    final childNumberHex = childNumber.toRadixString(16).padLeft(8, '0');
    final chainCodeHex = bytesToHex(chainCode);
    final keyHex = '00${bytesToHex(privateKey)}';
    final serialized = hexToBytes(
      '$prefix$depthHex$parentFingerprintHex$childNumberHex$chainCodeHex$keyHex',
    );
    // Calculate the checksum
    final checksum = hash256(serialized).sublist(0, 4);
    // Return the xpriv in base58 format
    final xprivBytes = Uint8List.fromList(serialized + checksum);
    return base58Encode(xprivBytes);
  }
}
