// ignore_for_file: avoid_relative_lib_imports

import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/sign_verify.dart';
import '../lib/src/keys.dart';
import '../lib/src/mnemonic.dart';
import '../lib/src/utils.dart';
import '../lib/src/common.dart';
import 'vectors/ecdsa_vectors.dart' as ecdsa_vectors;

void main() {
  late String seed;
  late PrivateKey masterKey;
  setUp(() {
    seed = mnemonicToSeed(
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    );
    masterKey = PrivateKey.fromSeed(hexToBytes(seed));
  });

  test('bitcoinSignedMessageSign()', () {
    final msg = utf8.encode('hello world');
    var bsn = bitcoinSignedMessageSign(
      masterKey,
      msg,
      Network.mainnet,
      ScriptType.p2pkh,
    );
    expect(bsn.address, equals('1BZ9j3F7m4H1RPyeDp5iFwpR31SB6zrs19'));
    expect(
      bsn.signature,
      equals(
        'IEGvUEFY6r1d/r4fsJFOLH3PxGItn3D4mWBwcEIbM3bYIJ5PAWAx5xkXEVwwpfD3pIw3gXDsQ78nld5imvsx4FA=',
      ),
    );
    bsn = bitcoinSignedMessageSign(
      masterKey,
      msg,
      Network.mainnet,
      ScriptType.p2shP2wpkh,
    );
    expect(bsn.address, equals('3P2wVKudAzGpduyUZe8amduQpqSiSKEQzk'));
    expect(
      bsn.signature,
      equals(
        'JEGvUEFY6r1d/r4fsJFOLH3PxGItn3D4mWBwcEIbM3bYIJ5PAWAx5xkXEVwwpfD3pIw3gXDsQ78nld5imvsx4FA=',
      ),
    );
    bsn = bitcoinSignedMessageSign(
      masterKey,
      msg,
      Network.mainnet,
      ScriptType.p2wpkh,
    );
    expect(bsn.address, equals('bc1qw0za5zsr6tggqwmnruzzg2a5pnkjlzaus8upyg'));
    expect(
      bsn.signature,
      equals(
        'KEGvUEFY6r1d/r4fsJFOLH3PxGItn3D4mWBwcEIbM3bYIJ5PAWAx5xkXEVwwpfD3pIw3gXDsQ78nld5imvsx4FA=',
      ),
    );
  });
  test('bitcoinSignedMessageVerify()', () {
    final msg = utf8.encode('hello world');
    expect(
      bitcoinSignedMessageVerify(
        '1BZ9j3F7m4H1RPyeDp5iFwpR31SB6zrs19',
        msg,
        'IEGvUEFY6r1d/r4fsJFOLH3PxGItn3D4mWBwcEIbM3bYIJ5PAWAx5xkXEVwwpfD3pIw3gXDsQ78nld5imvsx4FA=',
      ),
      isTrue,
    );
    expect(
      bitcoinSignedMessageVerify(
        '3P2wVKudAzGpduyUZe8amduQpqSiSKEQzk',
        msg,
        'JEGvUEFY6r1d/r4fsJFOLH3PxGItn3D4mWBwcEIbM3bYIJ5PAWAx5xkXEVwwpfD3pIw3gXDsQ78nld5imvsx4FA=',
      ),
      isTrue,
    );
    expect(
      bitcoinSignedMessageVerify(
        'bc1qw0za5zsr6tggqwmnruzzg2a5pnkjlzaus8upyg',
        msg,
        'KEGvUEFY6r1d/r4fsJFOLH3PxGItn3D4mWBwcEIbM3bYIJ5PAWAx5xkXEVwwpfD3pIw3gXDsQ78nld5imvsx4FA=',
      ),
      isTrue,
    );
  });
  test('derSign()', () {
    var msg = utf8.encode('hello world');
    var der = derSignMessage(masterKey, msg);
    expect(
      der.signature,
      equals(
        hexToBytes(
          '3045022100866b281b99f14fd6d45697cdbc2429f86da140b4dee7f39fa2056e087e2fb4ae022000fc4ce1e6d2ea8f7d2b13a9b26acce7649c16657789f3d51db9b4d8b81efb31',
        ),
      ),
    );
    msg = utf8.encode('the quick brown fox jumps over the lazy dog');
    der = derSignMessage(masterKey, msg);
    expect(
      der.signature,
      equals(
        hexToBytes(
          '30450221008743e45ed8d942a04d34701d80ca2a05a790f8d6d1b8c49a6a5b73de707922d002206642245fb1cb1b62b55d35d215e6f9d3aed7798b3db6f02572e4327e7a76a4f5',
        ),
      ),
    );
    msg = utf8.encode(
      'Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.',
    );
    der = derSignMessage(masterKey, msg);
    expect(
      der.signature,
      equals(
        hexToBytes(
          '3045022100a7d80c086392bc972d82845995199759dbcf4c24f1ceca3baf6350648a6d618e02206b9c6884065fa1a04622166f35f914ffcd8a4db446f2fbcd661a2cc11fa93fbf',
        ),
      ),
    );
  });
  test('derVerify()', () {
    var msg = utf8.encode('hello world');
    var publicKey = hexToBytes(
      '03d902f35f560e0470c63313c7369168d9d7df2d49bf295fd9fb7cb109ccee0494',
    );
    var derSignature = hexToBytes(
      '3045022100866b281b99f14fd6d45697cdbc2429f86da140b4dee7f39fa2056e087e2fb4ae022000fc4ce1e6d2ea8f7d2b13a9b26acce7649c16657789f3d51db9b4d8b81efb31',
    );
    expect(
      derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, derSignature),
      isTrue,
    );
    // test with wrong message
    var msgWrong = utf8.encode('hello world!');
    expect(
      derVerifyMessage(PublicKey.fromPublicKey(publicKey), msgWrong, derSignature),
      isFalse,
    );
    // test with wrong signature
    var wrongSignature = Uint8List.fromList(
      derSignature.sublist(0, derSignature.length - 1) + [0x00],
    );
    expect(
      derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, wrongSignature),
      isFalse,
    );
    // test with wrong public key
    final wrongPublicKey = Uint8List.fromList(
      publicKey.sublist(0, publicKey.length - 1) + [0x00],
    );
    expect(
      derVerifyMessage(PublicKey.fromPublicKey(wrongPublicKey), msg, derSignature),
      isFalse,
    );
    //
    // Example DER signature:
    // 3045022100866b281b99f14fd6d45697cdbc2429f86da140b4dee7f39fa2056e087e2fb4ae022000fc4ce1e6d2ea8f7d2b13a9b26acce7649c16657789f3d51db9b4d8b81efb31
    //
    final prefix = 0x30;
    final length = 0x45; // 69 bytes
    final rPrefix = 0x02;
    final rLength = 0x21; // 33 bytes
    final rValue = hexToBytes(
      '00866b281b99f14fd6d45697cdbc2429f86da140b4dee7f39fa2056e087e2fb4ae',
    );
    final sPrefix = 0x02;
    final sLength = 0x20; // 32 bytes
    final sValue = hexToBytes(
      '00fc4ce1e6d2ea8f7d2b13a9b26acce7649c16657789f3d51db9b4d8b81efb31',
    );
    // DER signature with wrong length
    wrongSignature = Uint8List.fromList(
      derSignature.sublist(0, derSignature.length - 1),
    );
    expect(
      () => derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, wrongSignature),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message == 'Invalid DER signature length',
        ),
      ),
    );
    // DER signature with wrong prefix
    wrongSignature = Uint8List.fromList(
      [0x31, length] + derSignature.sublist(2),
    );
    expect(
      () => derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, wrongSignature),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message == 'Invalid DER signature format',
        ),
      ),
    );
    // DER signature with wrong r prefix
    wrongSignature = Uint8List.fromList(
      [prefix, length, 0x03, rLength] + derSignature.sublist(4),
    );
    expect(
      () => derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, wrongSignature),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message == 'Invalid DER signature r value',
        ),
      ),
    );
    // DER signature with wrong r length
    wrongSignature = Uint8List.fromList(
      [prefix, length, rPrefix, 0x22] + derSignature.sublist(4),
    );
    expect(
      () => derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, wrongSignature),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message == 'Invalid DER signature r length',
        ),
      ),
    );
    // DER signature with wrong s prefix
    wrongSignature = Uint8List.fromList(
      [prefix, length, rPrefix, rLength, ...rValue] +
          [0x03] +
          derSignature.sublist(4 + rLength + 1),
    );
    expect(
      () => derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, wrongSignature),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message == 'Invalid DER signature s value',
        ),
      ),
    );
    // DER signature with wrong s length
    wrongSignature = Uint8List.fromList(
      [prefix, length, rPrefix, rLength, ...rValue] +
          [sPrefix, 0x21, ...sValue],
    );
    expect(
      () => derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, wrongSignature),
      throwsA(
        predicate(
          (e) =>
              e is FormatException &&
              e.message == 'Invalid DER signature s length',
        ),
      ),
    );
    // put the parts together correctly
    final correctSignature = Uint8List.fromList([
      prefix,
      length,
      rPrefix,
      rLength,
      ...rValue,
      sPrefix,
      sLength,
      ...sValue,
    ]);
    expect(
      derVerifyMessage(PublicKey.fromPublicKey(publicKey), msg, correctSignature),
      isTrue,
    );
  });
  test('derSign() ecdsa small key vectors', () {
    for (final v in ecdsa_vectors.smallKeys) {
      final masterKey = PrivateKey.fromPrivateKey(
        bigIntToBytes(v.privateKey, minLength: 32),
      );
      final msg = utf8.encode(v.message);
      final der = derSignMessage(masterKey, msg);
      expect(
        der.signature,
        equals(v.sigDERDeterministic),
        reason: 'Failed for key: ${v.privateKey}, message: ${v.message}',
      );
    }
  });
  test('derSign() ecdsa large key vectors', () {
    for (final v in ecdsa_vectors.largeKeys) {
      final masterKey = PrivateKey.fromPrivateKey(
        bigIntToBytes(v.privateKey, minLength: 32),
      );
      final msg = utf8.encode(v.message);
      final der = derSignMessage(masterKey, msg);
      expect(
        der.signature,
        equals(v.sigDERDeterministic),
        reason: 'Failed for key: ${v.privateKey}, message: ${v.message}',
      );
    }
  });
}
