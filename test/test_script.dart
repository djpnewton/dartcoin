// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/common.dart';
import '../lib/src/script.dart';
import '../lib/src/utils.dart';

void main() {
  test('matchScriptPubKey()', () {
    // txid 29aeba74e17931a9b34923ae636bb8bd35b0ebd40e6eb013c322f272a071db55, testnet3 p2pkh 
    var scriptPubKey = hexToBytes('76a914a6d633033f750ee06accd7eb288f96eda5de922688ac');
    var spkMatch = matchScriptPubKey(scriptPubKey);
    expect(spkMatch.scriptType, equals(ScriptType.p2pkh));
    expect(bytesToHex(spkMatch.payload), equals('a6d633033f750ee06accd7eb288f96eda5de9226'));

    // txid dca0ca637c5c12a23e870fcce946c52d8b9067b374edeff9d17e74abdee2801d, testnet3 p2wpkh
    scriptPubKey = hexToBytes('0014f39de63512203d0c5a48beedf25195ef47571fa7');
    spkMatch = matchScriptPubKey(scriptPubKey);
    expect(spkMatch.scriptType, equals(ScriptType.p2wpkh));
    expect(bytesToHex(spkMatch.payload), equals('f39de63512203d0c5a48beedf25195ef47571fa7'));

    // opreturn (not handled by matchScriptPubKey)
    scriptPubKey = hexToBytes('6a176661756365742e746573746e6574342e6465762074786e');
    expect(() => matchScriptPubKey(scriptPubKey), throwsArgumentError);

    // txid 450c309b70fb3f71b63b10ce60af17499bd21b1db39aa47b19bf22166ee67144, mainnet p2sh
    scriptPubKey = hexToBytes('a914748284390f9e263a4b766a75d0633c50426eb87587');
    spkMatch = matchScriptPubKey(scriptPubKey);
    expect(spkMatch.scriptType, equals(ScriptType.p2sh));
    expect(bytesToHex(spkMatch.payload), equals('748284390f9e263a4b766a75d0633c50426eb875'));

    // txid 46ebe264b0115a439732554b2b390b11b332b5b5692958b1754aa0ee57b64265, mainnet p2wsh
    scriptPubKey = hexToBytes('002065f91a53cb7120057db3d378bd0f7d944167d43a7dcbff15d6afc4823f1d3ed3');
    spkMatch = matchScriptPubKey(scriptPubKey);
    expect(spkMatch.scriptType, equals(ScriptType.p2wsh));
    expect(bytesToHex(spkMatch.payload), equals('65f91a53cb7120057db3d378bd0f7d944167d43a7dcbff15d6afc4823f1d3ed3'));

    // txid d1c40446c65456a9b11a9dddede31ee34b8d3df83788d98f690225d2958bfe3c, mainet p2tr (not handled by matchScriptPubKey)
    scriptPubKey = hexToBytes('5120f3778defe5173a9bf7169575116224f961c03c725c0e98b8da8f15df29194b80');
    expect(() => matchScriptPubKey(scriptPubKey), throwsArgumentError);

    // empty script
    scriptPubKey = Uint8List(0);
    expect(() => matchScriptPubKey(scriptPubKey), throwsArgumentError);
  });
}
