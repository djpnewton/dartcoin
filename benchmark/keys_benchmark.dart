// ignore_for_file: avoid_relative_lib_imports

import 'package:benchmark_runner/benchmark_runner.dart';

import '../lib/src/utils.dart';
import '../lib/src/secp256k1.dart';
import '../lib/src/keys.dart';

void main() {
  group('secp256k1', () {
    benchmark('multiply generator by 0xffff', () {
      Secp256k1Point.generator.multiply(BigInt.from(0xffff));
    });
    benchmark('multiply generator by N', () {
      Secp256k1Point.generator.multiply(Secp256k1Point.n);
    });
  });
  group('keys', () {
    var privateKey = hexToBytes(
      'ff00000000000000000000000000000000000000000000000000000000000000',
    );
    benchmark('public key from "ff0000.."', () {
      PrivateKey.pubkeyFromPrivateKey(privateKey);
    });
    privateKey = hexToBytes(
      '00000000000000000000000000000000000000000000000000000000000000ff',
    );
    benchmark('public key from "..0000ff"', () {
      PrivateKey.pubkeyFromPrivateKey(privateKey);
    });
    privateKey = hexToBytes(
      'dfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
    );
    benchmark('public key from "dfffff.."', () {
      PrivateKey.pubkeyFromPrivateKey(privateKey);
    });
  });
}
