// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';

import '../lib/src/blockfilter.dart';
import '../lib/src/block.dart';
import '../lib/src/utils.dart';
import '../lib/src/common.dart';

void main() {
  test('block filter creation', () {
    final testnet4Genesis = Block.genesisBlock(Network.testnet4);
    final filterGenesis = BasicBlockFilter(block: testnet4Genesis);
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
    final filter1 = BasicBlockFilter(block: testnet4Block1);
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
    final filter2 = BasicBlockFilter(block: testnet4Block2);
    final header2 = BasicBlockFilter.filterHeader(filter2.filterHash, header1);
    final header2Nice = BasicBlockFilter.filterHeaderNice(header2);
    expect(filter2.filterBytes, equals(hexToBytes('01810818')));
    expect(
      header2Nice,
      equals(
        ('646af0c2f729e376f1590dedda6298207d09b6870c4be42555a37cde6880817f'),
      ),
    );

    //TODO: tests with blocks that have prevouts
  });
}
