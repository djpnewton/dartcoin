// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';

import '../lib/src/utils.dart';
import '../lib/src/common.dart';
import '../lib/src/address.dart';

class AddrTest {
  final String name;
  final String address;
  final AddressData expected;

  AddrTest({required this.name, required this.address, required this.expected});
}

void main() {
  test('p2pkhAddress() creates a P2PKH address', () {
    final publicKey = hexToBytes(
      '0207a22257fad2aa0f48cc46c60681117af064482624a329c217e728bcea419265',
    );
    final addressMainnet = p2pkhAddress(publicKey, network: Network.mainnet);
    final addressTestnet = p2pkhAddress(publicKey, network: Network.testnet);
    expect(addressMainnet, equals('17CAWEuEXomN3GqbMtZ7YvRyziaveBNBxo'));
    expect(addressTestnet, equals('mmi7oHzDLqCcpPKD5TXVNqeJriBdZqZNgC'));
    // invalid length
    var publicKeyInvalid = hexToBytes('0207a22257fad2aa0f48cc46c606');
    expect(
      () => p2pkhAddress(publicKeyInvalid, network: Network.mainnet),
      throwsArgumentError,
    );
    // invalid prefix
    publicKeyInvalid = hexToBytes(
      '0107a22257fad2aa0f48cc46c60681117af064482624a329c217e728bcea419265',
    );
    expect(
      () => p2pkhAddress(publicKeyInvalid, network: Network.mainnet),
      throwsArgumentError,
    );
  });
  test('p2shP2wpkhAddress() creates a P2SH-P2WPKH address', () {
    final publicKey = hexToBytes(
      '030305aff85dd48d32aa8fea019e09bed36db9db18b46f8339d0ad1cd7a11210c9',
    );
    final addressMainnet = p2shP2wpkhAddress(
      publicKey,
      network: Network.mainnet,
    );
    final addressTestnet = p2shP2wpkhAddress(
      publicKey,
      network: Network.testnet,
    );
    expect(addressMainnet, equals('3EGHyaUqjngxeaMrDC8KaNE3R2rfmADUqM'));
    expect(addressTestnet, equals('2N5pW3KQsMFCJrMzPtKkCCKDJdP4qdAy7tD'));
    // invalid length
    var publicKeyInvalid = hexToBytes(
      '030305aff85dd48d32aa8fea019e09bed36db9db18b46f8339d0ad1cd7a11210c9ff',
    );
    expect(
      () => p2shP2wpkhAddress(publicKeyInvalid, network: Network.mainnet),
      throwsArgumentError,
    );
    // invalid prefix
    publicKeyInvalid = hexToBytes(
      '050305aff85dd48d32aa8fea019e09bed36db9db18b46f8339d0ad1cd7a11210c9',
    );
    expect(
      () => p2shP2wpkhAddress(publicKeyInvalid, network: Network.mainnet),
      throwsArgumentError,
    );
  });
  test('p2wpkhAddress() creates a P2WPKH address', () {
    var publicKey = hexToBytes(
      '02d0b6a6e2acf8f3c2ff2bd17ebb01798924db2c42f0f6724fa09169a72cc48dae',
    );
    var addressMainnet = p2wpkhAddress(publicKey, network: Network.mainnet);
    var addressTestnet = p2wpkhAddress(publicKey, network: Network.testnet);
    expect(
      addressMainnet,
      equals('bc1qmdextqm66f2prkp4vkjexsc6trp56956w5rm0e'),
    );
    expect(
      addressTestnet,
      equals('tb1qmdextqm66f2prkp4vkjexsc6trp56956yjcg52'),
    );
    // invalid length
    var publicKeyInvalid = hexToBytes(
      '02d0b6a6e2acf8f3c2ff2bd17ebb01798924db2c42f0f6724fa09169a72cc48daeff',
    );
    expect(
      () => p2wpkhAddress(publicKeyInvalid, network: Network.mainnet),
      throwsArgumentError,
    );
    // invalid prefix
    publicKeyInvalid = hexToBytes(
      '06d0b6a6e2acf8f3c2ff2bd17ebb01798924db2c42f0f6724fa09169a72cc48dae',
    );
    expect(
      () => p2wpkhAddress(publicKeyInvalid, network: Network.mainnet),
      throwsArgumentError,
    );
  });
  test('parse addresses', () {
    final testVectors = [
      AddrTest(
        name: 'p2pkh mainnet',
        address: '17krsNjaUFr1vDtVkCc45JHX4LEm3TQSET',
        expected: AddressData(
          type: AddressType(
            prefix: '1',
            scriptType: ScriptType.p2pkh,
            network: Network.mainnet,
            dataLength: 20,
            encoding: AddressEncoding.base58,
          ),
          script: hexToBytes(
            '76a9144a1c44eb1191b1bb47c001ddef53749aaf2f791088ac',
          ),
        ),
      ),
      AddrTest(
        name: 'p2sh mainnet',
        address: '3JpAoYhzx8u17TcxjGFBBSYhqLtMkLRuA5',
        expected: AddressData(
          type: AddressType(
            prefix: '3',
            scriptType: ScriptType.p2sh,
            network: Network.mainnet,
            dataLength: 20,
            encoding: AddressEncoding.base58,
          ),
          script: hexToBytes('a914bbd47651c9a5c430f887d218f595bf18c12ff90287'),
        ),
      ),
      AddrTest(
        name: 'p2wpkh mainnet',
        address: 'bc1qyyezpk4qclm48c8xdup08alh9fgyn69mjr8mhs',
        expected: AddressData(
          type: AddressType(
            prefix: 'bc1q',
            scriptType: ScriptType.p2wpkh,
            network: Network.mainnet,
            dataLength: 20,
            encoding: AddressEncoding.bech32,
          ),
          script: hexToBytes('0014213220daa0c7f753e0e66f02f3f7f72a5049e8bb'),
        ),
      ),
      AddrTest(
        name: 'p2wsh mainnet',
        address:
            'bc1q3ea2pnrcknv0qectk8wzy67t3ke4kjn60hne5zxujdqzvf69dqlqwvla2n',
        expected: AddressData(
          type: AddressType(
            prefix: 'bc1q',
            scriptType: ScriptType.p2wsh,
            network: Network.mainnet,
            dataLength: 32,
            encoding: AddressEncoding.bech32,
          ),
          script: hexToBytes(
            '00208e7aa0cc78b4d8f0670bb1dc226bcb8db35b4a7a7de79a08dc9340262745683e',
          ),
        ),
      ),
      AddrTest(
        name: 'p2tr mainnet',
        address:
            'bc1pc2vkmghdtuc3fnvgqnmyjyfdhq2a3fu30t2fkjz7dtmh2kdftrtsnykkzz',
        expected: AddressData(
          type: AddressType(
            prefix: 'bc1p',
            scriptType: ScriptType.p2tr,
            network: Network.mainnet,
            dataLength: 32,
            encoding: AddressEncoding.bech32m,
          ),
          script: hexToBytes(
            '5120c2996da2ed5f3114cd8804f649112db815d8a7917ad49b485e6af77559a958d7',
          ),
        ),
      ),
      AddrTest(
        name: 'p2pkh testnet (prefix m)',
        address: 'moKzZBmNrpmDqacrZMVEwPnCodRsJL7hjt',
        expected: AddressData(
          type: AddressType(
            prefix: 'm',
            scriptType: ScriptType.p2pkh,
            network: Network.testnet,
            dataLength: 20,
            encoding: AddressEncoding.base58,
          ),
          script: hexToBytes(
            '76a91455ae51684c43435da751ac8d2173b2652eb6410588ac',
          ),
        ),
      ),
      AddrTest(
        name: 'p2pkh testnet (prefix n)',
        address: 'n451ywZYwPpX7mGWwbK5BsJ8jbwdFfauot',
        expected: AddressData(
          type: AddressType(
            prefix: 'n',
            scriptType: ScriptType.p2pkh,
            network: Network.testnet,
            dataLength: 20,
            encoding: AddressEncoding.base58,
          ),
          script: hexToBytes(
            '76a914f7632807e3093aff8025eaee170d9073e51b0a1988ac',
          ),
        ),
      ),
      AddrTest(
        name: 'p2sh testnet',
        address: '2MzVNQvcVferfpT3qPkBBNHHwavExCp3ZLj',
        expected: AddressData(
          type: AddressType(
            prefix: '2',
            scriptType: ScriptType.p2sh,
            network: Network.testnet,
            dataLength: 20,
            encoding: AddressEncoding.base58,
          ),
          script: hexToBytes('a9144f75bc95cd416b5501fe5aa5be3e2e2c55b860c487'),
        ),
      ),
      AddrTest(
        name: 'p2wpkh testnet',
        address: 'tb1qyyezpk4qclm48c8xdup08alh9fgyn69mc9ugvr',
        expected: AddressData(
          type: AddressType(
            prefix: 'tb1q',
            scriptType: ScriptType.p2wpkh,
            network: Network.testnet,
            dataLength: 20,
            encoding: AddressEncoding.bech32,
          ),
          script: hexToBytes('0014213220daa0c7f753e0e66f02f3f7f72a5049e8bb'),
        ),
      ),
      AddrTest(
        name: 'p2wsh testnet',
        address:
            'tb1q3ea2pnrcknv0qectk8wzy67t3ke4kjn60hne5zxujdqzvf69dqlqeyfjsu',
        expected: AddressData(
          type: AddressType(
            prefix: 'tb1q',
            scriptType: ScriptType.p2wsh,
            network: Network.testnet,
            dataLength: 32,
            encoding: AddressEncoding.bech32,
          ),
          script: hexToBytes(
            '00208e7aa0cc78b4d8f0670bb1dc226bcb8db35b4a7a7de79a08dc9340262745683e',
          ),
        ),
      ),
      AddrTest(
        name: 'p2tr testnet',
        address:
            'tb1pc2vkmghdtuc3fnvgqnmyjyfdhq2a3fu30t2fkjz7dtmh2kdftrtsyvqecd',
        expected: AddressData(
          type: AddressType(
            prefix: 'tb1p',
            scriptType: ScriptType.p2tr,
            network: Network.testnet,
            dataLength: 32,
            encoding: AddressEncoding.bech32m,
          ),
          script: hexToBytes(
            '5120c2996da2ed5f3114cd8804f649112db815d8a7917ad49b485e6af77559a958d7',
          ),
        ),
      ),
      AddrTest(
        name: 'p2wpkh regtest',
        address: 'bcrt1qyyezpk4qclm48c8xdup08alh9fgyn69m6v99m2',
        expected: AddressData(
          type: AddressType(
            prefix: 'bcrt1q',
            scriptType: ScriptType.p2wpkh,
            network: Network.regtest,
            dataLength: 20,
            encoding: AddressEncoding.bech32,
          ),
          script: hexToBytes('0014213220daa0c7f753e0e66f02f3f7f72a5049e8bb'),
        ),
      ),
      AddrTest(
        name: 'p2wsh regtest',
        address:
            'bcrt1q3ea2pnrcknv0qectk8wzy67t3ke4kjn60hne5zxujdqzvf69dqlq5ar59x',
        expected: AddressData(
          type: AddressType(
            prefix: 'bcrt1q',
            scriptType: ScriptType.p2wsh,
            network: Network.regtest,
            dataLength: 32,
            encoding: AddressEncoding.bech32,
          ),
          script: hexToBytes(
            '00208e7aa0cc78b4d8f0670bb1dc226bcb8db35b4a7a7de79a08dc9340262745683e',
          ),
        ),
      ),
      AddrTest(
        name: 'p2tr regtest',
        address:
            'bcrt1pc2vkmghdtuc3fnvgqnmyjyfdhq2a3fu30t2fkjz7dtmh2kdftrtsf42ldh',
        expected: AddressData(
          type: AddressType(
            prefix: 'bcrt1p',
            scriptType: ScriptType.p2tr,
            network: Network.regtest,
            dataLength: 32,
            encoding: AddressEncoding.bech32m,
          ),
          script: hexToBytes(
            '5120c2996da2ed5f3114cd8804f649112db815d8a7917ad49b485e6af77559a958d7',
          ),
        ),
      ),
    ];

    for (final test in testVectors) {
      final parsed = AddressData.parseAddress(test.address);
      expect(
        parsed.type.prefix,
        equals(test.expected.type.prefix),
        reason: 'Failed on ${test.name} prefix',
      );
      expect(
        parsed.type.scriptType,
        equals(test.expected.type.scriptType),
        reason: 'Failed on ${test.name} scriptType',
      );
      expect(
        parsed.type.network,
        equals(test.expected.type.network),
        reason: 'Failed on ${test.name} network',
      );
      expect(
        parsed.type.dataLength,
        equals(test.expected.type.dataLength),
        reason: 'Failed on ${test.name} hashLength',
      );
      expect(
        parsed.type.encoding,
        equals(test.expected.type.encoding),
        reason: 'Failed on ${test.name} encoding',
      );
      expect(
        bytesToHex(parsed.script),
        equals(bytesToHex(test.expected.script)),
        reason: 'Failed on ${test.name} script',
      );
    }
  });
}
