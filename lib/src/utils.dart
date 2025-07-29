import 'dart:math';
import 'dart:typed_data';

import 'ripemd160.dart';
import 'sha256.dart';

String bytesToHex(Uint8List bytes) {
  BigInt value = bytesToBigInt(bytes);
  return value.toRadixString(16).padLeft(bytes.length * 2, '0');
}

Uint8List hexToBytes(String hex) {
  if (hex.length % 2 != 0) {
    throw ArgumentError('Hex string must have an even length');
  }
  // remove any leading '0x' if present
  if (hex.startsWith('0x')) {
    hex = hex.substring(2);
  }
  final byteList = Uint8List(hex.length ~/ 2);
  for (int i = 0; i < hex.length; i += 2) {
    final byte = int.parse(hex.substring(i, i + 2), radix: 16);
    byteList[i ~/ 2] = byte;
  }
  return byteList;
}

extension HexString on String {
  Uint8List toBytes() => hexToBytes(this);
}

extension HexUint8List on Uint8List {
  String toHex() => bytesToHex(this);
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

BigInt bytesToBigInt(Uint8List bytes) {
  BigInt result = BigInt.zero;
  for (int i = 0; i < bytes.length; i++) {
    result = (result << 8) + BigInt.from(bytes[i]);
  }
  return result;
}

Uint8List bigIntToBytes(BigInt value, {int? minLength}) {
  if (minLength != null && minLength < 0) {
    throw ArgumentError('Length must be non-negative');
  }
  if (value < BigInt.zero) {
    throw ArgumentError('Value must be non-negative');
  }
  final byteList = <int>[];
  while (value > BigInt.zero) {
    byteList.add((value & BigInt.from(0xFF)).toInt());
    value >>= 8;
  }
  if (minLength != null) {
    while (byteList.length < minLength) {
      byteList.add(0);
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
  if (endian == Endian.big) {
    byteData.setUint32(0, (value >> 32) & 0xFFFFFFFF, Endian.big);
    byteData.setUint32(4, value & 0xFFFFFFFF, Endian.big);
  } else {
    byteData.setUint32(4, (value >> 32) & 0xFFFFFFFF, Endian.little);
    byteData.setUint32(0, value & 0xFFFFFFFF, Endian.little);
  }
  return buffer;
}

/// dart2js does not support getUint64
int getUint64JsSafe(Uint8List bytes, {Endian endian = Endian.big}) {
  if (bytes.length < 8) {
    throw ArgumentError('Bytes must be at least 8 bytes long');
  }
  final byteData = bytes.buffer.asByteData();
  if (endian == Endian.big) {
    return (byteData.getUint32(0, Endian.big) << 32) |
        byteData.getUint32(4, Endian.big);
  } else {
    return (byteData.getUint32(4, Endian.little) << 32) |
        byteData.getUint32(0, Endian.little);
  }
}
