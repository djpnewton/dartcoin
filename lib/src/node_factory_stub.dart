import 'block_filter.dart';
import 'common.dart';
import 'node.dart';
import 'wallet.dart';

Node _unsupportedNodeFactory({
  required Network network,
  String? storageLocation,
  bool verbose = false,
  bool syncBlockHeaders = true,
  bool syncBlockFilterHeaders = true,
  Wallet? wallet,
  required TxProvider txProvider,
}) => throw UnsupportedError(
  'No NodeFactory implementation for this platform. '
  'Ensure you are running on a supported platform (native or web).',
);

/// Stub [NodeFactory] — always throws [UnsupportedError].
const NodeFactory defaultNodeFactory = _unsupportedNodeFactory;
