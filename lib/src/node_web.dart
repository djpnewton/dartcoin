import 'block_filter.dart';
import 'chain_store_web.dart';
import 'common.dart';
import 'node.dart';
import 'wallet.dart';

/// [Node] subclass that stores data in IndexedDB, for use on web platforms.
///
/// Each logical data set (block headers, filter headers, filter data, blocks)
/// is stored in its own IDB database whose name is derived from
/// [storageLocation] and the [network]:
/// `<storageLocation>.<suffix>` where storageLocation defaults to
/// `dartcoin.<network-name>` when omitted.
class NodeWeb extends Node {
  NodeWeb({
    required super.network,
    String? storageLocation,
    super.verbose,
    super.syncBlockHeaders,
    super.syncBlockFilterHeaders,
    super.wallet,
    required super.txProvider,
  }) : super(
         blockHeadersChainStore: ChainStoreWebAuto(
           _dbName(network, storageLocation, 'headers'),
         ),
         blockFilterHeadersChainStore: ChainStoreWebAuto(
           _dbName(network, storageLocation, 'filterHeaders'),
         ),
         blockFiltersChainStore: ChainStoreWebAuto(
           _dbName(network, storageLocation, 'filters'),
         ),
         blockStore: BlockStoreWebAuto(
           _dbName(network, storageLocation, 'blocks'),
         ),
       );

  static String _dbName(Network network, String? prefix, String suffix) {
    final base = prefix ?? 'dartcoin.${network.name}';
    return '$base.$suffix';
  }
}

Node _defaultNodeWebFactory({
  required Network network,
  String? storageLocation,
  bool verbose = false,
  bool syncBlockHeaders = true,
  bool syncBlockFilterHeaders = true,
  Wallet? wallet,
  required TxProvider txProvider,
}) => NodeWeb(
  network: network,
  storageLocation: storageLocation,
  verbose: verbose,
  syncBlockHeaders: syncBlockHeaders,
  syncBlockFilterHeaders: syncBlockFilterHeaders,
  wallet: wallet,
  txProvider: txProvider,
);

/// The IndexedDB-backed [NodeFactory] for web platforms.
const NodeFactory defaultNodeFactory = _defaultNodeWebFactory;
