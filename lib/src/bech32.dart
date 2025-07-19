import 'dart:convert';
import 'dart:typed_data';

import 'common.dart';

class Bech32 {
  Uint8List scriptPubKey;
  Network network;
  Bech32(this.scriptPubKey, this.network);
}

final _alphabet = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

Uint8List _hrpExpand(String hrp) {
  final hrpBytes = utf8.encode(hrp);
  final hrpExpanded = Uint8List(hrpBytes.length * 2 + 1);
  for (var i = 0; i < hrpBytes.length; i++) {
    hrpExpanded[i] = hrpBytes[i] >> 5;
  }
  hrpExpanded[hrpBytes.length]; // separator
  for (var i = 0; i < hrpBytes.length; i++) {
    hrpExpanded[hrpBytes.length + i + 1] = hrpBytes[i] & 0x1F; // 11111 = 1F
  }
  return hrpExpanded;
}

List<String> _splitChunks(String input, {int chunk = 5}) {
  if (chunk <= 0) {
    throw ArgumentError('Chunk size must be greater than zero');
  }
  List<String> list = [];
  if (input.isEmpty) {
    return [];
  }
  if (input.length <= chunk) {
    return [input];
  }
  var i = 0;
  for (i = 0; i < (input.length ~/ chunk); i++) {
    var temp = input.substring(i * chunk, i * chunk + chunk);
    list.add(temp);
  }
  if (input.length % chunk != 0) {
    list.add(input.substring(i * chunk, input.length));
  }
  return list;
}

Uint8List _convert8BitTo5Bit(Uint8List input) {
  final strs8bit = input
      .map((byte) => byte.toRadixString(2).padLeft(8, '0'))
      .join('');
  final strs5bit = _splitChunks(strs8bit);
  return Uint8List.fromList(
    strs5bit.map((s) => int.parse(s, radix: 2)).toList(),
  );
}

Uint8List _convert5BitTo8Bit(Uint8List input) {
  // join to big binary string
  var strJoined = input
      .map((byte) => byte.toRadixString(2).padLeft(5, '0'))
      .join('');
  if (strJoined.length % 8 != 0) {
    strJoined = strJoined.substring(
      0,
      strJoined.length - (strJoined.length % 8),
    );
  }
  // Split the string into 8-bit chunks
  final chunks = _splitChunks(strJoined, chunk: 8);
  // Convert each chunk back to an integer
  final bytes = chunks.map((chunk) => int.parse(chunk, radix: 2)).toList();
  // Return as Uint8List
  return Uint8List.fromList(bytes);
}

Uint8List _checksumAs5Bits(int value) {
  if (value < 0 || value > 0x3FFFFFFF) {
    throw ArgumentError('Value must be between 0 and 3FFFFFFF');
  }
  final strs5bit = _splitChunks(value.toRadixString(2).padLeft(30, '0'));
  return Uint8List.fromList(
    strs5bit.map((s) => int.parse(s, radix: 2)).toList(),
  );
}

Uint8List _bech32Checksum(
  Uint8List hrp,
  int version,
  Uint8List witnessProgram5Bit,
) {
  // checksum input
  final checksumInput = <int>[
    ...hrp,
    version,
    ...witnessProgram5Bit,
    0,
    0,
    0,
    0,
    0,
    0,
  ];
  // initial checksum value
  var checksum = 1;
  // setup generator
  final generator = [
    int.parse('111011011010100101011110110010', radix: 2),
    int.parse('100110010100001000111001101101', radix: 2),
    int.parse('011110101000010001100111111010', radix: 2),
    int.parse('111101010000100011001111011101', radix: 2),
    int.parse('101010000101000110001010110011', radix: 2),
  ];
  // calculate checksum
  for (var i = 0; i < checksumInput.length; i++) {
    // get top 5 bits
    var top = checksum >> (30 - 5);
    // get bottom 25 bits
    var bottom = checksum & 0x1FFFFFF; // 1111111111111111111111111 (25 bits)
    // pad bottom with 5 bits
    bottom = bottom << 5;
    // get next value from checksum input
    var nextValue = checksumInput[i];
    // XOR with
    checksum = bottom ^ nextValue;

    // XOR with generator
    if (top & 1 == 1) {
      checksum ^= generator[0];
    }
    if (top & 1 << 1 == 1 << 1) {
      checksum ^= generator[1];
    }
    if (top & 1 << 2 == 1 << 2) {
      checksum ^= generator[2];
    }
    if (top & 1 << 3 == 1 << 3) {
      checksum ^= generator[3];
    }
    if (top & 1 << 4 == 1 << 4) {
      checksum ^= generator[4];
    }
  }
  // XOR with constant
  if (version == 0) {
    // constant for bech32
    checksum ^= 1;
  } else {
    // constant for bech32m
    checksum ^= 0x2BC830A3; // 101011110010000011000010100011 = 2BC830A3
  }
  // split checksum into 5-bit groups
  return _checksumAs5Bits(checksum);
}

String bech32Encode(
  Uint8List scriptPubKey, {
  Network network = Network.mainnet,
}) {
  // human readable part (hrp) based on the network
  final hrp = switch (network) {
    Network.mainnet => 'bc',
    Network.testnet => 'tb',
    Network.testnet4 => 'tb',
  };
  // check scriptPubKey length
  if (scriptPubKey.length < 2) {
    throw ArgumentError('Invalid scriptPubKey length: ${scriptPubKey.length}');
  }
  // get the witness version
  final version = scriptPubKey[0];
  // witness version should be between OP_0 and OP_16
  if (version != 0 && (version < 0x51 || version > 0x60)) {
    throw ArgumentError('Invalid witness version: $version');
  }
  // get the witness size
  final size = scriptPubKey[1];
  // size should be 20 bytes (public key hash - P2WPKH, script hash - P2WSH) or 32 bytes (tweaked public key - P2TR)
  if (version == 0 && size != 20 && size != 32) {
    throw ArgumentError('Invalid witness size: $size (expected 20 or 32)');
  }
  if (version == 0x51 && size != 32) {
    throw ArgumentError('Invalid witness size: $size (expected 32)');
  }
  // check sciptPubKey length
  if (scriptPubKey.length != size + 2) {
    throw ArgumentError(
      'Invalid scriptPubKey length: ${scriptPubKey.length}, expected: ${size + 2}',
    );
  }
  // expand hrp to 5-bit groups
  final hrpExpanded = _hrpExpand(hrp);
  // bech32 version as 5-bit group
  final bech32Version = (version == 0 ? 0 : version - 0x50);
  // convert witness program to 5-bit values
  var witnessProgram = _convert8BitTo5Bit(scriptPubKey.sublist(2));
  // calculate checksum
  final checksum = _bech32Checksum(hrpExpanded, bech32Version, witnessProgram);
  // combine all parts
  final bech32Parts = <int>[bech32Version, ...witnessProgram, ...checksum];
  // convert to bech32 string
  final bech32String = StringBuffer(hrp);
  bech32String.write('1'); // separator
  for (var i = 0; i < bech32Parts.length; i++) {
    bech32String.write(_alphabet[bech32Parts[i]]);
  }
  return bech32String.toString();
}

Bech32 bech32Decode(String input) {
  // split input into human readable part (hrp) and data part
  final oneIndex = input.lastIndexOf('1');
  if (oneIndex == -1) {
    throw ArgumentError('Invalid Bech32 input: $input');
  }
  if (oneIndex == 0 || oneIndex == input.length - 1) {
    throw ArgumentError('Invalid Bech32 input: $input');
  }
  final hrp = input.substring(0, oneIndex);
  final data = input.substring(oneIndex + 1);
  // get the network based on hrp
  final network = switch (hrp) {
    'bc' => Network.mainnet,
    'tb' => Network.testnet,
    _ => throw ArgumentError(
      'Invalid or unsupported Bech32 human readable part: $hrp',
    ),
  };
  // expand hrp to 5-bit groups
  final hrpExpanded = _hrpExpand(hrp);
  // convert data to 5-bit values
  final data5Bit = Uint8List(data.length);
  for (var i = 0; i < data.length; i++) {
    final index = _alphabet.indexOf(data[i]);
    if (index == -1) {
      throw ArgumentError('Invalid character in Bech32 input: ${data[i]}');
    }
    data5Bit[i] = index;
  }
  // extract version, witness program, and checksum
  if (data5Bit.length < 7) {
    throw ArgumentError('Bech32 input too short: $input');
  }
  final version = data5Bit[0];
  if (version < 0 || version > 16) {
    throw ArgumentError('Invalid Bech32 version: $version');
  }
  final witnessProgram5Bit = data5Bit.sublist(1, data5Bit.length - 6);
  final checksum = data5Bit.sublist(data5Bit.length - 6);
  // verify checksum
  final calculatedChecksum = _bech32Checksum(
    hrpExpanded,
    version,
    witnessProgram5Bit,
  );
  for (var i = 0; i < 6; i++) {
    if (checksum[i] != calculatedChecksum[i]) {
      throw ArgumentError('Invalid Bech32 checksum: $input');
    }
  }
  // convert version to opcode value
  final opcode = version == 0 ? 0 : version + 0x50;
  // convert witness program back to 8-bit values
  final witnessProgram8Bit = _convert5BitTo8Bit(witnessProgram5Bit);
  // check witness program length
  if (version == 0 &&
      witnessProgram8Bit.length != 20 &&
      witnessProgram8Bit.length != 32) {
    throw ArgumentError(
      'Invalid witness program length: ${witnessProgram8Bit.length}',
    );
  }
  if (version == 1 && witnessProgram8Bit.length != 32) {
    throw ArgumentError(
      'Invalid witness program length: ${witnessProgram8Bit.length}',
    );
  }
  // combine version, witness program length, and witness program
  final scriptPubKey = Uint8List.fromList([
    opcode,
    witnessProgram8Bit.length,
    ...witnessProgram8Bit,
  ]);
  return Bech32(scriptPubKey, network);
}
