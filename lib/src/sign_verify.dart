import 'dart:typed_data';
import 'dart:convert';

import 'common.dart';
import 'utils.dart';
import 'secp256k1.dart';
import 'keys.dart';
import 'rfc6979.dart';
import 'sha256.dart';
import 'address.dart';

class Signature {
  BigInt r;
  BigInt s;

  Signature(this.r, this.s);
}

class SignatureWithY extends Signature {
  /// y coordinate of the point R
  BigInt y;

  SignatureWithY(super.r, super.s, this.y);
}

class BitcoinSignedMessage {
  final String address;
  final String signature;

  BitcoinSignedMessage(this.address, this.signature);
}

class DERSignature {
  final Uint8List publicKey;
  final Uint8List signature;

  DERSignature(this.publicKey, this.signature);
}

Uint8List _formatDER(Signature sig) {
  var rBytes = bigIntToBytes(sig.r);
  if (rBytes.length > 32) {
    throw ArgumentError('R value is too large for a signature');
  }
  if (rBytes[0] > 0x7F) {
    rBytes = Uint8List.fromList([0x00, ...rBytes]);
  }
  var sBytes = bigIntToBytes(sig.s);
  if (sBytes.length > 32) {
    throw ArgumentError('S value is too large for a signature');
  }
  if (sBytes[0] > 0x7F) {
    sBytes = Uint8List.fromList([0x00, ...sBytes]);
  }
  // DER encoding: 0x30 + length + 0x02 + r length + r + 0x02 + s length + s
  final length = 4 + rBytes.length + sBytes.length;
  return Uint8List.fromList([
    0x30,
    length,
    0x02,
    rBytes.length,
    ...rBytes,
    0x02,
    sBytes.length,
    ...sBytes,
  ]);
}

Signature _parseDER(Uint8List der) {
  // 0x30,LENGTH,0x02,RLENGTH,R,0x02,SLENGTH,S
  final minLength = 8;
  // first byte is 0x30
  if (der.isEmpty || der[0] != 0x30) {
    throw FormatException('Invalid DER signature format');
  }
  if (der.length < minLength) {
    throw FormatException('DER signature too short');
  }
  // the second byte is the length of the signature overall
  final length = der[1];
  if (der.length != length + 2) {
    throw FormatException('Invalid DER signature length');
  }
  // next byte should be 0x02 for the r value
  if (der[2] != 0x02) {
    throw FormatException('Invalid DER signature r value');
  }
  final rLength = der[3];
  if (rLength < 1 || rLength > 33 || rLength + 4 > der.length) {
    throw FormatException('Invalid DER signature r length');
  }
  final rBytes = der.sublist(4, 4 + rLength);
  final r = bytesToBigInt(rBytes);
  if (der.length <= 6 + rLength) {
    throw FormatException('DER signature too short for s value');
  }
  // next byte should be 0x02 for the s value
  if (der[4 + rLength] != 0x02) {
    throw FormatException('Invalid DER signature s value');
  }
  final sLength = der[5 + rLength];
  if (sLength < 1 || sLength > 33 || sLength + 6 + rLength > der.length) {
    throw FormatException('Invalid DER signature s length');
  }
  final sBytes = der.sublist(6 + rLength, 6 + rLength + sLength);
  final s = bytesToBigInt(sBytes);
  return Signature(r, s);
}

SignatureWithY sign(PrivateKey pk, Uint8List hash) {
  // generate a nonce using RFC 6979
  final nonce = generateK(pk.privateKey, hash);
  // ensure the nonce is less than the secp256k1 order
  if (nonce >= Secp256k1Point.n) {
    throw ArgumentError(
      'Nonce is greater than or equal to the secp256k1 order',
    );
  }
  // x value of a random point on the curve
  final R = Secp256k1Point.generator.multiply(nonce);
  final r = R.x;
  final y = R.y;
  // check if r is zero
  if (r == BigInt.zero) {
    throw ArgumentError('R value is zero, cannot sign with this nonce');
  }
  // s = nonce⁻¹ * (hash + private_key * r) mod n
  final s =
      (modInverse(nonce, Secp256k1Point.n) *
          (bytesToBigInt(hash) + (r * bytesToBigInt(pk.privateKey)))) %
      Secp256k1Point.n;
  // check if s is zero, if so, generate a new nonce
  if (s == BigInt.zero) {
    throw ArgumentError('S value is zero, cannot sign with this nonce');
  }
  // ensure low s value
  if (s > Secp256k1Point.n >> 1) {
    // s is greater than n/2, we can use n - s to get a lower value
    return SignatureWithY(r, Secp256k1Point.n - s, y);
  }
  // s is already low, return the signature as is
  return SignatureWithY(r, s, y);
}

bool verify(PublicKey pk, Uint8List hash, Signature sig) {
  // check if r and s are valid
  if (sig.r <= BigInt.zero ||
      sig.r >= Secp256k1Point.n ||
      sig.s <= BigInt.zero ||
      sig.s >= Secp256k1Point.n) {
    return false;
  }
  // calculate the public key point from the public key
  final publicKeyPoint = pk.point();
  // s⁻¹
  final sInv = modInverse(sig.s, Secp256k1Point.n);
  // G(s⁻¹ * z)
  final p1 = Secp256k1Point.generator.multiply(sInv * bytesToBigInt(hash));
  // Q(s⁻¹ * r)
  final p2 = publicKeyPoint.multiply(sInv * sig.r);
  // R = G(s⁻¹ * z) + Q(s⁻¹ * r)
  final R = p1.add(p2);
  // check if R.x matches the signature r
  return R.x == sig.r;
}

Uint8List _bitcoinMessageHash(Uint8List message) {
  // wrap the message in the Bitcoin signed message header
  final headerLen = 0x18;
  final header = utf8.encode('Bitcoin Signed Message:\n');
  message = Uint8List.fromList([
    headerLen,
    ...header,
    ...compactSize(message.length),
    ...message,
  ]);
  // hash the message using double SHA-256
  return hash256(message);
}

/// create a Bitcoin signed message (https://github.com/fivepiece/sign-verify-message/blob/master/signverifymessage.md)
BitcoinSignedMessage bitcoinSignedMessageSign(
  PrivateKey pk,
  Uint8List message,
  Network network,
  ScriptType scriptType,
) {
  // wrap the message in the Bitcoin signed message header
  final hash = _bitcoinMessageHash(message);
  // create signature
  final sig = sign(pk, hash);
  // create the recovery ID
  var recId = (sig.y & BigInt.one).toInt();
  if (sig.s > Secp256k1Point.n >> 1) {
    recId += 1;
  }
  recId = switch (scriptType) {
    ScriptType.p2pkh => 31 + recId,
    ScriptType.p2sh => throw UnimplementedError(
      'Bitcoin signed message for P2SH is not implemented yet',
    ),
    ScriptType.p2shP2wpkh => 35 + recId,
    ScriptType.p2wpkh => 39 + recId,
    ScriptType.p2wsh => throw UnimplementedError(
      'Bitcoin signed message for P2WSH is not implemented yet',
    ),
    ScriptType.p2tr => throw UnimplementedError(
      'Bitcoin signed message for Taproot is not implemented yet',
    ),
  };
  // encode the signature in base64
  // the signature is a concatenation of the recovery ID, r and s values
  final signature = base64Encode(
    Uint8List.fromList([
      recId,
      ...bigIntToBytes(sig.r, minLength: 32),
      ...bigIntToBytes(sig.s, minLength: 32),
    ]),
  );
  // get the address from the public key
  final address = pk.address(network: network, scriptType: scriptType);
  return BitcoinSignedMessage(address, signature);
}

bool bitcoinSignedMessageVerify(
  String address,
  Uint8List message,
  String signature,
) {
  // wrap the message in the Bitcoin signed message header and hash it
  final hash = _bitcoinMessageHash(message);
  // decode the signature from base64
  final sigBytes = base64Decode(signature);
  if (sigBytes.length != 65) {
    throw ArgumentError('Invalid signature length, expected 65 bytes');
  }
  // extract the recovery ID, r and s values
  var header = sigBytes[0];
  final r = bytesToBigInt(sigBytes.sublist(1, 33));
  final s = bytesToBigInt(sigBytes.sublist(33, 65));
  if (r <= BigInt.zero || r >= Secp256k1Point.n) {
    throw ArgumentError('Invalid R value: $r');
  }
  if (s <= BigInt.zero || s >= Secp256k1Point.n) {
    throw ArgumentError('Invalid S value: $s');
  }
  // get the script type and recovery Id from the header byte
  final (scriptType, recId) = switch (header) {
    >= 31 && <= 34 => (ScriptType.p2pkh, header - 31),
    >= 35 && <= 38 => (ScriptType.p2shP2wpkh, header - 35),
    >= 39 && <= 42 => (ScriptType.p2wpkh, header - 39),
    _ => throw ArgumentError('Invalid header: $header'),
  };
  // recover the public key from the signature
  final x = r + Secp256k1Point.n * BigInt.from(recId >> 1);
  final R = Secp256k1Point.fromX(
    x,
    recId & 0x1 == 0 ? YParity.even : YParity.odd,
  );
  // Q = r^−1 * (sR − eG)
  final z = bytesToBigInt(hash);
  final e = (-z) % Secp256k1Point.n;
  final sR = R.multiply(s);
  final eG = Secp256k1Point.generator.multiply(e);
  final rInv = modInverse(r, Secp256k1Point.n);
  final Q = sR.add(eG).multiply(rInv);
  // create the public key from the recovered point
  final pk = PublicKey.fromPoint(Q);
  final (addrMainnet, addrTestnet) = switch (scriptType) {
    ScriptType.p2pkh => (
      p2pkhAddress(pk.publicKey, network: Network.mainnet),
      p2pkhAddress(pk.publicKey, network: Network.testnet),
    ),
    ScriptType.p2sh => throw UnimplementedError(
      'Bitcoin signed message for P2SH is not implemented yet',
    ),
    ScriptType.p2shP2wpkh => (
      p2shP2wpkhAddress(pk.publicKey, network: Network.mainnet),
      p2shP2wpkhAddress(pk.publicKey, network: Network.testnet),
    ),
    ScriptType.p2wpkh => (
      p2wpkhAddress(pk.publicKey, network: Network.mainnet),
      p2wpkhAddress(pk.publicKey, network: Network.testnet),
    ),
    ScriptType.p2wsh => throw UnimplementedError(
      'Bitcoin signed message for P2WSH is not implemented yet',
    ),
    ScriptType.p2tr => throw UnimplementedError(
      'Bitcoin signed message for Taproot is not implemented yet',
    ),
  };
  // check if the address matches the provided address
  if (addrMainnet == address || addrTestnet == address) {
    return true;
  }
  return false;
}

DERSignature derSignMessage(PrivateKey pk, Uint8List message) {
  // hash the message using SHA-256
  final hash = sha256(message);
  // create signature
  return derSignHash(pk, hash);
}

bool derVerifyMessage(PublicKey pk, Uint8List message, Uint8List derSignature) {
  // hash the message using SHA-256
  final hash = sha256(message);
  // verify the signature
  return derVerifyHash(pk, hash, derSignature);
}

DERSignature derSignHash(PrivateKey pk, Uint8List hash) {
  // create signature
  final sig = sign(pk, hash);
  // convert the signature to DER format
  return DERSignature(pk.publicKey, _formatDER(sig));
}

bool derVerifyHash(PublicKey pk, Uint8List hash, Uint8List derSignature) {
  // parse the DER signature
  final sig = _parseDER(derSignature);
  // verify the signature
  return verify(pk, hash, sig);
}
