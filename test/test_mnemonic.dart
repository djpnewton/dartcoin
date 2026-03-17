// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:bip39/bip39.dart' as bip39;

import '../lib/src/mnemonic.dart';
import '../lib/src/utils.dart';

void main() {
  late Uint8List entropy;
  setUp(() {
    entropy = randomBits(128);
  });
  tearDown(() {});
  test('create mnemonic', () {
    final mnemonic = mnemonicFromEntropy(entropy);
    expect(mnemonic.isNotEmpty, isTrue);
    expect(mnemonic.split(' ').length, equals(12));
    expect(mnemonic, equals(bip39.entropyToMnemonic(bytesToHex(entropy))));
  });
  test('create mnemonic from too small entropy', () {
    final smallEntropy = randomBits(64);
    expect(() => mnemonicFromEntropy(smallEntropy), throwsArgumentError);
  });
  test('create mnemonic from large entropy', () {
    final largeEntropy = randomBits(256);
    final mnemonic = mnemonicFromEntropy(largeEntropy);
    expect(mnemonic.isNotEmpty, isTrue);
    expect(mnemonic.split(' ').length, equals(24));
    expect(mnemonic, equals(bip39.entropyToMnemonic(bytesToHex(largeEntropy))));
  });
  test('create mnemonic from too large entropy', () {
    final largeEntropy = randomBits(512);
    expect(() => mnemonicFromEntropy(largeEntropy), throwsArgumentError);
  });
  test('create mnemonic from invalid entropy length', () {
    final entropy = randomBits(264);
    expect(() => mnemonicFromEntropy(entropy), throwsArgumentError);
  });
  test('mnemonic valid', () {
    final mnemonic = mnemonicFromEntropy(entropy);
    expect(mnemonicValid(mnemonic), isTrue);
  });
  test('mnemonic invalid', () {
    final mnemonic = 'this is an invalid mnemonic';
    expect(mnemonicValid(mnemonic), isFalse);
  });
  test('mnemonic to seed', () {
    final mnemonic = mnemonicFromEntropy(entropy);
    final seed = mnemonicToSeed(mnemonic);
    expect(seed.isNotEmpty, isTrue);
    expect(seed.length, equals(128)); // 512 bits
    expect(seed, equals(bip39.mnemonicToSeedHex(mnemonic)));
  });
  test('mnemonic to seed 2', () {
    expect(
      mnemonicToSeed(
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
      ),
      '5eb00bbddcf069084889a8ab9155568165f5c453ccb85e70811aaed6f6da5fc19a5ac40b389cd370d086206dec8aa6c43daea6690f20ad3d8d48b2d2ce9e38e4',
    );
  });
}
