import 'package:sqlite3/sqlite3.dart';
import 'package:dartcoin/dartcoin.dart';

import 'chain_store_sqlite.dart';

class NodeSqliteStorage extends Node {
  /// The underlying SQLite database.  Close this when the node is shut down.
  final Database db;

  factory NodeSqliteStorage({
    required Network network,
    required String dbFilename,
    bool verbose = false,
    bool syncBlockHeaders = true,
    bool syncBlockFilterHeaders = true,
    Wallet? wallet,
    required TxProvider txProvider,
  }) {
    final db = sqlite3.open(dbFilename);
    return NodeSqliteStorage._internal(
      network: network,
      db: db,
      verbose: verbose,
      syncBlockHeaders: syncBlockHeaders,
      syncBlockFilterHeaders: syncBlockFilterHeaders,
      wallet: wallet,
      txProvider: txProvider,
    );
  }

  NodeSqliteStorage._internal({
    required super.network,
    required this.db,
    super.verbose,
    super.syncBlockHeaders,
    super.syncBlockFilterHeaders,
    super.wallet,
    required super.txProvider,
  }) : super(
         blockHeadersChainStore: ChainStoreSqlite(
           db,
           '${network.name}_headers',
         ),
         blockFilterHeadersChainStore: ChainStoreSqlite(
           db,
           '${network.name}_filter_headers',
         ),
         blockFiltersChainStore: ChainStoreSqlite(
           db,
           '${network.name}_filters',
         ),
         blockStore: BlockStoreSqlite(db, '${network.name}_blocks'),
       );
}
