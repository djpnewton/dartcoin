// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/transaction.dart';
import '../lib/src/utils.dart';

void main() {
  test('tx parsing/serialization', () {
    // testnet4 block 1 coinbase transaction (segwit)
    var txHex = '010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff095100062f4077697a2fffffffff0200f2052a010000001976a9140a59837ccd4df25adc31cdad39be6a8d97557ed688ac0000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000';
    var tx = Transaction.fromBytes(hexToBytes(txHex));
    expect(tx.toBytes(), equals(hexToBytes(txHex)));
    expect(tx.txid(), equals('619c9db8597dc8aaaa37569e25930efa04c9aef7b604b1b8a26bd4f086b2785c'));
    expect(tx.version, equals(1));
    expect(tx.marker, equals(0));
    expect(tx.flag, equals(1));
    expect(tx.locktime, equals(0));
    expect(tx.inputs.length, equals(1));
    expect(tx.inputs[0].txid, equals(Uint8List(32)));
    expect(tx.inputs[0].vout, equals(0xffffffff));
    expect(tx.inputs[0].scriptSig, equals(hexToBytes('5100062f4077697a2f')));
    expect(tx.inputs[0].sequence, equals(0xffffffff));
    expect(tx.outputs.length, equals(2));
    expect(tx.outputs[0].value, equals(5000000000));
    expect(tx.outputs[0].scriptPubKey, equals(hexToBytes('76a9140a59837ccd4df25adc31cdad39be6a8d97557ed688ac')));
    expect(tx.outputs[1].value, equals(0));
    expect(tx.outputs[1].scriptPubKey, equals(hexToBytes('6a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf9')));
    expect(tx.witness, isNotNull);
    expect(tx.witness!.stackItems.length, equals(1));
    expect(tx.witness!.stackItems[0].data, equals(hexToBytes('0000000000000000000000000000000000000000000000000000000000000000')));
    var tx2 = Transaction(
      version: tx.version,
      marker: tx.marker,
      flag: tx.flag,
      inputs: tx.inputs,
      outputs: tx.outputs,
      witness: tx.witness,
      locktime: tx.locktime,
    );
    expect(tx2.toBytes(), equals(hexToBytes(txHex)));

    // testnet4 block 2067 non coinbase transaction (segwit)
    txHex = '0200000000010181f980c7703039a91a9a7c5365f9902975e2944209629fa58fc36dd1a25e18310000000000fdffffff022005000000000000160014a54e2a1ec06389203887661535ed118b7d05388953ec052a01000000160014505c4fa6dd11e0b3a0b0211cfa3ddf33958dd8bd02473044022032d0f97adef165f69da184332f68c91fc27782444aacc213088ac7c5ba6fe3a602206d7dbb42dcc78ba1661bb3106bb8ae1b424036592c0a16c9b51adcad46731eba012102476e8b9914532f15a42d34840b3b143746d1bb35d536055a276b41f1321479e111080000';
    tx = Transaction.fromBytes(hexToBytes(txHex));
    expect(tx.toBytes(), equals(hexToBytes(txHex)));
    expect(tx.txid(), equals('3bb9edf5b9b2f1f3e0f7de69147939db1927ef6c075c79fed0ce81fa4cff1b07'));
    expect(tx.version, equals(2));
    expect(tx.marker, equals(0));
    expect(tx.flag, equals(1));
    expect(tx.locktime, equals(2065));
    expect(tx.inputs.length, equals(1));
    expect(tx.inputs[0].txid, equals(hexToBytes('81f980c7703039a91a9a7c5365f9902975e2944209629fa58fc36dd1a25e1831')));
    expect(tx.inputs[0].vout, equals(0));
    expect(tx.inputs[0].scriptSig, equals(Uint8List(0)));
    expect(tx.inputs[0].sequence, equals(4294967293));
    expect(tx.outputs.length, equals(2));
    expect(tx.outputs[0].value, equals(1312));
    expect(tx.outputs[0].scriptPubKey, equals(hexToBytes('0014a54e2a1ec06389203887661535ed118b7d053889')));
    expect(tx.outputs[1].value, equals(4999998547));
    expect(tx.outputs[1].scriptPubKey, equals(hexToBytes('0014505c4fa6dd11e0b3a0b0211cfa3ddf33958dd8bd')));
    expect(tx.witness, isNotNull);
    expect(tx.witness!.stackItems.length, equals(2));
    expect(tx.witness!.stackItems[0].data, equals(hexToBytes('3044022032d0f97adef165f69da184332f68c91fc27782444aacc213088ac7c5ba6fe3a602206d7dbb42dcc78ba1661bb3106bb8ae1b424036592c0a16c9b51adcad46731eba01')));
    expect(tx.witness!.stackItems[1].data, equals(hexToBytes('02476e8b9914532f15a42d34840b3b143746d1bb35d536055a276b41f1321479e1')));
    tx2 = Transaction(
      version: tx.version,
      marker: tx.marker,
      flag: tx.flag,
      inputs: tx.inputs,
      outputs: tx.outputs,
      witness: tx.witness,
      locktime: tx.locktime,
    );
    expect(tx2.toBytes(), equals(hexToBytes(txHex)));

    // testnet3 block 1 coinbase transaction (legacy)
    txHex = '01000000010000000000000000000000000000000000000000000000000000000000000000ffffffff0e0420e7494d017f062f503253482fffffffff0100f2052a010000002321021aeaf2f8638a129a3156fbe7e5ef635226b0bafd495ff03afe2c843d7e3a4b51ac00000000';
    tx = Transaction.fromBytes(hexToBytes(txHex));
    expect(tx.toBytes(), equals(hexToBytes(txHex)));
    expect(tx.txid(), equals('f0315ffc38709d70ad5647e22048358dd3745f3ce3874223c80a7c92fab0c8ba'));
    expect(tx.version, equals(1));
    expect(tx.locktime, equals(0));
    expect(tx.inputs.length, equals(1));
    expect(tx.inputs[0].txid, equals(Uint8List(32)));
    expect(tx.inputs[0].vout, equals(0xffffffff));
    expect(tx.inputs[0].scriptSig, equals(hexToBytes('0420e7494d017f062f503253482f')));
    expect(tx.inputs[0].sequence, equals(0xffffffff));
    expect(tx.outputs.length, equals(1));
    expect(tx.outputs[0].value, equals(5000000000));
    expect(tx.outputs[0].scriptPubKey, equals(hexToBytes('21021aeaf2f8638a129a3156fbe7e5ef635226b0bafd495ff03afe2c843d7e3a4b51ac')));
    expect(tx.witness, isNull);
    tx2 = Transaction(
      version: tx.version,
      inputs: tx.inputs,
      outputs: tx.outputs,
      locktime: tx.locktime,
    );
    expect(tx2.toBytes(), equals(hexToBytes(txHex)));

    // testnet3 block 19043 non coinbase transaction (legacy)
    txHex = '0100000001c181fef965f3baff3371623f1813682d7e367fd46fb0d68da459dfe861679946000000006a4730440220728a9e02be7b0c2e148aad0b0866308313a58e899c9a811d33b247cdc3de5dd102200f225869167c7fde498dfa5731dde5e0d37da71fd992a6ee752bfe6c7d1747e2012103372ac4423314b0f492fd5870c477d9331f624c183f37160bdec3a6c0f60e49afffffffff0100743ba40b0000001976a91457448a68e0c5cf5cc2fbdda00b9570396cba8f5d88ac00000000';
    tx = Transaction.fromBytes(hexToBytes(txHex));
    expect(tx.toBytes(), equals(hexToBytes(txHex)));
    expect(tx.txid(), equals('a3e63e17784ad21515dd37e4742923e9ff5753dc80f003b521fd60f08389f738'));
    expect(tx.version, equals(1));
    expect(tx.locktime, equals(0));
    expect(tx.inputs.length, equals(1));
    expect(tx.inputs[0].txid, equals(hexToBytes('c181fef965f3baff3371623f1813682d7e367fd46fb0d68da459dfe861679946')));
    expect(tx.inputs[0].vout, equals(0));
    expect(tx.inputs[0].scriptSig, equals(hexToBytes('4730440220728a9e02be7b0c2e148aad0b0866308313a58e899c9a811d33b247cdc3de5dd102200f225869167c7fde498dfa5731dde5e0d37da71fd992a6ee752bfe6c7d1747e2012103372ac4423314b0f492fd5870c477d9331f624c183f37160bdec3a6c0f60e49af')));
    expect(tx.inputs[0].sequence, equals(0xffffffff));
    expect(tx.outputs.length, equals(1));
    expect(tx.outputs[0].value, equals(50000000000));
    expect(tx.outputs[0].scriptPubKey, equals(hexToBytes('76a91457448a68e0c5cf5cc2fbdda00b9570396cba8f5d88ac')));
    expect(tx.witness, isNull);
    tx2 = Transaction(
      version: tx.version,
      inputs: tx.inputs,
      outputs: tx.outputs,
      locktime: tx.locktime,
    );
    expect(tx2.toBytes(), equals(hexToBytes(txHex)));
  });
}
