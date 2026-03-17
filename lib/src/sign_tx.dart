import 'dart:typed_data';

import 'package:collection/collection.dart';

import 'common.dart';
import 'utils.dart';
import 'keys.dart';
import 'sign_verify.dart';
import 'script.dart';
import 'transaction.dart';

// ignore: constant_identifier_names
const SIGHASH_ALL1 = '01';
// ignore: constant_identifier_names
const SIGHASH_ALL4 = '01000000';

Uint8List _legacyPreimageHash(
  Transaction tx,
  int inputIndex,
  List<TxOut> previousOutputs,
) {
  // 1) inputs with cleared scriptSigs and the scriptPubKey as a placeholder for the input being signed
  final inputs = tx.inputs.asMap().entries.map((entry) {
    final index = entry.key;
    final input = entry.value;
    if (index == inputIndex) {
      return TxIn(
        txid: input.txid,
        vout: input.vout,
        scriptSig: previousOutputs[inputIndex].scriptPubKey,
        sequence: input.sequence,
      );
    } else {
      return TxIn(
        txid: input.txid,
        vout: input.vout,
        scriptSig: Uint8List(0),
        sequence: input.sequence,
      );
    }
  }).toList();

  // 2) tmp tx with the modified inputs and the original outputs
  final tmpTx = Transaction(
    type: TxType.legacy,
    version: tx.version,
    inputs: inputs,
    outputs: tx.outputs,
    locktime: tx.locktime,
  );

  // 3) serialize the tmp tx and append the signature hash type
  var txBytes = tmpTx.toBytes();
  final sighash4 = hexToBytes(SIGHASH_ALL4);
  txBytes = Uint8List.fromList([...txBytes, ...sighash4]);

  // 4) hash the serialized tmp tx with appended sighash
  final hash = hash256(txBytes);

  return hash;
}

TxIn _signLegacyInput(
  Transaction tx,
  int inputIndex,
  List<TxOut> previousOutputs,
  List<PrivateKey> privKeys,
) {
  // 1) preimage hash
  final hash = _legacyPreimageHash(tx, inputIndex, previousOutputs);

  // 2) sign the hash (signature is low s by default) and encode the signature in DER format
  final signature = derSignHash(privKeys[inputIndex], hash);

  // 3) append the signature hash type to the DER-encoded signature
  final sighash1 = hexToBytes(SIGHASH_ALL1);
  final signatureWithSighash = Uint8List.fromList([
    ...signature.signature,
    ...sighash1,
  ]);

  // 4) make the scriptSig for the input being signed: OP_PUSHBYTES_70-72 [signature] OP_PUSHBYTES_33 [public key]
  assert(
    signatureWithSighash.length >= 70 && signatureWithSighash.length <= 72,
  );
  final pubkey = privKeys[inputIndex].publicKey;
  assert(pubkey.length == 33);
  final scriptSig = Uint8List.fromList([
    signatureWithSighash.length,
    ...signatureWithSighash,
    pubkey.length,
    ...pubkey,
  ]);

  // 5) set the scriptSig for the input being signed in the original transaction
  return TxIn(
    txid: tx.inputs[inputIndex].txid,
    vout: tx.inputs[inputIndex].vout,
    scriptSig: scriptSig,
    sequence: tx.inputs[inputIndex].sequence,
  );
}

Transaction _signTxLegacy({
  required Transaction tx,
  required List<PrivateKey> privKeys,
  required List<TxOut> previousOutputs,
}) {
  final txSigned = Transaction.fromBytes(tx.toBytes());

  for (var i = 0; i < tx.inputs.length; i++) {
    txSigned.inputs[i] = _signLegacyInput(
      txSigned,
      i,
      previousOutputs,
      privKeys,
    );
  }

  return txSigned;
}

bool _verifyLegacyInput(
  Transaction tx,
  int inputIndex,
  List<TxOut> previousOutputs,
) {
  // 1) preimage hash
  final hash = _legacyPreimageHash(tx, inputIndex, previousOutputs);

  // 2) extract the signature, sighash and pubkey from the scriptSig
  final scriptSig = tx.inputs[inputIndex].scriptSig;
  final signatureWithSighashLength = scriptSig[0];
  if (signatureWithSighashLength < 70 ||
      signatureWithSighashLength > 72 ||
      scriptSig.length != 1 + signatureWithSighashLength + 1 + 33) {
    return false;
  }
  final signatureWithSighash = scriptSig.sublist(
    1,
    1 + signatureWithSighashLength,
  );
  final pubkey = scriptSig.sublist(1 + signatureWithSighashLength + 1);
  if (pubkey.length != 33) {
    return false;
  }
  final signatureBytes = signatureWithSighash.sublist(
    0,
    signatureWithSighashLength - 1,
  );
  final sighashBytes = signatureWithSighash.sublist(
    signatureWithSighashLength - 1,
  );
  if (bytesToHex(sighashBytes) != SIGHASH_ALL1) {
    return false; // Only SIGHASH_ALL is supported in this implementation
  }

  // 3) verify the signature
  final pk = PublicKey.fromPublicKey(pubkey);
  if (!derVerifyHash(pk, hash, signatureBytes)) {
    return false;
  }
  return true;
}

bool _verifyTxLegacy({
  required Transaction tx,
  required List<TxOut> previousOutputs,
}) {
  for (var i = 0; i < tx.inputs.length; i++) {
    if (!_verifyLegacyInput(tx, i, previousOutputs)) return false;
  }

  return true;
}

Uint8List _segwitPreimageHash(
  Transaction tx,
  int inputIndex,
  List<TxOut> previousOutputs,
) {
  // 1) version field
  final versionBytes = (ByteData(
    4,
  )..setUint32(0, tx.version, Endian.little)).buffer.asUint8List();

  // 2) hash prevouts (txid + vout for all inputs)
  final prevoutsBytes = tx.inputs.expand((input) {
    final voutBytes = ByteData(4)..setUint32(0, input.vout, Endian.little);
    return [...input.txid, ...voutBytes.buffer.asUint8List()];
  }).toList();
  final prevoutsHash = hash256(Uint8List.fromList(prevoutsBytes));

  // 3) hash sequence (sequence for all inputs)
  final sequenceBytes = tx.inputs.expand((input) {
    final seqBytes = ByteData(4)..setUint32(0, input.sequence, Endian.little);
    return seqBytes.buffer.asUint8List();
  }).toList();
  final sequenceHash = hash256(Uint8List.fromList(sequenceBytes));

  // 4) prevout (txid + vout for the input being signed)
  final voutBytes = ByteData(4)
    ..setUint32(0, tx.inputs[inputIndex].vout, Endian.little);
  final prevoutBytes = [
    ...tx.inputs[inputIndex].txid,
    ...voutBytes.buffer.asUint8List(),
  ];

  // 5) scriptCode
  final scriptPubKey = previousOutputs[inputIndex].scriptPubKey;
  final spkMatch = matchScriptPubKey(scriptPubKey);
  assert(
    spkMatch.scriptType == ScriptType.p2wpkh ||
        spkMatch.scriptType == ScriptType.p2pkh,
  );
  assert(spkMatch.payload.length == 20);
  final pubkeyHash = spkMatch.payload;
  final scriptCode = Uint8List.fromList([
    0x19,
    0x76,
    0xa9,
    0x14,
    ...pubkeyHash,
    0x88,
    0xac,
  ]);

  // 6) value
  final valueBytes = ByteData(8)
    ..setInt64(0, previousOutputs[inputIndex].value, Endian.little);

  // 7) input sequence
  final inputSequenceBytes = ByteData(4)
    ..setUint32(0, tx.inputs[inputIndex].sequence, Endian.little);

  // 8) hash outputs (value + scriptPubKey for all outputs)
  final outputsBytes = tx.outputs.expand((output) {
    final valueBytes = ByteData(8)..setInt64(0, output.value, Endian.little);
    final scriptPubKeySize = compactSize(output.scriptPubKey.length);
    final scriptPubKeyBytes = output.scriptPubKey;
    return [
      ...valueBytes.buffer.asUint8List(),
      ...scriptPubKeySize,
      ...scriptPubKeyBytes,
    ];
  }).toList();
  final outputsHash = hash256(Uint8List.fromList(outputsBytes));

  // 9) locktime
  final locktimeBytes = ByteData(4)..setUint32(0, tx.locktime, Endian.little);

  // 10) sighash type
  final sighash4 = hexToBytes(SIGHASH_ALL4);

  // 11) preimage
  final preimageBytes = [
    ...versionBytes,
    ...prevoutsHash,
    ...sequenceHash,
    ...prevoutBytes,
    ...scriptCode,
    ...valueBytes.buffer.asUint8List(),
    ...inputSequenceBytes.buffer.asUint8List(),
    ...outputsHash,
    ...locktimeBytes.buffer.asUint8List(),
    ...sighash4,
  ];

  // 12) preimage hash
  final preimageHash = hash256(Uint8List.fromList(preimageBytes));

  return preimageHash;
}

Transaction _signTxSegwit({
  required Transaction tx,
  required List<PrivateKey> privKeys,
  required List<TxOut> previousOutputs,
}) {
  final txSigned = Transaction.fromBytes(tx.toBytes());

  for (var i = 0; i < tx.inputs.length; i++) {
    if (tx.inputs[i].isSegwit()) {
      // 1) preimage hash
      final preimageHash = _segwitPreimageHash(tx, i, previousOutputs);

      // 2) sign the preimage hash and encode the signature in DER format
      final signature = derSignHash(privKeys[i], preimageHash);

      // 3) append the signature hash type to the DER-encoded signature
      final sighash1 = hexToBytes(SIGHASH_ALL1);
      final signatureWithSighash = Uint8List.fromList([
        ...signature.signature,
        ...sighash1,
      ]);

      // 4) set the witness for the input being signed: [signature] [public key]
      final pubkey = privKeys[i].publicKey;
      assert(pubkey.length == 33);
      assert(txSigned.witness?.length == tx.inputs.length);
      final witness = TxWitness(
        stackItems: [
          WitnessStackItem(signatureWithSighash),
          WitnessStackItem(pubkey),
        ],
      );
      txSigned.witness?[i] = witness;
      txSigned.inputs[i] = TxIn(
        txid: tx.inputs[i].txid,
        vout: tx.inputs[i].vout,
        scriptSig: tx.inputs[i].scriptSig,
        sequence: tx.inputs[i].sequence,
        witness: witness,
      );
    } else {
      txSigned.inputs[i] = _signLegacyInput(
        txSigned,
        i,
        previousOutputs,
        privKeys,
      );
    }
  }

  return txSigned;
}

bool _verifyTxSegwit({
  required Transaction tx,
  required List<TxOut> previousOutputs,
}) {
  for (var i = 0; i < tx.inputs.length; i++) {
    if (tx.inputs[i].isSegwit()) {
      // 1) preimage hash
      final preimageHash = tx.inputs[i].isSegwit()
          ? _segwitPreimageHash(tx, i, previousOutputs)
          : _legacyPreimageHash(tx, i, previousOutputs);

      // 2) extract the signature, sighash and pubkey from the witness
      final witness = tx.witness?[i];
      if (witness == null || witness.stackItems.length != 2) return false;
      final signatureWithSighash = witness.stackItems[0].data;
      final pubkey = witness.stackItems[1].data;
      if (signatureWithSighash.length < 70 ||
          signatureWithSighash.length > 72 ||
          pubkey.length != 33) {
        return false;
      }
      final signatureBytes = signatureWithSighash.sublist(
        0,
        signatureWithSighash.length - 1,
      );
      final sighashBytes = signatureWithSighash.sublist(
        signatureWithSighash.length - 1,
      );
      if (bytesToHex(sighashBytes) != SIGHASH_ALL1) return false;

      // 3) verify the signature
      final pk = PublicKey.fromPublicKey(pubkey);
      if (!derVerifyHash(pk, preimageHash, signatureBytes)) {
        return false;
      }
    } else {
      if (!_verifyLegacyInput(tx, i, previousOutputs)) {
        return false;
      }
    }
  }

  return true;
}

Transaction signTransaction({
  required Transaction tx,
  required List<PrivateKey> privKeys,
  required List<TxOut> previousOutputs,
  required int fee,
}) {
  if (privKeys.length != tx.inputs.length ||
      previousOutputs.length != tx.inputs.length) {
    throw ArgumentError(
      'Length of privKeys and previousOutputs must match the number of inputs in the transaction',
    );
  }

  // get prevous outputs total value for fee check
  final totalInputValue = previousOutputs.map((output) => output.value).sum;
  final totalOutputValue = tx.outputs.map((output) => output.value).sum;
  if (totalOutputValue > totalInputValue) {
    throw ArgumentError(
      'Total output value cannot exceed total input value. Total input value: $totalInputValue, total output value: $totalOutputValue',
    );
  }
  final calculatedFee = totalInputValue - totalOutputValue;
  if (calculatedFee != fee) {
    throw ArgumentError(
      'Calculated fee does not match the provided fee. Calculated fee: $calculatedFee, provided fee: $fee',
    );
  }

  switch (tx.type()) {
    case TxType.legacy:
      if (tx.inputs.any((input) => input.isSegwit())) {
        throw ArgumentError('Legacy transaction cannot have segwit inputs');
      }
      return _signTxLegacy(
        tx: tx,
        privKeys: privKeys,
        previousOutputs: previousOutputs,
      );
    case TxType.segwit:
      if (tx.inputs.none((input) => input.isSegwit())) {
        throw ArgumentError(
          'Segwit transaction must have at least one segwit input',
        );
      }
      return _signTxSegwit(
        tx: tx,
        privKeys: privKeys,
        previousOutputs: previousOutputs,
      );
  }
}

bool verifyTransaction({
  required Transaction tx,
  required List<TxOut> previousOutputs,
}) {
  if (previousOutputs.length != tx.inputs.length) {
    throw ArgumentError(
      'Length of previousOutputs must match the number of inputs in the transaction',
    );
  }

  switch (tx.type()) {
    case TxType.legacy:
      return _verifyTxLegacy(tx: tx, previousOutputs: previousOutputs);
    case TxType.segwit:
      return _verifyTxSegwit(tx: tx, previousOutputs: previousOutputs);
  }
}
