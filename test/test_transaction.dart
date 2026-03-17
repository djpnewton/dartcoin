// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/transaction.dart';
import '../lib/src/utils.dart';

void main() {
  test('tx parsing/serialization', () async {
    // testnet4 block 1 coinbase transaction (segwit)
    var txHex = '010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff095100062f4077697a2fffffffff0200f2052a010000001976a9140a59837ccd4df25adc31cdad39be6a8d97557ed688ac0000000000000000266a24aa21a9ede2f61c3f71d1defd3fa999dfa36953755c690689799962b48bebd836974e8cf90120000000000000000000000000000000000000000000000000000000000000000000000000';
    var tx = Transaction.fromBytes(hexToBytes(txHex));
    expect(tx.toBytes(), equals(hexToBytes(txHex)));
    expect(tx.txid(), equals('619c9db8597dc8aaaa37569e25930efa04c9aef7b604b1b8a26bd4f086b2785c'));
    expect(tx.type(), equals(TxType.segwit));
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
    expect(tx.witness?.length, equals(1));
    expect(tx.witness?[0].stackItems.length, equals(1));
    expect(tx.witness?[0].stackItems[0].data, equals(hexToBytes('0000000000000000000000000000000000000000000000000000000000000000')));
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
    expect(tx.type(), equals(TxType.segwit));
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
    expect(tx.witness?.length, equals(1));
    expect(tx.witness?[0].stackItems.length, equals(2));
    expect(tx.witness?[0].stackItems[0].data, equals(hexToBytes('3044022032d0f97adef165f69da184332f68c91fc27782444aacc213088ac7c5ba6fe3a602206d7dbb42dcc78ba1661bb3106bb8ae1b424036592c0a16c9b51adcad46731eba01')));
    expect(tx.witness?[0].stackItems[1].data, equals(hexToBytes('02476e8b9914532f15a42d34840b3b143746d1bb35d536055a276b41f1321479e1')));
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
    expect(tx.type(), equals(TxType.legacy));
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
    expect(tx.witness, equals(null));
    tx2 = Transaction(
      version: tx.version,
      inputs: tx.inputs,
      outputs: tx.outputs,
      witness: [],
      locktime: tx.locktime,
    );
    expect(tx2.toBytes(), equals(hexToBytes(txHex)));

    // testnet3 block 19043 non coinbase transaction (legacy)
    txHex = '0100000001c181fef965f3baff3371623f1813682d7e367fd46fb0d68da459dfe861679946000000006a4730440220728a9e02be7b0c2e148aad0b0866308313a58e899c9a811d33b247cdc3de5dd102200f225869167c7fde498dfa5731dde5e0d37da71fd992a6ee752bfe6c7d1747e2012103372ac4423314b0f492fd5870c477d9331f624c183f37160bdec3a6c0f60e49afffffffff0100743ba40b0000001976a91457448a68e0c5cf5cc2fbdda00b9570396cba8f5d88ac00000000';
    tx = Transaction.fromBytes(hexToBytes(txHex));
    expect(tx.toBytes(), equals(hexToBytes(txHex)));
    expect(tx.txid(), equals('a3e63e17784ad21515dd37e4742923e9ff5753dc80f003b521fd60f08389f738'));
    expect(tx.type(), equals(TxType.legacy));
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
    expect(tx.witness, equals(null));
    tx2 = Transaction(
      version: tx.version,
      inputs: tx.inputs,
      outputs: tx.outputs,
      witness: [],
      locktime: tx.locktime,
    );
    expect(tx2.toBytes(), equals(hexToBytes(txHex)));

    // testnet4 110405 (segwit, multiple witness fields)
    txHex = '010000000001026abd13c7108fd5de6911f32dcc5d389410fbc59f1f22a2fa34036990c57e410f0100000000ffffffff2078bbfaa7fa78dc6bfb3b78edbaea91c42018653ec35367a4576ab0250bbc410100000000ffffffff02c5320000000000001600140db72b0be58bc19872f0847fc4ef9f27992be4577e6c0f0000000000160014704c0fca4db576b4205b355573be868dafa01616024730440220151e757b3a803a4ada641dde0fd1e98317fa27d34b668fb7473d0ce46ef68546022020a1cc57f15abd08bb479c558b96156fe00ffcff7235840da90e360097dd306c012103f4dec1bd825a5942c62724e1fb21f8e962085409cbefff1446a5f350f2814b7902473044022030cc063613b8048dd059a6410c1cbfbb3dfaf88389947546ce3ffaf20744a22f0220663f135e063a7730dd286d2c27d186a3b430f48c9970b5245ab900610d2777500121027e79827360ca963fdc547f89e14e841483216582add05c705178b926ba23ad6700000000';
    tx = Transaction.fromBytes(hexToBytes(txHex));
    expect(tx.toBytes(), equals(hexToBytes(txHex)));
    expect(tx.txid(), equals('a203baeba2f8402a2cb0c42a3fee756f51e4509e91fff61cc86db8a9f4a57506'));
    expect(tx.type(), equals(TxType.segwit));
    expect(tx.version, equals(1));
    expect(tx.marker, equals(0));
    expect(tx.flag, equals(1));
    expect(tx.locktime, equals(0));
    expect(tx.inputs.length, equals(2));
    expect(tx.inputs[0].txid, equals(hexToBytes('0f417ec590690334faa2221f9fc5fb1094385dcc2df31169ded58f10c713bd6a').reversed.toList()));
    expect(tx.inputs[0].vout, equals(1));
    expect(tx.inputs[0].scriptSig, equals(Uint8List(0)));
    expect(tx.inputs[0].sequence, equals(0xffffffff));
    expect(tx.inputs[1].txid, equals(hexToBytes('41bc0b25b06a57a46753c33e651820c491eabaed783bfb6bdc78faa7fabb7820').reversed.toList()));
    expect(tx.inputs[1].vout, equals(1));
    expect(tx.inputs[1].scriptSig, equals(Uint8List(0)));
    expect(tx.inputs[1].sequence, equals(0xffffffff));
    expect(tx.outputs.length, equals(2));
    expect(tx.outputs[0].value, equals(12997));
    expect(tx.outputs[0].scriptPubKey, equals(hexToBytes('00140db72b0be58bc19872f0847fc4ef9f27992be457')));
    expect(tx.outputs[1].value, equals(1010814));
    expect(tx.outputs[1].scriptPubKey, equals(hexToBytes('0014704c0fca4db576b4205b355573be868dafa01616')));
    expect(tx.witness?.length, equals(2));
    expect(tx.witness?[0].stackItems.length, equals(2));
    expect(tx.witness?[0].stackItems[0].data, equals(hexToBytes('30440220151e757b3a803a4ada641dde0fd1e98317fa27d34b668fb7473d0ce46ef68546022020a1cc57f15abd08bb479c558b96156fe00ffcff7235840da90e360097dd306c01')));
    expect(tx.witness?[0].stackItems[1].data, equals(hexToBytes('03f4dec1bd825a5942c62724e1fb21f8e962085409cbefff1446a5f350f2814b79')));
    expect(tx.witness?[1].stackItems.length, equals(2));
    expect(tx.witness?[1].stackItems[0].data, equals(hexToBytes('3044022030cc063613b8048dd059a6410c1cbfbb3dfaf88389947546ce3ffaf20744a22f0220663f135e063a7730dd286d2c27d186a3b430f48c9970b5245ab900610d27775001')));
    expect(tx.witness?[1].stackItems[1].data, equals(hexToBytes('027e79827360ca963fdc547f89e14e841483216582add05c705178b926ba23ad67')));
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
  });

  test('create/serialize/parse TxIn', () {
    var txIn = TxIn(
      txid: hexToBytes('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'),
      vout: 1,
      scriptSig: hexToBytes('483045022100f3b1e5c8a2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f901234567890abcdef01202206d7dbb42dcc78ba1661bb3106bb8ae1b424036592c0a16c9b51adcad46731eba01'),
      sequence: 0xffffffff,
    );
    var txInBytes = txIn.toBytes();
    var txInParsed = TxIn.fromBytes(txInBytes);
    expect(txInParsed.txid, equals(txIn.txid));
    expect(txInParsed.vout, equals(txIn.vout));
    expect(txInParsed.scriptSig, equals(txIn.scriptSig));
    expect(txInParsed.sequence, equals(txIn.sequence));
    var txInParsedBytes = txInParsed.toBytes();
    expect(txInParsedBytes, equals(txInBytes));
  });

  test('create/serialize/parse TxOut', () {
    var txOut = TxOut(
      value: 10000,
      scriptPubKey: hexToBytes('76a9140a59837ccd4df25adc31cdad39be6a8d97557ed688ac'),
    );
    var txOutBytes = txOut.toBytes();
    var txOutParsed = TxOut.fromBytes(txOutBytes);
    expect(txOutParsed.value, equals(txOut.value));
    expect(txOutParsed.scriptPubKey, equals(txOut.scriptPubKey));
    var txOutParsedBytes = txOutParsed.toBytes();
    expect(txOutParsedBytes, equals(txOutBytes));
  });

  test('create/serialize/parse TxWitness', () {
    var txWitness = TxWitness(
      stackItems: [
        WitnessStackItem(hexToBytes('3044022030cc063613b8048dd059a6410c1cbfbb3dfaf88389947546ce3ffaf20744a22f0220663f135e063a7730dd286d2c27d186a3b430f48c9970b5245ab900610d27775001')),
        WitnessStackItem(hexToBytes('027e79827360ca963fdc547f89e14e841483216582add05c705178b926ba23ad67')),
      ],
    );
    var txWitnessBytes = txWitness.toBytes();
    var txWitnessParsed = TxWitness.fromBytes(txWitnessBytes);
    expect(txWitnessParsed.stackItems.length, equals(txWitness.stackItems.length));
    for (var i = 0; i < txWitness.stackItems.length; i++) {
      expect(txWitnessParsed.stackItems[i].data, equals(txWitness.stackItems[i].data));
    }
    var txWitnessParsedBytes = txWitnessParsed.toBytes();
    expect(txWitnessParsedBytes, equals(txWitnessBytes));

    var emptyWitness = TxWitness(stackItems: []);
    var emptyWitnessBytes = emptyWitness.toBytes();
    var emptyWitnessParsed = TxWitness.fromBytes(emptyWitnessBytes);
    expect(emptyWitnessParsed.stackItems.length, equals(0));
    var emptyWitnessParsedBytes = emptyWitnessParsed.toBytes();
    expect(emptyWitnessParsedBytes, equals(emptyWitnessBytes));
  });

  test('create/serialize/parse Transaction', () {
    // segwit tx
    var tx = Transaction(
      version: 1,
      marker: 0,
      flag: 1,
      inputs: [
        TxIn(
          txid: hexToBytes('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'),
          vout: 1,
          scriptSig: Uint8List(0),
          sequence: 0xffffffff,
        ),
      ],
      outputs: [
        TxOut(
          value: 10000,
          scriptPubKey: hexToBytes('76a9140a59837ccd4df25adc31cdad39be6a8d97557ed688ac'),
        ),
      ],
      witness: [
        TxWitness(
          stackItems: [
            WitnessStackItem(hexToBytes('3044022030cc063613b8048dd059a6410c1cbfbb3dfaf88389947546ce3ffaf20744a22f0220663f135e063a7730dd286d2c27d186a3b430f48c9970b5245ab900610d27775001')),
            WitnessStackItem(hexToBytes('027e79827360ca963fdc547f89e14e841483216582add05c705178b926ba23ad67')),
          ],
        ),
      ],
      locktime: 0,
    );
    var txBytes = tx.toBytes();
    var txParsed = Transaction.fromBytes(txBytes);
    expect(txParsed.version, equals(tx.version));
    expect(txParsed.marker, equals(tx.marker));
    expect(txParsed.flag, equals(tx.flag));
    expect(txParsed.inputs.length, equals(tx.inputs.length));
    for (var i = 0; i < tx.inputs.length; i++) {
      expect(txParsed.inputs[i].txid, equals(tx.inputs[i].txid));
      expect(txParsed.inputs[i].vout, equals(tx.inputs[i].vout));
      expect(txParsed.inputs[i].scriptSig, equals(tx.inputs[i].scriptSig));
      expect(txParsed.inputs[i].sequence, equals(tx.inputs[i].sequence));
    }
    expect(txParsed.outputs.length, equals(tx.outputs.length));
    for (var i = 0; i < tx.outputs.length; i++) {
      expect(txParsed.outputs[i].value, equals(tx.outputs[i].value));
      expect(txParsed.outputs[i].scriptPubKey, equals(tx.outputs[i].scriptPubKey));
    }
    expect(txParsed.witness?.length, equals(tx.witness?.length));
    for (var i = 0; i < (tx.witness?.length ?? 0); i++) {
      expect(txParsed.witness?[i].stackItems.length, equals(tx.witness?[i].stackItems.length));
      for (var j = 0; j < (tx.witness?[i].stackItems.length ?? 0); j++) {
        expect(txParsed.witness?[i].stackItems[j].data, equals(tx.witness?[i].stackItems[j].data));
      }
    }
    expect(txParsed.locktime, equals(tx.locktime));
    var txParsedBytes = txParsed.toBytes();
    expect(txParsedBytes, equals(txBytes));
    // empty segwit tx
    tx = Transaction(
      version: 1,
      marker: 0,
      flag: 1,
      inputs: [],
      outputs: [],
      witness: [],
      locktime: 0,
    );
    txBytes = tx.toBytes();
    txParsed = Transaction.fromBytes(txBytes);
    expect(txParsed.version, equals(tx.version));
    expect(txParsed.marker, equals(tx.marker));
    expect(txParsed.flag, equals(tx.flag));
    expect(txParsed.inputs.length, equals(0));
    expect(txParsed.outputs.length, equals(0));
    expect(txParsed.witness?.length, equals(0));
    expect(txParsed.locktime, equals(tx.locktime));
    txParsedBytes = txParsed.toBytes();
    expect(txParsedBytes, equals(txBytes));
    // legacy tx
    tx = Transaction(
      version: 1,
      inputs: [
        TxIn(
          txid: hexToBytes('0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'),
          vout: 1,
          scriptSig: hexToBytes('483045022100f3b1e5c8a2c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f901234567890abcdef01202206d7dbb42dcc78ba1661bb3106bb8ae1b424036592c0a16c9b51adcad46731eba01'),
          sequence: 0xffffffff,
        ),
      ],
      outputs: [
        TxOut(
          value: 10000,
          scriptPubKey: hexToBytes('76a9140a59837ccd4df25adc31cdad39be6a8d97557ed688ac'),
        ),
      ],
      witness: null,
      locktime: 0,
    );
    txBytes = tx.toBytes();
    txParsed = Transaction.fromBytes(txBytes);
    expect(txParsed.version, equals(tx.version));
    expect(txParsed.marker, equals(null));
    expect(txParsed.flag, equals(null));
    expect(txParsed.inputs.length, equals(tx.inputs.length));
    for (var i = 0; i < tx.inputs.length; i++) {
      expect(txParsed.inputs[i].txid, equals(tx.inputs[i].txid));
      expect(txParsed.inputs[i].vout, equals(tx.inputs[i].vout));
      expect(txParsed.inputs[i].scriptSig, equals(tx.inputs[i].scriptSig));
      expect(txParsed.inputs[i].sequence, equals(tx.inputs[i].sequence));
    }
    expect(txParsed.outputs.length, equals(tx.outputs.length));
    for (var i = 0; i < tx.outputs.length; i++) {
      expect(txParsed.outputs[i].value, equals(tx.outputs[i].value));
      expect(txParsed.outputs[i].scriptPubKey, equals(tx.outputs[i].scriptPubKey));
    }
    expect(txParsed.witness, equals(null));
    expect(txParsed.locktime, equals(tx.locktime));
    txParsedBytes = txParsed.toBytes();
    expect(txParsedBytes, equals(txBytes));
    // empty legacy tx
    tx = Transaction(
      version: 1,
      inputs: [],
      outputs: [],
      witness: null,
      locktime: 0,
    );
    txBytes = tx.toBytes();
    txParsed = Transaction.fromBytes(txBytes);
    expect(txParsed.version, equals(tx.version));
    expect(txParsed.marker, equals(null));
    expect(txParsed.flag, equals(null));
    expect(txParsed.inputs.length, equals(0));
    expect(txParsed.outputs.length, equals(0));
    expect(txParsed.witness, equals(null));
    expect(txParsed.locktime, equals(tx.locktime));
    txParsedBytes = txParsed.toBytes();
    expect(txParsedBytes, equals(txBytes));
  });
}
