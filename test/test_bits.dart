// ignore_for_file: avoid_relative_lib_imports
import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/bits.dart';

void main() {
  test('BitsWriter', () {
    final writer = BitsWriter();
    writer.writeBits(BigInt.from(5), 3);
    writer.writeBit(true);
    expect(writer.toString(), equals('1011'));
    expect(writer.toBytes(), equals(Uint8List.fromList([176])));
    writer.writeBit(true);
    expect(writer.toString(), equals('10111'));
    expect(writer.toBytes(), equals(Uint8List.fromList([184])));
    writer.writeBit(true);
    expect(writer.toString(), equals('101111'));
    expect(writer.toBytes(), equals(Uint8List.fromList([188])));
    writer.clear();
    writer.writeBit(true);
    expect(writer.toString(), equals('1'));
    expect(writer.toBytes(), equals(Uint8List.fromList([128])));
    writer.clear();
    writer.writeBits(BigInt.zero, 5);
    expect(writer.toString(), equals('00000'));
    writer.clear();
    writer.writeBits(BigInt.from(0xff), 5);
    expect(writer.toString(), equals('11111'));
    writer.clear();
    writer.writeBits(BigInt.zero, 16);
    expect(writer.toString(), equals('0000000000000000'));
    expect(writer.toBytes(), equals(Uint8List.fromList([0, 0])));
    writer.writeBit(true);
    expect(writer.toString(), equals('00000000000000001'));
    expect(writer.toBytes(), equals(Uint8List.fromList([0, 0, 128])));
  });

  test('BitsReader', () {
    var reader = BitsReader(Uint8List.fromList([0xff]));
    expect(reader.toString(), equals('11111111'));
    expect(reader.readBits(4), equals(15));
    expect(reader.toString(), equals('1111'));
    expect(reader.readBit(), equals(true));
    expect(reader.remainingBits(), equals(3));
    expect(reader.readBits(3), equals(7));
    expect(reader.remainingBits(), equals(0));
    expect(() => reader.readBit(), throwsRangeError);
    expect(() => reader.readBits(2), throwsRangeError);
    reader = BitsReader(Uint8List.fromList([0xaa, 0xaa]));
    expect(reader.toString(), equals('1010101010101010'));
    expect(() => reader.readBits(17), throwsRangeError);
    expect(reader.readBits(16), equals(0xaaaa));
    reader = BitsReader(Uint8List.fromList([0xaa, 0xaa]));
    expect(reader.readBits(8), equals(0xaa));
    expect(reader.toString(), equals('10101010'));
    expect(reader.readBits(8), equals(0xaa));
    expect(reader.toString(), equals(''));
    expect(reader.remainingBits(), equals(0));
    expect(() => reader.readBits(1), throwsRangeError);
    reader = BitsReader(Uint8List.fromList([0x0b]));
    expect(reader.toString(), equals('00001011'));
    expect(reader.readBits(5), equals(1));
    expect(reader.toString(), equals('011'));
    expect(reader.readBits(3), equals(3));
    expect(reader.toString(), equals(''));
    expect(reader.remainingBits(), equals(0));
  });
}
