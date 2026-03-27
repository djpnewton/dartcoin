import 'dart:typed_data';

import 'package:dartcoin/dartcoin.dart';

Future<bool> storageInit() async {
  throw UnimplementedError(
    'BlockStore is not implemented for this platform.  Please use a platform-specific implementation.',
  );
}

Future<bool> blockSave(Block block) async {
  throw UnimplementedError(
    'BlockStore is not implemented for this platform.  Please use a platform-specific implementation.',
  );
}

Future<Block?> blockLoad(Uint8List blockHash) async {
  throw UnimplementedError(
    'BlockStore is not implemented for this platform.  Please use a platform-specific implementation.',
  );
}

String storageBackendName() => 'Unknown (stub)';
