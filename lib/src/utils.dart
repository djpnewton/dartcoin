import 'dart:math';
import 'dart:typed_data';

import 'ripemd160.dart';
import 'sha256.dart';

const _hexDigits = '0123456789abcdef';

String bytesToHex(Uint8List bytes) {
  // Lookup-table encoding into a code-unit buffer. This avoids per-byte
  // `toRadixString`/`padLeft`/StringBuffer overhead.
  final out = Uint8List(bytes.length * 2);
  var j = 0;
  for (final b in bytes) {
    out[j++] = _hexDigits.codeUnitAt((b >> 4) & 0xf);
    out[j++] = _hexDigits.codeUnitAt(b & 0xf);
  }
  return String.fromCharCodes(out);
}

String ibytesToHex(List<int> bytes) {
  return bytesToHex(Uint8List.fromList(bytes));
}

Uint8List hexToBytes(String hex) {
  // Decode using direct code-unit arithmetic instead of substring + int.parse
  // per byte.
  var start = 0;
  // skip a leading '0x' / '0X' prefix if present
  if (hex.length >= 2 &&
      hex.codeUnitAt(0) == 0x30 &&
      (hex.codeUnitAt(1) | 0x20) == 0x78) {
    start = 2;
  }
  final len = hex.length - start;
  if (len % 2 != 0) {
    throw ArgumentError('Hex string must have an even length');
  }
  final out = Uint8List(len ~/ 2);
  var oi = 0;
  for (var i = start; i < hex.length; i += 2) {
    out[oi++] =
        (_hexNibble(hex.codeUnitAt(i)) << 4) |
        _hexNibble(hex.codeUnitAt(i + 1));
  }
  return out;
}

int _hexNibble(int c) {
  if (c >= 0x30 && c <= 0x39) return c - 0x30; // '0'-'9'
  if (c >= 0x61 && c <= 0x66) return c - 0x57; // 'a'-'f'
  if (c >= 0x41 && c <= 0x46) return c - 0x37; // 'A'-'F'
  throw FormatException('Invalid hex character: ${String.fromCharCode(c)}');
}

extension HexString on String {
  Uint8List toBytes() => hexToBytes(this);
}

extension HexUint8List on Uint8List {
  String toHex() => bytesToHex(this);
  Uint8List reverse() => Uint8List.fromList(reversed.toList());
}

extension HexIntList on List<int> {
  String toHex() => ibytesToHex(this);
}

Uint8List randomBits(int bits) {
  assert(bits > 0);
  assert(bits % 8 == 0);
  int bytes = bits ~/ 8;
  final byteArray = Uint8List(bytes);
  final rand = Random.secure();
  while (bytes > 0) {
    final byte = rand.nextInt(256); // 2^8
    byteArray[--bytes] = byte;
  }
  return byteArray;
}

BigInt bytesToBigInt(Uint8List bytes, {Endian endian = Endian.big}) {
  BigInt result = BigInt.zero;
  if (endian == Endian.big) {
    for (int i = 0; i < bytes.length; i++) {
      result = (result << 8) + BigInt.from(bytes[i]);
    }
  } else {
    for (int i = bytes.length - 1; i >= 0; i--) {
      result = (result << 8) + BigInt.from(bytes[i]);
    }
  }
  return result;
}

Uint8List bigIntToBytes(
  BigInt value, {
  int? minLength,
  Endian endian = Endian.big,
}) {
  if (minLength != null && minLength < 0) {
    throw ArgumentError('Length must be non-negative');
  }
  if (value < BigInt.zero) {
    throw ArgumentError('Value must be non-negative');
  }
  final byteList = <int>[];
  if (endian == Endian.big) {
    while (value > BigInt.zero) {
      byteList.add((value & BigInt.from(0xFF)).toInt());
      value >>= 8;
    }
    if (minLength != null) {
      while (byteList.length < minLength) {
        byteList.add(0);
      }
    }
  } else {
    while (value > BigInt.zero) {
      byteList.insert(0, (value & BigInt.from(0xFF)).toInt());
      value >>= 8;
    }
    if (minLength != null) {
      while (byteList.length < minLength) {
        byteList.insert(0, 0);
      }
    }
  }
  return Uint8List.fromList(byteList.reversed.toList());
}

bool listEquals<T>(List<T>? a, List<T>? b) {
  if (a == null) {
    return b == null;
  }
  if (b == null || a.length != b.length) {
    return false;
  }
  if (identical(a, b)) {
    return true;
  }
  for (int index = 0; index < a.length; index += 1) {
    if (a[index] != b[index]) {
      return false;
    }
  }
  return true;
}

bool compareHashes(Uint8List hash1, Uint8List hash2) {
  if (hash1.length != hash2.length) {
    return false;
  }
  for (int i = 0; i < hash1.length; i++) {
    if (hash1[i] != hash2[i]) {
      return false;
    }
  }
  return true;
}

/// compute the hash256 (ie SHA-256(SHA-256(data))) of the input data
Uint8List hash256(Uint8List data) {
  final firstHash = sha256(data);
  final secondHash = sha256(firstHash);
  return secondHash;
}

/// compute the hash160 (ie RIPEMD-160(SHA-256(data))) of the input data
Uint8List hash160(Uint8List data) {
  final firstHash = sha256(data);
  final secondHash = ripemd160(firstHash);
  return secondHash;
}

Uint8List compactSize(int x) {
  // https://en.bitcoin.it/wiki/Protocol_documentation#Variable_length_integer
  if (x < 0) {
    throw ArgumentError('Value must be non-negative');
  }
  if (x < 0xFD) {
    return Uint8List.fromList([x]);
  } else if (x <= 0xFFFF) {
    return Uint8List.fromList([0xFD, x & 0xFF, (x >> 8) & 0xFF]);
  } else if (x <= 0xFFFFFFFF) {
    return Uint8List.fromList([
      0xFE,
      x & 0xFF,
      (x >> 8) & 0xFF,
      (x >> 16) & 0xFF,
      (x >> 24) & 0xFF,
    ]);
    // convert to BigInt for javascript compatibility
  } else if (BigInt.from(x) <= BigInt.parse('0x7FFFFFFFFFFFFFFF')) {
    return Uint8List.fromList([
      0xFF,
      x & 0xFF,
      (x >> 8) & 0xFF,
      (x >> 16) & 0xFF,
      (x >> 24) & 0xFF,
      (x >> 32) & 0xFF,
      (x >> 40) & 0xFF,
      (x >> 48) & 0xFF,
      (x >> 56) & 0xFF,
    ]);
  } else {
    // wont get hit as 0x7FFFFFFFFFFFFFFF is the max for a signed 64-bit integer
    throw ArgumentError('Integer too large for varint encoding: $x');
  }
}

class CompactSizeParseResult {
  final int value;
  final int bytesRead;

  CompactSizeParseResult(this.value, this.bytesRead);
}

CompactSizeParseResult compactSizeParse(Uint8List buffer) {
  if (buffer.isEmpty) {
    throw FormatException('Buffer is empty');
  }
  final firstByte = buffer[0];
  if (firstByte < 0xFD) {
    return CompactSizeParseResult(firstByte, 1);
  } else if (firstByte == 0xFD) {
    if (buffer.length < 3) {
      throw FormatException('Buffer too short for compact size');
    }
    return CompactSizeParseResult(buffer[1] | (buffer[2] << 8), 3);
  } else if (firstByte == 0xFE) {
    if (buffer.length < 5) {
      throw FormatException('Buffer too short for compact size');
    }
    return CompactSizeParseResult(
      buffer[1] | (buffer[2] << 8) | (buffer[3] << 16) | (buffer[4] << 24),
      5,
    );
  } else if (firstByte == 0xFF) {
    if (buffer.length < 9) {
      throw FormatException('Buffer too short for compact size');
    }
    return CompactSizeParseResult(
      buffer[1] |
          (buffer[2] << 8) |
          (buffer[3] << 16) |
          (buffer[4] << 24) |
          (buffer[5] << 32) |
          (buffer[6] << 40) |
          (buffer[7] << 48) |
          (buffer[8] << 56),
      9,
    );
  } else {
    throw FormatException('Invalid first byte for compact size: $firstByte');
  }
}

/// dart2js does not support setUint64
Uint8List setUint64JsSafe(int value, {Endian endian = Endian.big}) {
  final buffer = Uint8List(8);
  final byteData = buffer.buffer.asByteData();
  final high = value ~/ 0x100000000;
  final low = value % 0x100000000;
  if (endian == Endian.big) {
    byteData.setUint32(0, high, Endian.big);
    byteData.setUint32(4, low, Endian.big);
  } else {
    byteData.setUint32(4, high, Endian.little);
    byteData.setUint32(0, low, Endian.little);
  }
  return buffer;
}

/// dart2js does not support getUint64
int getUint64JsSafe(Uint8List bytes, {Endian endian = Endian.big}) {
  if (bytes.length < 8) {
    throw ArgumentError('Bytes must be at least 8 bytes long');
  }
  final byteData = bytes.buffer.asByteData();
  final int high;
  final int low;
  if (endian == Endian.big) {
    high = byteData.getUint32(0, Endian.big);
    low = byteData.getUint32(4, Endian.big);
  } else {
    high = byteData.getUint32(4, Endian.little);
    low = byteData.getUint32(0, Endian.little);
  }
  return high * 0x100000000 + low;
}
