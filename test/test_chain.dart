// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/block_filter.dart';
import '../lib/src/chain.dart';
import '../lib/src/chain_store.dart';
import '../lib/src/common.dart';
import '../lib/src/transaction.dart';

// ---------------------------------------------------------------------------
// Minimal in-memory ChainStore for unit tests.
// ---------------------------------------------------------------------------

class _MemChainStore implements ChainStore {
  String _data = '';

  @override
  Future<void> init() async {}

  @override
  Future<bool> exists() async => _data.isNotEmpty;

  @override
  Future<bool> empty() async => _data.isEmpty;

  @override
  Future<void> delete() async => _data = '';

  @override
  Future<List<String>> readLines() async => _data.isEmpty
      ? []
      : _data.split('\n').where((l) => l.isNotEmpty).toList();

  @override
  Future<String?> lastLine() async {
    final lines = await readLines();
    return lines.isEmpty ? null : lines.last;
  }

  @override
  Future<void> writeAll(String content) async {
    if (_data.isNotEmpty) throw StateError('Store already has data');
    _data = content;
  }

  @override
  Future<void> append(String content) async => _data += content;
}

class _NullTxProvider implements TxProvider {
  @override
  Future<Transaction> fromTxid(String txid) =>
      throw UnimplementedError('Not needed for filter-header tests');
}

Future<ChainManager> _makeChainManager() async {
  final m = ChainManager(
    network: Network.testnet4,
    blockHeadersChainStore: _MemChainStore(),
    blockFilterHeadersChainStore: _MemChainStore(),
    blockFiltersChainStore: _MemChainStore(),
    txProvider: _NullTxProvider(),
  );
  await m.init();
  return m;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('addBlockFilterHeaders - genesis height-0 handling', () {
    // ----- normal path ---------------------------------------------------- //

    test(
      'succeeds when previousFilterHash matches genesis at height 0',
      () async {
        final m = await _makeChainManager();
        final genesis = m.bestBlockFilterHead.header;

        final result = await m.addBlockFilterHeaders(
          genesis,
          [Uint8List(32)], // one dummy filter hash
          Uint8List(32), // dummy stop hash
        );

        expect(result, AddBlockFilterHeadersResult.success);
        expect(m.bestBlockFilterHead.height, 1);
      },
    );

    // ----- stale path (genuinely pre-reset response) ---------------------- //

    test(
      'returns staleBlockFilterHeader when previousFilterHash is not genesis '
      'at height 0',
      () async {
        final m = await _makeChainManager();
        // All-zeros is definitely not the real genesis filter header.
        final nonGenesis = Uint8List(32);

        final result = await m.addBlockFilterHeaders(
          nonGenesis,
          [],
          Uint8List(32),
        );

        expect(result, AddBlockFilterHeadersResult.staleBlockFilterHeader);
        expect(
          m.bestBlockFilterHead.height,
          0,
          reason: 'chain must not advance',
        );
      },
    );

    // ----- repair path (race-condition corruption) ------------------------ //
    //
    // The race: resetBlockFilterHeaderChain() sets _bestBlockFilterHead to
    // genesis *synchronously*, but then yields at an IDB await.  While
    // suspended, the 1-second retry timer fires, sends a new GetCfHeaders,
    // and a concurrent addBlockFilterHeaders() call succeeds, advancing
    // _bestBlockFilterHead beyond genesis.  When resetBlockFilterHeaderChain()
    // resumes it no longer touches _bestBlockFilterHead, so the field stays
    // at height N>0.  A subsequent reset call may bring height back to 0 but
    // with a freshly-allocated entry whose header is whatever the race left
    // behind.  The fix: at height 0, fall back to comparing against the
    // canonical _genesisBlockFilterHeader and repair the head on a match.

    test('repairs corrupted genesis head and succeeds when previousFilterHash '
        'matches canonical genesis', () async {
      final m = await _makeChainManager();
      final genesis = m.bestBlockFilterHead.header;

      // Manufacture the corrupted state: height 0, but header is not genesis.
      m.bestBlockFilterHeadForTesting = BlockFilterHeaderEntry(
        height: 0,
        header: Uint8List(32), // all-zeros ≠ real genesis filter header
      );
      expect(m.bestBlockFilterHead.height, 0);

      // addBlockFilterHeaders with the CORRECT genesis previousFilterHash
      // should detect the mismatch, repair, and process the batch.
      final result = await m.addBlockFilterHeaders(
        genesis,
        [Uint8List(32)], // one dummy filter hash
        Uint8List(32),
      );

      expect(result, AddBlockFilterHeadersResult.success);
      expect(m.bestBlockFilterHead.height, 1);
    });

    test('returns staleBlockFilterHeader when head is corrupted AND '
        'previousFilterHash is also not genesis', () async {
      final m = await _makeChainManager();

      // Corrupt the head.
      m.bestBlockFilterHeadForTesting = BlockFilterHeaderEntry(
        height: 0,
        header: Uint8List(32),
      );
      // Use a previousFilterHash that is neither the corrupted head NOR genesis.
      final unrelated = Uint8List.fromList(List.generate(32, (i) => i + 1));

      final result = await m.addBlockFilterHeaders(
        unrelated,
        [],
        Uint8List(32),
      );

      expect(result, AddBlockFilterHeadersResult.staleBlockFilterHeader);
    });

    // ----- stale / invalid at height > 0 ---------------------------------- //

    test(
      'returns staleBlockFilterHeader for duplicate genesis previousFilterHash '
      'when chain has already advanced beyond genesis',
      () async {
        final m = await _makeChainManager();
        final genesis = m.bestBlockFilterHead.header;

        // Advance chain to height 1.
        await m.addBlockFilterHeaders(genesis, [Uint8List(32)], Uint8List(32));
        expect(m.bestBlockFilterHead.height, 1);

        // Old duplicate response: previousFilterHash = genesis (already processed).
        final result = await m.addBlockFilterHeaders(genesis, [
          Uint8List(32),
        ], Uint8List(32));

        expect(result, AddBlockFilterHeadersResult.staleBlockFilterHeader);
      },
    );

    test('returns invalidBlockFilterHeader for completely unknown '
        'previousFilterHash when chain is at height > 0', () async {
      final m = await _makeChainManager();
      final genesis = m.bestBlockFilterHead.header;

      // Advance chain to height 1.
      await m.addBlockFilterHeaders(genesis, [Uint8List(32)], Uint8List(32));

      // Unknown previousFilterHash: not in the index, not genesis.
      final unknown = Uint8List.fromList(List.generate(32, (i) => i + 100));

      final result = await m.addBlockFilterHeaders(unknown, [], Uint8List(32));

      expect(result, AddBlockFilterHeadersResult.invalidBlockFilterHeader);
    });
  });
}
