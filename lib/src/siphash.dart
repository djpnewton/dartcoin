import 'dart:typed_data';

import 'utils.dart';

//
// SipHash-2-4
//

const cRounds = 2;
const dRounds = 4;

class SipHashState {
  BigInt v0;
  BigInt v1;
  BigInt v2;
  BigInt v3;

  SipHashState(this.v0, this.v1, this.v2, this.v3);

  @override
  String toString() {
    return 'SipHashState(v0: ${v0.toRadixString(16)}, v1: ${v1.toRadixString(16)}, v2: ${v2.toRadixString(16)}, v3: ${v3.toRadixString(16)})';
  }

  factory SipHashState.init() {
    return SipHashState(
      BigInt.parse("0x736f6d6570736575"),
      BigInt.parse("0x646f72616e646f6d"),
      BigInt.parse("0x6c7967656e657261"),
      BigInt.parse("0x7465646279746573"),
    );
  }

  static BigInt rotl(BigInt x, int b) {
    return (x << b) | (x >> (64 - b));
  }

  void sipRound() {
    v0 += v1;
    v0 = v0.toUnsigned(64);
    v1 = rotl(v1, 13).toUnsigned(64);
    v1 ^= v0;
    v1 = v1.toUnsigned(64);
    v0 = rotl(v0, 32).toUnsigned(64);
    v2 += v3;
    v2 = v2.toUnsigned(64);
    v3 = rotl(v3, 16).toUnsigned(64);
    v3 ^= v2;
    v3 = v3.toUnsigned(64);
    v0 += v3;
    v0 = v0.toUnsigned(64);
    v3 = rotl(v3, 21).toUnsigned(64);
    v3 ^= v0;
    v3 = v3.toUnsigned(64);
    v2 += v1;
    v2 = v2.toUnsigned(64);
    v1 = rotl(v1, 17).toUnsigned(64);
    v1 ^= v2;
    v1 = v1.toUnsigned(64);
    v2 = rotl(v2, 32).toUnsigned(64);
  }
}

/// Computes SipHash-2-4 for the given input and key.
/// The key should be 16-bytes. The output is a 8-byte hash.
BigInt siphash(Uint8List input, Uint8List key) {
  if (key.length != 16) {
    throw ArgumentError('Key must be 16 bytes long');
  }

  final state = SipHashState.init();
  var k0 = bytesToBigInt(key.sublist(0, 8), endian: Endian.little);
  var k1 = bytesToBigInt(key.sublist(8, 16), endian: Endian.little);
  final endIndex = input.length - (input.length % 8);
  final left = input.length & 7;
  var b = input.length << 56;
  state.v3 ^= k1;
  state.v2 ^= k0;
  state.v1 ^= k1;
  state.v0 ^= k0;

  BigInt m;
  for (int i = 0; i < endIndex; i += 8) {
    m = bytesToBigInt(input.sublist(i, i + 8), endian: Endian.little);
    state.v3 ^= m;

    for (int j = 0; j < cRounds; ++j) {
      state.sipRound();
    }

    state.v0 ^= m;
  }

  switch (left) {
    case 7:
      b |= input[endIndex + 6] << 48;
      continue six;
    six:
    case 6:
      b |= input[endIndex + 5] << 40;
      continue five;
    five:
    case 5:
      b |= input[endIndex + 4] << 32;
      continue four;
    four:
    case 4:
      b |= input[endIndex + 3] << 24;
      continue three;
    three:
    case 3:
      b |= input[endIndex + 2] << 16;
      continue two;
    two:
    case 2:
      b |= input[endIndex + 1] << 8;
      continue one;
    one:
    case 1:
      b |= input[endIndex];
  }

  state.v3 ^= BigInt.from(b);

  for (int i = 0; i < cRounds; ++i) {
    state.sipRound();
  }

  state.v0 ^= BigInt.from(b);
  state.v2 ^= BigInt.from(0xff);

  for (int i = 0; i < dRounds; ++i) {
    state.sipRound();
  }

  return (state.v0 ^ state.v1 ^ state.v2 ^ state.v3).toUnsigned(64);
}

Uint8List siphashBytes(Uint8List input, Uint8List key) {
  return bigIntToBytes(
    siphash(input, key),
    minLength: 8,
    endian: Endian.little,
  );
}
