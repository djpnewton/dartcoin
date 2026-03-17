// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/block_filter.dart';
import '../lib/src/block.dart';
import '../lib/src/transaction.dart';
import '../lib/src/utils.dart';
import '../lib/src/common.dart';

import 'vectors/bip158_vectors.dart';

class TestTxProvider implements TxProvider {
  final Map<String, Transaction> _txMap;

  TestTxProvider(this._txMap);

  @override
  Future<Transaction> fromTxid(String txid) async {
    final tx = _txMap[txid];
    if (tx == null) {
      throw Exception(
        'Transaction with txid $txid not found in TestTxProvider',
      );
    }
    return tx;
  }
}

void main() {
  test('BlockDnTxProvider and prevOutputScripts', () async {
    final txProvider = BlockDnTxProvider(Network.testnet);
    for (var vector in bip158Vectors.skip(1)) {
      final blockHeight = vector[0] as int;
      final block = Block.fromBytes(hexToBytes(vector[2] as String));
      final prevOutputScripts = (vector[3] as List<String>)
          .map((script) => hexToBytes(script))
          .toList();

      final ourPrevOutputScripts = await BasicBlockFilter.prevOutputScripts(
        block,
        txProvider,
      );
      expect(
        ourPrevOutputScripts.length,
        equals(prevOutputScripts.length),
        reason:
            'Prev output scripts length mismatch for block at height $blockHeight',
      );
      for (int i = 0; i < prevOutputScripts.length; i++) {
        expect(
          ourPrevOutputScripts[i],
          equals(prevOutputScripts[i]),
          reason:
              'Prev output script mismatch at index $i for block at height $blockHeight',
        );
      }
    }
  });

  test('block filter creation', () async {
    // testnet4 genesis block (no transactions other than coinbase)
    final testnet4Genesis = Block.genesisBlock(Network.testnet4);
    final filterGenesis = BasicBlockFilter(
      block: testnet4Genesis,
      prevOutputScripts: [],
    );
    final headerGenesis = BasicBlockFilter.filterHeader(
      filterGenesis.filterHash,
      BasicBlockFilter.genesisPreviousHeader,
    );
    final headerGenesisNice = BasicBlockFilter.filterHeaderNice(headerGenesis);
    expect(filterGenesis.filterBytes, equals(hexToBytes('01976d88')));
    expect(
      headerGenesisNice,
      equals(
        ('0bf21f76e722983499fdf053df229813d79bad9e0dfd316ed3e89de2c4b7b2f1'),
      ),
    );
    final testnet4Block1 = Block.fromBytes(
      hexToBytes(
        '0000002043f08bdab050e35b567c864b91f47f50ae725ae2de53bcfbbaf284da000000005c78b286f0d46ba2b8b104b6f7aec904fa0e93259e5637aaaac87d59b89d9c6160d63866ffff001da680f8ad01010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff095100062f4077697a2fffffffff0200f2052a010000001976a9140a59837ccd4df25adc31cdad39be6a8d97557ed688ac0000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000',
      ),
    );

    // testnet4 block 1 (only coinbase transaction)
    final filter1 = BasicBlockFilter(
      block: testnet4Block1,
      prevOutputScripts: [],
    );
    final header1 = BasicBlockFilter.filterHeader(
      filter1.filterHash,
      headerGenesis,
    );
    final header1Nice = BasicBlockFilter.filterHeaderNice(header1);
    expect(filter1.filterBytes, equals(hexToBytes('016c4360')));
    expect(
      header1Nice,
      equals(
        ('c77b9ff60dd4ffaa4beac174aff174c3686b3ea3ff5ab2b59a38975699fede14'),
      ),
    );
    final testnet4Block2 = Block.fromBytes(
      hexToBytes(
        '00000020283fb111e32c10bbfa2a9c66df8499900e886b282912625f6d2b981200000000499bbf7eabfd52fac213d9cb21e903ab423ef6eaae7f29d03583c025ec19daa16ed63866ffff001d5c3f591001010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff095200062f4077697a2fffffffff0200f2052a010000001976a9140a59837ccd4df25adc31cdad39be6a8d97557ed688ac0000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000',
      ),
    );
    final filter2 = BasicBlockFilter(
      block: testnet4Block2,
      prevOutputScripts: [],
    );
    final header2 = BasicBlockFilter.filterHeader(filter2.filterHash, header1);
    final header2Nice = BasicBlockFilter.filterHeaderNice(header2);
    expect(filter2.filterBytes, equals(hexToBytes('01810818')));
    expect(
      header2Nice,
      equals(
        ('646af0c2f729e376f1590dedda6298207d09b6870c4be42555a37cde6880817f'),
      ),
    );

    // testnet4 block 2067 (with a non-coinbase transaction)
    final header2066 = Uint8List.fromList(
      hexToBytes(
        '2661ab200a594c08840914c9b828927dac710d6915eb0a9f2d0bcae128b243f7',
      ).reversed.toList(),
    );
    final testnet4Block2067 = Block.fromBytes(
      hexToBytes(
        '00000020f009a7425a6b0962bc12d3a2d2497588182202b9b59d46d33835ad0300000000b2ed3db0e5f468e9faa29b50a2bbe9cb041c40c2ecd53156a3d51173719e8e6c6d4b3966c0ff3f1c65c7bf0102010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff0a021308062f4077697a2fffffffff028df2052a01000000160014a54e2a1ec06389203887661535ed118b7d0538890000000000000000266a24aa21a9ed2b5052d89d429b990f78f48e0b0332e2caf6cea8c878168f9847e5b6b3daff8201200000000000000000000000000000000000000000000000000000000000000000000000000200000000010181f980c7703039a91a9a7c5365f9902975e2944209629fa58fc36dd1a25e18310000000000fdffffff022005000000000000160014a54e2a1ec06389203887661535ed118b7d05388953ec052a01000000160014505c4fa6dd11e0b3a0b0211cfa3ddf33958dd8bd02473044022032d0f97adef165f69da184332f68c91fc27782444aacc213088ac7c5ba6fe3a602206d7dbb42dcc78ba1661bb3106bb8ae1b424036592c0a16c9b51adcad46731eba012102476e8b9914532f15a42d34840b3b143746d1bb35d536055a276b41f1321479e111080000',
      ),
    );
    expect(
      testnet4Block2067.header.hashNice(),
      equals(
        '000000000b618d0915876b49345d4c25d9a1210dcbbbf3c63b35b4b1efb13095',
      ),
    );
    final txProvider2067 = TestTxProvider({
      '31185ea2d16dc38fa59f62094294e2752990f965537c9a1aa9393070c780f981':
          Transaction.fromBytes(
            hexToBytes(
              '020000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff0402ad0700ffffffff0200f2052a01000000160014690912f95570260001bc668468269a82b382fd040000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000',
            ),
          ),
    });
    final prevOutputScripts2067 = await BasicBlockFilter.prevOutputScripts(
      testnet4Block2067,
      txProvider2067,
    );
    final filter2067 = BasicBlockFilter(
      block: testnet4Block2067,
      prevOutputScripts: prevOutputScripts2067,
    );
    final header2067 = BasicBlockFilter.filterHeader(
      filter2067.filterHash,
      header2066,
    );
    final header2067Nice = BasicBlockFilter.filterHeaderNice(header2067);
    expect(filter2067.filterBytes, equals(hexToBytes('038633a4f94a94f544')));
    expect(
      header2067Nice,
      equals(
        ('0a3782fac2f02ad53feb61df785b2e2055d70d610309633cd2fb8ced6fbafea0'),
      ),
    );
  });

  test('bip158 test vectors', () async {
    for (var vector in bip158Vectors.skip(1)) {
      final blockHeight = vector[0] as int;
      final blockHash = vector[1] as String;
      final block = Block.fromBytes(hexToBytes(vector[2] as String));
      final prevOutputScripts = (vector[3] as List<String>)
          .map((scriptHex) => hexToBytes(scriptHex))
          .toList();
      final prevBlockFilterHeader = Uint8List.fromList(
        hexToBytes(vector[4] as String).reversed.toList(),
      );
      final blockFilter = (vector[5] as String).toBytes();
      final blockFilterHeader = vector[6] as String;


      final filter = BasicBlockFilter(
        block: block,
        prevOutputScripts: prevOutputScripts,
      );
      final header = BasicBlockFilter.filterHeader(
        filter.filterHash,
        prevBlockFilterHeader,
      );
      expect(
        block.header.hashNice(),
        equals(blockHash),
        reason: 'Block hash does not match for block at height $blockHeight',
      );
      expect(
        filter.filterBytes,
        equals(blockFilter),
        reason: 'Block filter does not match for block at height $blockHeight',
      );
      expect(
        BasicBlockFilter.filterHeaderNice(header),
        equals(blockFilterHeader),
        reason:
            'Block filter header does not match for block at height $blockHeight',
      );
    }
  });

  test('test filter matching', () async {
    // testnet4 block 2067 (with a non-coinbase transaction)
    final testnet4Block2067 = Block.fromBytes(
      hexToBytes(
        '00000020f009a7425a6b0962bc12d3a2d2497588182202b9b59d46d33835ad0300000000b2ed3db0e5f468e9faa29b50a2bbe9cb041c40c2ecd53156a3d51173719e8e6c6d4b3966c0ff3f1c65c7bf0102010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff0a021308062f4077697a2fffffffff028df2052a01000000160014a54e2a1ec06389203887661535ed118b7d0538890000000000000000266a24aa21a9ed2b5052d89d429b990f78f48e0b0332e2caf6cea8c878168f9847e5b6b3daff8201200000000000000000000000000000000000000000000000000000000000000000000000000200000000010181f980c7703039a91a9a7c5365f9902975e2944209629fa58fc36dd1a25e18310000000000fdffffff022005000000000000160014a54e2a1ec06389203887661535ed118b7d05388953ec052a01000000160014505c4fa6dd11e0b3a0b0211cfa3ddf33958dd8bd02473044022032d0f97adef165f69da184332f68c91fc27782444aacc213088ac7c5ba6fe3a602206d7dbb42dcc78ba1661bb3106bb8ae1b424036592c0a16c9b51adcad46731eba012102476e8b9914532f15a42d34840b3b143746d1bb35d536055a276b41f1321479e111080000',
      ),
    );
    final txProvider2067 = TestTxProvider({
      '31185ea2d16dc38fa59f62094294e2752990f965537c9a1aa9393070c780f981':
          Transaction.fromBytes(
            hexToBytes(
              '020000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff0402ad0700ffffffff0200f2052a01000000160014690912f95570260001bc668468269a82b382fd040000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000',
            ),
          ),
    });
    final prevOutputScripts2067 = await BasicBlockFilter.prevOutputScripts(
      testnet4Block2067,
      txProvider2067,
    );
    final filter2067 = BasicBlockFilter(
      block: testnet4Block2067,
      prevOutputScripts: prevOutputScripts2067,
    );
    expect(
      filter2067.match(testnet4Block2067.header.hash(), prevOutputScripts2067),
      isTrue,
    );
    expect(
      filter2067.match(testnet4Block2067.header.hash(), []),
      isFalse,
    );
    expect(
      filter2067.match(testnet4Block2067.header.hash(), [Uint8List(0), Uint8List(32)]),
      isFalse,
    );
  });
}
