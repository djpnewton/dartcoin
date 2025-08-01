// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/siphash.dart';
import '../lib/src/utils.dart';

void main() {
  test('invalid input', () {
    // key length too short
    expect(
      () => siphashBytes(utf8.encode(''), utf8.encode('123456789012345')),
      throwsArgumentError,
    );
    // key length too long
    expect(
      () => siphashBytes(utf8.encode(''), utf8.encode('12345678901234567')),
      throwsArgumentError,
    );
  });
  test('values from https://github.com/majek/pysiphash', () {
    final key = '1234567890123456';
    expect(
      siphashBytes(utf8.encode(''), utf8.encode(key)),
      equals(hexToBytes('7f32f18a1dc235af')),
    );
    expect(
      siphashBytes(utf8.encode('hello'), utf8.encode(key)),
      equals(hexToBytes('0f2d12c3c33d66f2')),
    );
    expect(
      siphashBytes(utf8.encode('hello world'), utf8.encode(key)),
      equals(hexToBytes('4a38c614b08e451f')),
    );
    expect(
      siphashBytes(
        utf8.encode('the quick brown fox jumped over the lazy dog'),
        utf8.encode(key),
      ),
      equals(hexToBytes('4f7126ca7b9e48f7')),
    );
  });
  test('test vectors', () {
    // dart format off
    final testVectors = [
      "310e0edd47db6f72", "fd67dc93c539f874", "5a4fa9d909806c0d", "2d7efbd796666785",
      "b7877127e09427cf", "8da699cd64557618", "cee3fe586e46c9cb", "37d1018bf50002ab",
      "6224939a79f5f593", "b0e4a90bdf82009e", "f3b9dd94c5bb5d7a", "a7ad6b22462fb3f4",
      "fbe50e86bc8f1e75", "903d84c02756ea14", "eef27a8e90ca23f7", "e545be4961ca29a1",
      "db9bc2577fcc2a3f", "9447be2cf5e99a69", "9cd38d96f0b3c14b", "bd6179a71dc96dbb",
      "98eea21af25cd6be", "c7673b2eb0cbf2d0", "883ea3e395675393", "c8ce5ccd8c030ca8",
      "94af49f6c650adb8", "eab8858ade92e1bc", "f315bb5bb835d817", "adcf6b0763612e2f",
      "a5c91da7acaa4dde", "716595876650a2a6", "28ef495c53a387ad", "42c341d8fa92d832",
      "ce7cf2722f512771", "e37859f94623f3a7", "381205bb1ab0e012", "ae97a10fd434e015",
      "b4a31508beff4d31", "81396229f0907902", "4d0cf49ee5d4dcca", "5c73336a76d8bf9a",
      "d0a704536ba93e0e", "925958fcd6420cad", "a915c29bc8067318", "952b79f3bc0aa6d4",
      "f21df2e41d4535f9", "87577519048f53a9", "10a56cf5dfcd9adb", "eb75095ccd986cd0",
      "51a9cb9ecba312e6", "96afadfc2ce666c7", "72fe52975a4364ee", "5a1645b276d592a1",
      "b274cb8ebf87870a", "6f9bb4203de7b381", "eaecb2a30b22a87f", "9924a43cc1315724",
      "bd838d3aafbf8db7", "0b1a2a3265d51aea", "135079a3231ce660", "932b2846e4d70666",
      "e1915f5cb1eca46c", "f325965ca16d629f", "575ff28e60381be5", "724506eb4c328a95",
    ];
    // dart format on
    final key = Uint8List.fromList(List.generate(16, (i) => i));
    final input = Uint8List.fromList(
      List.generate(testVectors.length, (i) => i),
    );
    for (int i = 0; i < testVectors.length; i++) {
      final expected = hexToBytes(testVectors[i]);
      final result = siphashBytes(input.sublist(0, i), key);
      expect(result, equals(expected), reason: 'Failed on test vector $i');
    }
  });
}
