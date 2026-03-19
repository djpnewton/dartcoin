// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:benchmark_runner/benchmark_runner.dart';
import 'package:http/http.dart' as http;

import '../lib/src/block.dart';

void main() async {
  late final Uint8List block899999Bytes;
  late final Uint8List block200000Bytes;
  group('block', () {
    asyncBenchmark(
      'parse mainnet block 899999 (633 txs)',
      () async {
        Block.fromBytes(block899999Bytes, lazy: false);
      },
      setup: () async {
        final url =
            'https://mempool.space/api/block/0000000000000000000196400396be46d0816dc462df4c3450972f589f4d7d24/raw';
        final resp = await http.get(Uri.parse(url));
        assert(resp.statusCode == 200);
        block899999Bytes = resp.bodyBytes;
      },
      sampleSize: SampleSize(length: 5),
    );
    asyncBenchmark(
      'parse mainnet block 200000 (388 txs)',
      () async {
        Block.fromBytes(block200000Bytes, lazy: false);
      },
      setup: () async {
        final url =
            'https://mempool.space/api/block/000000000000034a7dedef4a161fa058a2d67a173a90155f3a2fe6fc132e0ebf/raw';
        final resp = await http.get(Uri.parse(url));
        assert(resp.statusCode == 200);
        block200000Bytes = resp.bodyBytes;
      },
      sampleSize: SampleSize(length: 5),
    );
  });
}
