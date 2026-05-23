import 'dart:io';

import 'block_filter.dart';
import 'common.dart';
import 'node.dart';
import 'chain_store_file.dart';
import 'wallet.dart';

class NodeNative extends Node {
  final String dataDir;

  NodeNative({
    required super.network,
    String? dataDir,
    super.verbose,
    super.syncBlockHeaders,
    super.syncBlockFilterHeaders,
    super.wallet,
    required super.txProvider,
  }) : dataDir = _resolveDataDir(network, dataDir),
       super(
         blockHeadersChainStore: ChainStoreFile(
           '${_resolveDataDir(network, dataDir)}/$_headers',
         ),
         blockFilterHeadersChainStore: ChainStoreFile(
           '${_resolveDataDir(network, dataDir)}/$_filterHeaders',
         ),
         blockFiltersChainStore: ChainStoreFile(
           '${_resolveDataDir(network, dataDir)}/$_filters',
         ),
         blockStore: BlockStoreFile(
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

Node _defaultNodeNativeFactory({
  required Network network,
  String? storageLocation,
  bool verbose = false,
  bool syncBlockHeaders = true,
  bool syncBlockFilterHeaders = true,
  Wallet? wallet,
  required TxProvider txProvider,
}) => NodeNative(
  network: network,
  dataDir: storageLocation,
  verbose: verbose,
  syncBlockHeaders: syncBlockHeaders,
  syncBlockFilterHeaders: syncBlockFilterHeaders,
  wallet: wallet,
  txProvider: txProvider,
);

/// The file-system-backed [NodeFactory] for native platforms.
const NodeFactory defaultNodeFactory = _defaultNodeNativeFactory;
