// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:benchmark_runner/benchmark_runner.dart';

import '../lib/src/ripemd160.dart';
import '../lib/src/sha256.dart';
import '../lib/src/sha512.dart';

void main() {
  group('Ripemd160', () {
    var data = Uint8List.fromList(List.generate(1000, (index) => index % 256));
    benchmark('1000 bytes values 0->255', () {
      ripemd160(data);
    });
    data = Uint8List.fromList(List.filled(1000, 0));
    benchmark('1000 bytes all zeros', () {
      ripemd160(data);
    });
    data = Uint8List.fromList(List.filled(1000, 255));
    benchmark('1000 bytes all 255', () {
      ripemd160(data);
    });
  });
  group('Sha256', () {
    var data = Uint8List.fromList(List.generate(1000, (index) => index % 256));
    benchmark('1000 bytes values 0->255', () {
      sha256(data);
    });
    data = Uint8List.fromList(List.filled(1000, 0));
    benchmark('1000 bytes all zeros', () {
      sha256(data);
    });
    data = Uint8List.fromList(List.filled(1000, 255));
    benchmark('1000 bytes all 255', () {
      sha256(data);
    });
  });
  group('Sha512', () {
    var data = Uint8List.fromList(List.generate(1000, (index) => index % 256));
    benchmark('1000 bytes values 0->255', () {
      sha512(data);
    });
    data = Uint8List.fromList(List.filled(1000, 0));
    benchmark('1000 bytes all zeros', () {
      sha512(data);
    });
    data = Uint8List.fromList(List.filled(1000, 255));
    benchmark('1000 bytes all 255', () {
      sha512(data);
    });
  });
}
