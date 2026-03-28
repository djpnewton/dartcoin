import 'dart:typed_data';

import 'package:dartcoin/dartcoin.dart';
import 'package:dartcoin/native.dart';

late BlockStoreFile bs;

Future<bool> storageInit() async {
  bs = BlockStoreFile('blocks', verbose: true);
  await bs.init();
  return true;
}

Future<bool> blockSave(Block block) async {
  await bs.store(block);
  return true;
}

Future<Block?> blockLoad(Uint8List blockHash) async {
  return await bs.read(blockHash);
}

String storageBackendName() => 'File (dart:io)';
