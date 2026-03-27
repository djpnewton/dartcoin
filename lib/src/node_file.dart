import 'dart:io';

import 'common.dart';
import 'node.dart';
import 'chain_store_file.dart';

class NodeFileStorage extends Node {
  final String dataDir;

  NodeFileStorage({
    required super.network,
    String? dataDir,
    super.verbose,
    super.syncBlockHeaders,
    super.syncBlockFilterHeaders,
    super.wallet,
    required super.txProvider,
  }) : dataDir = _resolveDataDir(network, dataDir),
       super(
         blockHeadersChainStore: FileChainStore(
           '${_resolveDataDir(network, dataDir)}/$_headers',
         ),
         blockFilterHeadersChainStore: FileChainStore(
           '${_resolveDataDir(network, dataDir)}/$_filterHeaders',
         ),
         blockFiltersChainStore: FileChainStore(
           '${_resolveDataDir(network, dataDir)}/$_filters',
         ),
         blockStore: FileBlockStore(
           _resolveDataDir(network, dataDir),
           verbose: verbose,
         ),
       );

  static const _headers = 'headers.csv';
  static const _filterHeaders = 'filter_headers.csv';
  static const _filters = 'filters.csv';

  String get blockHeadersFilePath => '$dataDir/$_headers';
  String get blockFilterHeadersFilePath => '$dataDir/$_filterHeaders';
  String get blockFiltersFilePath => '$dataDir/$_filters';

  static String _resolveDataDir(Network network, String? dataDir) {
    if (dataDir != null) {
      Directory(dataDir).createSync(recursive: true);
      return dataDir;
    }
    final dirName = switch (network) {
      Network.mainnet => '.dartcoin/mainnet',
      Network.testnet => '.dartcoin/testnet',
      Network.testnet4 => '.dartcoin/testnet4',
      Network.regtest => '.dartcoin/regtest',
    };
    final resolved = './$dirName';
    Directory(resolved).createSync(recursive: true);
    return resolved;
  }
}
