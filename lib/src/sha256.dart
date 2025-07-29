import 'dart:typed_data';

import 'utils.dart';

class _State {
  int h0;
  int h1;
  int h2;
  int h3;
  int h4;
  int h5;
  int h6;
  int h7;
  _State(
    this.h0,
    this.h1,
    this.h2,
    this.h3,
    this.h4,
    this.h5,
    this.h6,
    this.h7,
  );
  _State clone() {
    return _State(h0, h1, h2, h3, h4, h5, h6, h7);
  }
}

const int _maxInt32 = 0xFFFFFFFF;

// dart format off
const _k = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
];
// dart format on

Uint8List _padData(Uint8List input) {
  final length = input.length * 8; // length in bits of input
  final data = BytesBuilder();
  data.add(input);
  data.addByte(0x80);
  while ((data.length + 8) % 64 != 0) {
    data.addByte(0x00);
  }
  data.add(setUint64JsSafe(length, endian: Endian.big));

  assert(data.length % 64 == 0);
  return data.toBytes();
}

_State _initializeState() {
  return _State(
    0x6a09e667, // h0
    0xbb67ae85, // h1
    0x3c6ef372, // h2
    0xa54ff53a, // h3
    0x510e527f, // h4
    0x9b05688c, // h5
    0x1f83d9ab, // h6
    0x5be0cd19, // h7
  );
}

int _rotateRight(int x, int n) {
  return (x >> n) | (x << (32 - n)) & _maxInt32;
}

int _sigma0(int x) {
  return _rotateRight(x, 7) ^ _rotateRight(x, 18) ^ (x >> 3);
}

int _sigma1(int x) {
  return _rotateRight(x, 17) ^ _rotateRight(x, 19) ^ (x >> 10);
}

int _sum0(int x) {
  return _rotateRight(x, 2) ^ _rotateRight(x, 13) ^ _rotateRight(x, 22);
}

int _sum1(int x) {
  return _rotateRight(x, 6) ^ _rotateRight(x, 11) ^ _rotateRight(x, 25);
}

int _ch(int x, int y, int z) {
  return (x & y) ^ (~x & z);
}

int _maj(int x, int y, int z) {
  return (x & y) ^ (x & z) ^ (y & z);
}

_State _processBlock(Uint8List block, _State state) {
  // prepare the message schedule
  final w = List<int>.filled(64, 0);
  for (var i = 0; i < 16; i++) {
    w[i] = block.buffer.asByteData().getUint32(i * 4, Endian.big);
  }
  for (var i = 16; i < 64; i++) {
    final term1 = _sigma1(w[i - 2]);
    final term2 = w[i - 7];
    final term3 = _sigma0(w[i - 15]);
    final term4 = w[i - 16];
    w[i] = (term1 + term2 + term3 + term4) & _maxInt32;
  }

  // initialize working variables
  var a = state.h0;
  var b = state.h1;
  var c = state.h2;
  var d = state.h3;
  var e = state.h4;
  var f = state.h5;
  var g = state.h6;
  var h = state.h7;

  // main loop
  for (var i = 0; i < 64; i++) {
    final term1 = (h + _sum1(e) + _ch(e, f, g) + _k[i] + w[i]) & _maxInt32;
    final term2 = (_sum0(a) + _maj(a, b, c)) & _maxInt32;

    h = g;
    g = f;
    f = e;
    e = (d + term1) & _maxInt32;
    d = c;
    c = b;
    b = a;
    a = (term1 + term2) & _maxInt32;
  }

  // intermediate hash value
  state.h0 = (state.h0 + a) & _maxInt32;
  state.h1 = (state.h1 + b) & _maxInt32;
  state.h2 = (state.h2 + c) & _maxInt32;
  state.h3 = (state.h3 + d) & _maxInt32;
  state.h4 = (state.h4 + e) & _maxInt32;
  state.h5 = (state.h5 + f) & _maxInt32;
  state.h6 = (state.h6 + g) & _maxInt32;
  state.h7 = (state.h7 + h) & _maxInt32;

  return state;
}

Uint8List _finalHash(_State state) {
  final hash = Uint8List(32);
  hash.buffer.asByteData().setUint32(0, state.h0, Endian.big);
  hash.buffer.asByteData().setUint32(4, state.h1, Endian.big);
  hash.buffer.asByteData().setUint32(8, state.h2, Endian.big);
  hash.buffer.asByteData().setUint32(12, state.h3, Endian.big);
  hash.buffer.asByteData().setUint32(16, state.h4, Endian.big);
  hash.buffer.asByteData().setUint32(20, state.h5, Endian.big);
  hash.buffer.asByteData().setUint32(24, state.h6, Endian.big);
  hash.buffer.asByteData().setUint32(28, state.h7, Endian.big);
  return hash;
}

Uint8List sha256(Uint8List data) {
  final paddedData = _padData(data);
  var state = _initializeState();

  for (var i = 0; i < paddedData.length; i += 64) {
    final block = paddedData.sublist(i, i + 64);
    state = _processBlock(block, state);
  }

  return _finalHash(state);
}
