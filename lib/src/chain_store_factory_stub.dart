import 'chain_store.dart';

ChainStore _unsupportedChainStoreFactory(String name) => throw UnsupportedError(
  'No ChainStoreFactory implementation for this platform. '
  'Ensure you are running on a supported platform (native or web).',
);

BlockStore _unsupportedBlockStoreFactory(String name, {bool verbose = false}) =>
    throw UnsupportedError(
      'No BlockStoreFactory implementation for this platform. '
      'Ensure you are running on a supported platform (native or web).',
    );

/// Stub [ChainStoreFactory] — always throws [UnsupportedError].
const ChainStoreFactory defaultChainStoreFactory =
    _unsupportedChainStoreFactory;

/// Stub [BlockStoreFactory] — always throws [UnsupportedError].
const BlockStoreFactory defaultBlockStoreFactory =
    _unsupportedBlockStoreFactory;
