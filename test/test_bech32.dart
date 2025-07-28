// ignore_for_file: avoid_relative_lib_imports

import 'package:test/test.dart';

import '../lib/src/common.dart';
import '../lib/src/bech32.dart';
import '../lib/src/utils.dart';

void main() {
  test('bech32Encode()', () {
    // P2WPKH address example
    var scriptPubKey = hexToBytes(
      '00145a9bfcdccd086dee2c26f490341589e97194845a',
    );
    var address = bech32Encode(scriptPubKey, network: Network.mainnet);
    expect(address, equals('bc1qt2dlehxdppk7utpx7jgrg9vfa9cefpz6wyrlka'));
    var addressTestnet = bech32Encode(scriptPubKey, network: Network.testnet);
    expect(
      addressTestnet,
      equals('tb1qt2dlehxdppk7utpx7jgrg9vfa9cefpz6yzcvdw'),
    );
    var addressRegtest = bech32Encode(scriptPubKey, network: Network.regtest);
    expect(
      addressRegtest,
      equals('bcrt1qt2dlehxdppk7utpx7jgrg9vfa9cefpz6xtpp68'),
    );
    // P2WSH address example
    scriptPubKey = hexToBytes(
      '0020e5e8be796ee121ee037cf429117311a4f3d893dcba6409b41382132992441402',
    );
    address = bech32Encode(scriptPubKey, network: Network.mainnet);
    expect(
      address,
      equals('bc1quh5tu7twuys7uqmu7s53zuc35nea3y7uhfjqndqnsgfjnyjyzspqcv0zsz'),
    );
    addressTestnet = bech32Encode(scriptPubKey, network: Network.testnet);
    expect(
      addressTestnet,
      equals('tb1quh5tu7twuys7uqmu7s53zuc35nea3y7uhfjqndqnsgfjnyjyzspq0yed2d'),
    );
    addressRegtest = bech32Encode(scriptPubKey, network: Network.regtest);
    expect(
      addressRegtest,
      equals(
        'bcrt1quh5tu7twuys7uqmu7s53zuc35nea3y7uhfjqndqnsgfjnyjyzspqzantlh',
      ),
    );
    // P2TR address example
    scriptPubKey = hexToBytes(
      '5120be39385a990fedd22a4ed8c810e663677aafa93187c2dafebc65dcd5195b660c',
    );
    address = bech32Encode(scriptPubKey, network: Network.mainnet);
    expect(
      address,
      equals('bc1phcunsk5eplkay2jwmryppenrvaa2l2f3slpd4l4uvhwd2x2mvcxqdkw80s'),
    );
    addressTestnet = bech32Encode(scriptPubKey, network: Network.testnet);
    expect(
      addressTestnet,
      equals('tb1phcunsk5eplkay2jwmryppenrvaa2l2f3slpd4l4uvhwd2x2mvcxq67cg4l'),
    );
    addressRegtest = bech32Encode(scriptPubKey, network: Network.regtest);
    expect(
      addressRegtest,
      equals(
        'bcrt1phcunsk5eplkay2jwmryppenrvaa2l2f3slpd4l4uvhwd2x2mvcxqh8jwq9',
      ),
    );
    // Invalid scriptPubKey length
    scriptPubKey = hexToBytes('00145a9bfcdccd086dee2c26f490341589e97194845aFF');
    expect(
      () => bech32Encode(scriptPubKey, network: Network.mainnet),
      throwsArgumentError,
    );
    // Invalid scriptPubKey version
    scriptPubKey = hexToBytes('FF145a9bfcdccd086dee2c26f490341589e97194845a');
    expect(
      () => bech32Encode(scriptPubKey, network: Network.mainnet),
      throwsArgumentError,
    );
    scriptPubKey = hexToBytes('01145a9bfcdccd086dee2c26f490341589e97194845a');
    expect(
      () => bech32Encode(scriptPubKey, network: Network.mainnet),
      throwsArgumentError,
    );
  });
  test('bech32Decode()', () {
    // P2WPKH address example
    var address = 'bc1qt2dlehxdppk7utpx7jgrg9vfa9cefpz6wyrlka';
    var beck32 = bech32Decode(address);
    expect(
      beck32.scriptPubKey,
      equals(hexToBytes('00145a9bfcdccd086dee2c26f490341589e97194845a')),
    );
    // P2WSH address example
    address = 'bc1quh5tu7twuys7uqmu7s53zuc35nea3y7uhfjqndqnsgfjnyjyzspqcv0zsz';
    beck32 = bech32Decode(address);
    expect(
      beck32.scriptPubKey,
      equals(
        hexToBytes(
          '0020e5e8be796ee121ee037cf429117311a4f3d893dcba6409b41382132992441402',
        ),
      ),
    );
    // P2TR address example
    address = 'bc1phcunsk5eplkay2jwmryppenrvaa2l2f3slpd4l4uvhwd2x2mvcxqdkw80s';
    beck32 = bech32Decode(address);
    expect(
      beck32.scriptPubKey,
      equals(
        hexToBytes(
          '5120be39385a990fedd22a4ed8c810e663677aafa93187c2dafebc65dcd5195b660c',
        ),
      ),
    );
    // Invalid address (wrong prefix)
    address = 'ac1qt2dlehxdppk7utpx7jgrg9vfa9cefpz6wyrlka';
    expect(() => bech32Decode(address), throwsArgumentError);
    // Invalid address (wrong checksum)
    address = 'bc1qt2dlehxdppk7utpx7jgrg9vfa9cefpz6wyrlkb';
    expect(() => bech32Decode(address), throwsArgumentError);
    // Invalid version byte
    address = 'bc10cyyfneracqkn289tlr55s5f5ll0t5exeqj3edr';
    expect(() => bech32Decode(address), throwsArgumentError);
    // Invalid scriptPubKey length
    address = 'bc1qcyyfneracqkn289tlr55s5f5ll0t5eq0swnc0';
    expect(() {
      bech32Decode(address);
    }, throwsArgumentError);
  });
}
