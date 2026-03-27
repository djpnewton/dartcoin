import 'dart:typed_data';

import 'package:universal_web/web.dart';

import 'package:dartcoin/dartcoin.dart';
import 'package:dartcoin/web.dart';

late IDBDatabase db;
late BlockStoreWeb bs;

Future<bool> storageInit() async {
  db = await openDatabase('dartcoin_chain_store', objectStoreNames: ['blocks']);
  bs = BlockStoreWeb(db, 'blocks');
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

String storageBackendName() => 'IndexedDB (browser)';
