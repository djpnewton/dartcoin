// ignore_for_file: avoid_relative_lib_imports

import 'dart:typed_data';

import 'package:test/test.dart';

import '../lib/src/bitcoin_core/core_process.dart';
import '../lib/src/common.dart';
import '../lib/src/address.dart';
import '../lib/src/block.dart';
import '../lib/src/block_filter.dart';
import '../lib/src/sign_tx.dart';
import '../lib/src/keys.dart';
import '../lib/src/mnemonic.dart';
import '../lib/src/transaction.dart';
import '../lib/src/utils.dart';

Future<List<TxOut>> _prevOutputs(
  List<TxIn> inputs,
  TxProvider txProvider,
) async {
  return await Future.wait(
    inputs.map((input) async {
      var prevTx = await txProvider.fromTxid(input.txid);
      return prevTx.outputs[input.vout];
    }),
  );
}

void main() {
  final dummyAddr1 = 'mgTgHVFXFdMEJiMmLhGrxu75waDYjCjDvN';
  late CoreProcess proc1;
  late PrivateKey masterKey;
  setUp(() async {
    // start the regtest process
    proc1 = CoreProcess(verbose: false, p2pPort: 18444, rpcPort: 18443);
    await proc1.start();
    await proc1.waitTillInitialized();
    // generate a mnemonic and master key
    final seed = mnemonicToSeed(
      'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about',
    );
    masterKey = PrivateKey.fromSeed(hexToBytes(seed));
  });
  tearDown(() async {
    // stop the regtest processes
    await proc1.stop();
  });

  test('signTransaction()', () async {
    // create legacy address
    final legacyAddr = masterKey.address(
      network: Network.regtest,
      scriptType: ScriptType.p2pkh,
    );
    // fund the address with a coinbase transaction
    final blockHashes = await proc1.rpc.generateToAddress(1, legacyAddr);
    expect(blockHashes.length, equals(1));
    final block1 = Block.fromBytes(
      hexToBytes(await proc1.rpc.getBlock(blockHashes[0], 0)),
    );
    expect(block1.transactions.length, equals(1));
    var coinbaseTx = block1.transactions[0];
    // create a segwit address
    final segwitAddr = masterKey.address(
      network: Network.regtest,
      scriptType: ScriptType.p2wpkh,
    );
    // create a transaction sending from legacy to segwit
    final fee = 500;
    final amountLegacyToSegwit = coinbaseTx.outputs[0].value - fee;
    final tx = Transaction(
      type: TxType.legacy,
      version: 1,
      inputs: [
        TxIn(
          txid: coinbaseTx.txid(),
          vout: 0,
          scriptSig: Uint8List(0),
          sequence: 0xffffffff,
        ),
      ],
      outputs: [
        TxOut(
          value: amountLegacyToSegwit,
          scriptPubKey: AddressData.parseAddress(segwitAddr).script,
        ),
      ],
      locktime: 0,
    );
    // sign the transaction
    final signedTx = signTransaction(
      tx: tx,
      privKeys: [masterKey],
      previousOutputs: [coinbaseTx.outputs[0]],
      fee: fee
    );
    // verify the transaction is correctly signed
    expect(
      verifyTransaction(tx: signedTx, previousOutputs: [coinbaseTx.outputs[0]]),
      isTrue,
    );
    // burn 100 blocks
    await proc1.rpc.generateToAddress(100, dummyAddr1);
    // broadcast the transaction and check it gets included in a block
    final txid = await proc1.rpc.sendRawTransaction(
      bytesToHex(signedTx.toBytes()),
    );
    expect(txid, equals(signedTx.txid()));
    final blockHashes2 = await proc1.rpc.generateToAddress(1, segwitAddr);
    final block2 = Block.fromBytes(
      hexToBytes(await proc1.rpc.getBlock(blockHashes2[0], 0)),
    );
    expect(
      block2.transactions.any((tx) => tx.txid() == signedTx.txid()),
      isTrue,
    );
    expect(block2.transactions.length, equals(2));
    coinbaseTx = block2.transactions[0];
    // create a transaction sending from segwit to legacy
    final amountSegwitToLegacy = amountLegacyToSegwit + coinbaseTx.outputs[0].value - fee;
    final tx2 = Transaction(
      type: TxType.segwit,
      version: 1,
      inputs: [
        TxIn(
          txid: signedTx.txid(),
          vout: 0,
          scriptSig: Uint8List(0),
          sequence: 0xffffffff,
          witness: TxWitness(stackItems: []),
        ),
        TxIn(
          txid: coinbaseTx.txid(),
          vout: 0,
          scriptSig: Uint8List(0),
          sequence: 0xffffffff,
          witness: TxWitness(stackItems: []),
        ),
      ],
      outputs: [
        TxOut(
          value: amountSegwitToLegacy,
          scriptPubKey: AddressData.parseAddress(legacyAddr).script,
        ),
      ],
      locktime: 0,
    );
    // sign the transaction
    final signedTx2 = signTransaction(
      tx: tx2,
      privKeys: [masterKey, masterKey],
      previousOutputs: [signedTx.outputs[0], coinbaseTx.outputs[0]],
      fee: fee,
    );
    // verify the transaction is correctly signed
    expect(
      verifyTransaction(
        tx: signedTx2,
        previousOutputs: [signedTx.outputs[0], coinbaseTx.outputs[0]],
      ),
      isTrue,
    );
    // burn 100 blocks
    await proc1.rpc.generateToAddress(100, dummyAddr1);
    // broadcast the transaction and check it gets included in a block
    final txid2 = await proc1.rpc.sendRawTransaction(
      bytesToHex(signedTx2.toBytes()),
    );
    expect(txid2, equals(signedTx2.txid()));
    final blockHashes3 = await proc1.rpc.generateToAddress(1, segwitAddr);
    final block3 = Block.fromBytes(
      hexToBytes(await proc1.rpc.getBlock(blockHashes3[0], 0)),
    );
    expect(
      block3.transactions.any((tx) => tx.txid() == signedTx2.txid()),
      isTrue,
    );
    expect(block3.transactions.length, equals(2));
    coinbaseTx = block3.transactions[0];
    // now to consolidate the funds back to segwit (to test segwit tx with one legacy input and one segwit input)
    final amountConsolidateToSegwit = amountSegwitToLegacy + coinbaseTx.outputs[0].value - fee;
    final tx3 = Transaction(
      type: TxType.segwit,
      version: 1,
      inputs: [
        TxIn(
          txid: signedTx2.txid(),
          vout: 0,
          scriptSig: Uint8List(0),
          sequence: 0xffffffff,
        ),
        TxIn(
          txid: coinbaseTx.txid(),
          vout: 0,
          scriptSig: Uint8List(0),
          sequence: 0xffffffff,
          witness: TxWitness(stackItems: []),
        ),
      ],
      outputs: [
        TxOut(
          value: amountConsolidateToSegwit,
          scriptPubKey: AddressData.parseAddress(segwitAddr).script,
        ),
      ],
      locktime: 0,
    );
    // sign the transaction
    final signedTx3 = signTransaction(
      tx: tx3,
      privKeys: [masterKey, masterKey],
      previousOutputs: [signedTx2.outputs[0], coinbaseTx.outputs[0]],
      fee: fee,
    );
    // verify the transaction is correctly signed
    expect(verifyTransaction(tx: signedTx3,previousOutputs: [signedTx2.outputs[0], coinbaseTx.outputs[0]],),isTrue,);
    // burn 100 blocks
    await proc1.rpc.generateToAddress(100, dummyAddr1);

    // broadcast the transaction and check it gets included in a block
    final txid3 = await proc1.rpc.sendRawTransaction(
      bytesToHex(signedTx3.toBytes()),
    );
    expect(txid3, equals(signedTx3.txid()));
    final blockHashes4 = await proc1.rpc.generateToAddress(1, segwitAddr);
    final block4 = Block.fromBytes(
      hexToBytes(await proc1.rpc.getBlock(blockHashes4[0], 0)),
    );
    expect(
      block4.transactions.any((tx) => tx.txid() == signedTx3.txid()),
      isTrue,
    );
    expect(block4.transactions.length, equals(2));
    coinbaseTx = block4.transactions[0];
  });

  test('verifyTransaction() - real txs', () async {
    var txProvider = BlockDnTxProvider(Network.testnet);

    // testnet3, legacy one input
    var tx = await txProvider.fromTxid(
      '681f4397d2aa7280306273885c04b4dd68878bc69a0e5cf5f9d476cc8acf99d0',
    );
    var previousOutputs = await _prevOutputs(tx.inputs, txProvider);
    expect(verifyTransaction(tx: tx, previousOutputs: previousOutputs), isTrue);

    // testnet3, legacy two inputs
    tx = await txProvider.fromTxid(
      '9ad77fff0dabfa0f585530cf8e20fecaf07ca2884a603a7c34d042db0fd3b751',
    );
    previousOutputs = await _prevOutputs(tx.inputs, txProvider);
    expect(verifyTransaction(tx: tx, previousOutputs: previousOutputs), isTrue);

    // testnet3, legacy three inputs
    tx = await txProvider.fromTxid(
      '6120c807ead93c1bfc244fe9f57fb873e367b59f3c6f26b79d6dfd8f178bc9ba',
    );
    previousOutputs = await _prevOutputs(tx.inputs, txProvider);
    expect(verifyTransaction(tx: tx, previousOutputs: previousOutputs), isTrue);

    txProvider = BlockDnTxProvider(Network.testnet4);

    // testnet4, segwit one input
    tx = await txProvider.fromTxid(
      'ca829b8f4c22cefbf798752e73fa9be26cd66ec8fa607c259614b8d212e58c59',
    );
    previousOutputs = await _prevOutputs(tx.inputs, txProvider);
    expect(verifyTransaction(tx: tx, previousOutputs: previousOutputs), isTrue);

    // testnet4, segwit two inputs
    tx = await txProvider.fromTxid(
      'cbc1d2e2abf85f9d0c5052b57c33f6bd82e29807b38606c1314ffec5a6a7e21e',
    );
    previousOutputs = await _prevOutputs(tx.inputs, txProvider);
    expect(verifyTransaction(tx: tx, previousOutputs: previousOutputs), isTrue);

    txProvider = BlockDnTxProvider(Network.mainnet);

    // mainnet, segwit 34 inputs (mixed P2WPKH and P2PKH)
    tx = await txProvider.fromTxid(
      'a03e43cfccddff3b47bdc94aa3851fcae23f9f023bb96a4e541ece6e5a326473',
    );
    previousOutputs = await _prevOutputs(tx.inputs, txProvider);
    expect(verifyTransaction(tx: tx, previousOutputs: previousOutputs), isTrue);
  });
}
