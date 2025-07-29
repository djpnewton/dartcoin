// ignore_for_file: constant_identifier_names

import 'dart:typed_data';

import 'utils.dart';

class _State {
  int h0;
  int h1;
  int h2;
  int h3;
  int h4;
  _State(this.h0, this.h1, this.h2, this.h3, this.h4);
  _State clone() {
    return _State(h0, h1, h2, h3, h4);
  }

  @override
  String toString() {
    return 'h0=${h0.toRadixString(16)}, h1=${h1.toRadixString(16)}, h2=${h2.toRadixString(16)}, h3=${h3.toRadixString(16)}, h4=${h4.toRadixString(16)}';
  }
}

// dart format off
// message schedule left path
const _ML = [
    0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    7, 4, 13, 1, 10, 6, 15, 3, 12, 0, 9, 5, 2, 14, 11, 8,
    3, 10, 14, 4, 9, 15, 8, 1, 2, 7, 0, 6, 13, 11, 5, 12,
    1, 9, 11, 10, 0, 8, 12, 4, 13, 3, 7, 15, 14, 5, 6, 2,
    4, 0, 5, 9, 7, 12, 2, 10, 14, 1, 3, 8, 11, 6, 15, 13
];

// message schedule right path
const _MR = [
    5, 14, 7, 0, 9, 2, 11, 4, 13, 6, 15, 8, 1, 10, 3, 12,
    6, 11, 3, 7, 0, 13, 5, 10, 14, 15, 8, 12, 4, 9, 1, 2,
    15, 5, 1, 3, 7, 14, 6, 9, 11, 8, 12, 2, 10, 0, 4, 13,
    8, 6, 4, 1, 3, 11, 15, 0, 5, 12, 2, 13, 9, 7, 10, 14,
    12, 15, 10, 4, 1, 5, 8, 7, 6, 2, 13, 14, 0, 3, 9, 11
];

// rotation counts left path
const _RL = [
    11, 14, 15, 12, 5, 8, 7, 9, 11, 13, 14, 15, 6, 7, 9, 8,
    7, 6, 8, 13, 11, 9, 7, 15, 7, 12, 15, 9, 11, 7, 13, 12,
    11, 13, 6, 7, 14, 9, 13, 15, 14, 8, 13, 6, 5, 12, 7, 5,
    11, 12, 14, 15, 14, 15, 9, 8, 9, 14, 5, 6, 8, 6, 5, 12,
    9, 15, 5, 11, 6, 8, 13, 12, 5, 12, 13, 14, 11, 8, 5, 6
];

// rotation counts right path
const _RR = [
    8, 9, 9, 11, 13, 15, 15, 5, 7, 7, 8, 11, 14, 14, 12, 6,
    9, 13, 15, 7, 12, 8, 9, 11, 7, 7, 12, 7, 6, 15, 13, 11,
    9, 7, 15, 11, 8, 6, 6, 14, 12, 13, 5, 14, 13, 13, 7, 5,
    15, 5, 8, 11, 14, 14, 6, 14, 6, 9, 12, 9, 12, 5, 15, 8,
    8, 5, 12, 9, 12, 5, 14, 6, 8, 13, 6, 5, 15, 13, 11, 11
];
// dart format on

// K constants left path.
const _KL = [0, 0x5a827999, 0x6ed9eba1, 0x8f1bbcdc, 0xa953fd4e];

// K constants path.
const _KR = [0x50a28be6, 0x5c4dd124, 0x6d703ef3, 0x7a6d76e9, 0];

int _rol(int x, int i) {
  return ((x << i) | ((x & 0xffffffff) >> (32 - i))) & 0xffffffff;
}

int _f(int round, int x, int y, int z) {
  switch (round) {
    case 0:
      // F1
      return x ^ y ^ z;
    case 1:
      // F2
      return (x & y) | (~x & z);
    case 2:
      // F3
      return (x | ~y) ^ z;
    case 3:
      // F4
      return (x & z) | (y & ~z);
    case 4:
      // F5
      return x ^ (y | ~z);
    default:
      throw ArgumentError('Invalid round: $round');
  }
}

_State _compress(_State state, Uint8List block) {
  final lp = state.clone();
  final rp = state.clone();
  final x = List<int>.generate(16, (i) {
    return block.buffer.asByteData().getUint32(i * 4, Endian.little);
  });
  for (var i = 0; i < 80; i++) {
    final round = i ~/ 16;
    // left path
    lp.h0 =
        _rol(
          lp.h0 + _f(round, lp.h1, lp.h2, lp.h3) + x[_ML[i]] + _KL[round],
          _RL[i],
        ) +
        lp.h4;
    var tmp = lp.clone();
    lp.h0 = tmp.h4;
    lp.h1 = tmp.h0;
    lp.h2 = tmp.h1;
    lp.h3 = _rol(tmp.h2, 10);
    lp.h4 = tmp.h3;
    // right path
    rp.h0 =
        _rol(
          rp.h0 + _f(4 - round, rp.h1, rp.h2, rp.h3) + x[_MR[i]] + _KR[round],
          _RR[i],
        ) +
        rp.h4;
    tmp = rp.clone();
    rp.h0 = tmp.h4;
    rp.h1 = tmp.h0;
    rp.h2 = tmp.h1;
    rp.h3 = _rol(tmp.h2, 10);
    rp.h4 = tmp.h3;
  }
  return _State(
    state.h1 + lp.h2 + rp.h3,
    state.h2 + lp.h3 + rp.h4,
    state.h3 + lp.h4 + rp.h0,
    state.h4 + lp.h0 + rp.h1,
    state.h0 + lp.h1 + rp.h2,
  );
}

Uint8List ripemd160(Uint8List input) {
  // initialize state
  var state = _State(
    0x67452301,
    0xefcdab89,
    0x98badcfe,
    0x10325476,
    0xc3d2e1f0,
  );
  // process the input in (full) 64-byte blocks
  for (var i = 0; i < input.length >> 6; i++) {
    final block = input.sublist(i * 64, (i + 1) * 64);
    assert(block.length == 64, 'Block must be 64 bytes');
    state = _compress(state, block);
  }
  // pad the final 1 or 2 blocks
  final padding = Uint8List.fromList([
    0x80, // append a single 1 bit (0x80)
    // padding zeros
    ...List.filled((119 - input.length) & 63, 0),
    // append the length of the input
    ...setUint64JsSafe(input.length * 8, endian: Endian.little),
  ]);
  final finalBlocks = Uint8List.fromList([
    ...input.sublist(input.length & ~63),
    ...padding,
  ]);
  for (var i = 0; i < finalBlocks.length >> 6; i++) {
    final block = finalBlocks.sublist(i * 64, (i + 1) * 64);
    assert(block.length == 64, 'Block must be 64 bytes');
    state = _compress(state, block);
  }
  // produce the final hash
  final hash = Uint8List(20);
  hash.buffer.asByteData().setUint32(0, state.h0, Endian.little);
  hash.buffer.asByteData().setUint32(4, state.h1, Endian.little);
  hash.buffer.asByteData().setUint32(8, state.h2, Endian.little);
  hash.buffer.asByteData().setUint32(12, state.h3, Endian.little);
  hash.buffer.asByteData().setUint32(16, state.h4, Endian.little);
  return hash;
}
