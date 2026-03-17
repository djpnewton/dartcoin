import 'dart:convert';
import 'dart:typed_data';

import 'utils.dart';

class TxIn {
  final Uint8List txid;
  final int vout;
  final Uint8List scriptSig;
  final int sequence;
  final TxWitness? witness;

  TxIn({
    required this.txid,
    required this.vout,
    required this.scriptSig,
    required this.sequence,
    this.witness,
  });

  bool isSegwit() {
    return witness != null;
  }

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    buffer.add(txid);
    buffer.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, vout, Endian.little),
    );
    final scriptSigSize = compactSize(scriptSig.length);
    buffer.add(scriptSigSize);
    buffer.add(scriptSig);
    buffer.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, sequence, Endian.little),
    );
    return buffer.toBytes();
  }

  factory TxIn.fromBytes(Uint8List bytes) {
    if (bytes.length < 42) {
      throw FormatException('TxIn bytes must be at least 42 bytes long');
    }
    var i = 0;
    final buffer = ByteData.sublistView(bytes);
    final txid = bytes.sublist(i, 32);
    i += 32;
    final vout = buffer.getUint32(i, Endian.little);
    i += 4;
    final cspr = compactSizeParse(bytes.sublist(i));
    final scriptSigSize = cspr.value;
    i += cspr.bytesRead;
    if (i + scriptSigSize > bytes.length) {
      throw FormatException('ScriptSigSize exceeds remaining bytes');
    }
    final scriptSig = bytes.sublist(i, i + scriptSigSize);
    i += scriptSigSize;
    if (i + 4 > bytes.length) {
      throw FormatException('Sequence length exceeds remaining bytes');
    }
    final sequence = buffer.getUint32(i, Endian.little);
    return TxIn(
      txid: txid,
      vout: vout,
      scriptSig: scriptSig,
      sequence: sequence,
    );
  }

  String toJson() {
    return '''{
      "txid": "${txid.toHex()}",
      "vout": $vout,
      "scriptSig": "${scriptSig.toHex()}",
      "sequence": $sequence,
      "witness": ${witness != null ? witness!.toJson() : 'null'}
    }''';
  }

  factory TxIn.fromJson(String json) {
    final data = jsonDecode(json);
    return TxIn(
      txid: hexToBytes(data['txid'] as String),
      vout: data['vout'] as int,
      scriptSig: hexToBytes(data['scriptSig'] as String),
      sequence: data['sequence'] as int,
      witness: data['witness'] != null
          ? TxWitness.fromJson(data['witness'] as String)
          : null,
    );
  }
}

class TxOut {
  final int value;
  final Uint8List scriptPubKey;

  TxOut({required this.value, required this.scriptPubKey});

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    buffer.add(setUint64JsSafe(value, endian: Endian.little));
    final scriptPubKeySize = compactSize(scriptPubKey.length);
    buffer.add(scriptPubKeySize);
    buffer.add(scriptPubKey);
    return buffer.toBytes();
  }

  factory TxOut.fromBytes(Uint8List bytes) {
    if (bytes.length < 10) {
      throw FormatException('TxOut bytes must be at least 10 bytes long');
    }
    var i = 0;
    final value = getUint64JsSafe(
      bytes.sublist(i, i + 8),
      endian: Endian.little,
    );
    i += 8;
    final cspr = compactSizeParse(bytes.sublist(i));
    final scriptPubKeySize = cspr.value;
    i += cspr.bytesRead;
    if (i + scriptPubKeySize > bytes.length) {
      throw FormatException('ScriptPubKeySize exceeds remaining bytes');
    }
    final scriptPubKey = bytes.sublist(i, i + scriptPubKeySize);
    return TxOut(value: value, scriptPubKey: scriptPubKey);
  }

  String toJson() {
    return '''{
      "value": $value,
      "scriptPubKey": "${scriptPubKey.toHex()}"
    }''';
  }

  factory TxOut.fromJson(String json) {
    final data = jsonDecode(json);
    return TxOut(
      value: data['value'] as int,
      scriptPubKey: hexToBytes(data['scriptPubKey'] as String),
    );
  }
}

class WitnessStackItem {
  Uint8List data;

  WitnessStackItem(this.data);

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    final size = compactSize(data.length);
    buffer.add(size);
    buffer.add(data);
    return buffer.toBytes();
  }

  factory WitnessStackItem.fromBytes(Uint8List bytes) {
    final cspr = compactSizeParse(bytes);
    final data = bytes.sublist(cspr.bytesRead, cspr.bytesRead + cspr.value);
    return WitnessStackItem(data);
  }

  String toJson() {
    return '''{
      "data": "${data.toHex()}"
    }''';
  }

  factory WitnessStackItem.fromJson(String json) {
    final data = jsonDecode(json);
    return WitnessStackItem(hexToBytes(data['data'] as String));
  }
}

class TxWitness {
  List<WitnessStackItem> stackItems;

  TxWitness({required this.stackItems});

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    final count = compactSize(stackItems.length);
    buffer.add(count);
    for (final item in stackItems) {
      buffer.add(item.toBytes());
    }
    return buffer.toBytes();
  }

  factory TxWitness.fromBytes(Uint8List bytes) {
    final cspr = compactSizeParse(bytes);
    final stackItems = <WitnessStackItem>[];
    var offset = cspr.bytesRead;
    for (var i = 0; i < cspr.value; i++) {
      final item = WitnessStackItem.fromBytes(bytes.sublist(offset));
      stackItems.add(item);
      offset += item.toBytes().length;
    }
    return TxWitness(stackItems: stackItems);
  }

  String toJson() {
    final itemsJson = stackItems.map((item) => item.toJson()).join(', ');
    return '''{
      "stackItems": [$itemsJson]
    }''';
  }

  factory TxWitness.fromJson(String json) {
    final data = jsonDecode(json);
    final stackItems = (data['stackItems'] as List)
        .map((item) => WitnessStackItem.fromJson(item as String))
        .toList();
    return TxWitness(stackItems: stackItems);
  }
}

enum TxType { legacy, segwit }

class Transaction {
  int version;
  int? marker;
  int? flag;
  List<TxIn> inputs;
  List<TxOut> outputs;
  List<TxWitness>? witness;
  int locktime;

  Transaction({
    TxType? type,
    required this.version,
    this.marker,
    this.flag,
    required this.inputs,
    required this.outputs,
    this.witness,
    required this.locktime,
  }) {
    if (type == TxType.legacy) {
      if (marker != null) {
        throw ArgumentError('Legacy transactions must not have a marker');
      }
      if (flag != null) {
        throw ArgumentError('Legacy transactions must not have a flag');
      }
      if (witness != null) {
        throw ArgumentError('Legacy transactions must not have witness data');
      }
    }
    if (type == TxType.segwit) {
      if (marker != null && marker != 0x00) {
        throw ArgumentError('Segwit transactions must have marker 0x00');
      }
      if (flag != null && flag != 0x01) {
        throw ArgumentError('Segwit transactions must have flag 0x01');
      }
      marker = 0x00;
      flag = 0x01;
    }
  }

  String wtxid() {
    return hash256(toBytes()).reversed.toList().toHex();
  }

  String txid() {
    if (type() == TxType.legacy) {
      return wtxid();
    }
    // txid excludes the marker/flag and witness data
    final buffer = BytesBuilder();
    buffer.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, version, Endian.little),
    );
    final inputsSize = compactSize(inputs.length);
    buffer.add(inputsSize);
    for (final input in inputs) {
      buffer.add(input.toBytes());
    }
    final outputsSize = compactSize(outputs.length);
    buffer.add(outputsSize);
    for (final output in outputs) {
      buffer.add(output.toBytes());
    }
    buffer.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, locktime, Endian.little),
    );
    return hash256(buffer.toBytes()).reversed.toList().toHex();
  }

  TxType type() {
    final t = (marker == 0x00 && flag == 0x01) ? TxType.segwit : TxType.legacy;
    if (t == TxType.legacy) {
      for (final input in inputs) {
        if (input.isSegwit()) {
          throw FormatException('Legacy transaction cannot have segwit inputs');
        }
      }
    }
    return t;
  }

  Uint8List toBytes() {
    final buffer = BytesBuilder();
    buffer.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, version, Endian.little),
    );
    if (marker != null && flag != null) {
      buffer.add(Uint8List.fromList([marker!, flag!]));
    }
    final inputsSize = compactSize(inputs.length);
    buffer.add(inputsSize);
    for (final input in inputs) {
      buffer.add(input.toBytes());
    }
    final outputsSize = compactSize(outputs.length);
    buffer.add(outputsSize);
    for (final output in outputs) {
      buffer.add(output.toBytes());
    }
    if (witness != null) {
      for (final w in witness!) {
        buffer.add(w.toBytes());
      }
    } else if (type() == TxType.segwit) {
      // if segwit, we need to add an empty witness for each input
      for (var i = 0; i < inputs.length; i++) {
        buffer.add(TxWitness(stackItems: []).toBytes());
      }
    }
    buffer.add(
      Uint8List(4)..buffer.asByteData().setUint32(0, locktime, Endian.little),
    );
    return buffer.toBytes();
  }

  factory Transaction.fromBytes(Uint8List bytes) {
    if (bytes.length < 10) {
      throw FormatException('Transaction bytes must be at least 10 bytes long');
    }
    var i = 0;
    final buffer = ByteData.sublistView(bytes);
    final version = buffer.getUint32(i, Endian.little);
    i += 4;
    // check for marker and flag (segwit transactions)
    int? marker;
    int? flag;
    if (bytes[i] == 0x00 && bytes[i + 1] == 0x01) {
      marker = bytes[i];
      flag = bytes[i + 1];
      i += 2;
    }
    // read inputs
    final csprInputs = compactSizeParse(bytes.sublist(i));
    i += csprInputs.bytesRead;
    final inputs = <TxIn>[];
    for (var j = 0; j < csprInputs.value; j++) {
      final input = TxIn.fromBytes(bytes.sublist(i));
      inputs.add(input);
      i += input.toBytes().length;
    }
    // read outputs
    final csprOutputs = compactSizeParse(bytes.sublist(i));
    i += csprOutputs.bytesRead;
    final outputs = <TxOut>[];
    for (var j = 0; j < csprOutputs.value; j++) {
      final output = TxOut.fromBytes(bytes.sublist(i));
      outputs.add(output);
      i += output.toBytes().length;
    }
    // read witness if present
    List<TxWitness>? witness;
    if (marker != null && flag != null) {
      witness = [];
      for (var j = 0; j < inputs.length; j++) {
        final witnessField = TxWitness.fromBytes(bytes.sublist(i));
        i += witnessField.toBytes().length;
        witness.add(witnessField);
        inputs[j] = TxIn(
          txid: inputs[j].txid,
          vout: inputs[j].vout,
          scriptSig: inputs[j].scriptSig,
          sequence: inputs[j].sequence,
          witness: witnessField.stackItems.isNotEmpty ? witnessField : null,
        );
      }
    }
    // read locktime
    if (i + 4 > bytes.length) {
      throw FormatException(
        'Locktime ($i-${i + 4}) exceeds remaining bytes (${bytes.length})',
      );
    }
    final locktime = buffer.getUint32(i, Endian.little);

    return Transaction(
      version: version,
      marker: marker,
      flag: flag,
      inputs: inputs,
      outputs: outputs,
      witness: witness,
      locktime: locktime,
    );
  }

  String toJson() {
    final inputsJson = inputs.map((input) => input.toJson()).join(', ');
    final outputsJson = outputs.map((output) => output.toJson()).join(', ');
    var witnessJson = 'null';
    if (type() == TxType.segwit) {
      if (witness != null) {
        witnessJson = witness!.map((w) => w.toJson()).join(', ');
      } else {
        witnessJson = inputs.map((_) => '[]').join(', ');
      }
      witnessJson = '[$witnessJson]';
    }
    return '''{
      "type": "${type().toString().split('.').last}",
      "txid": "${txid()}",
      "version": $version,
      "marker": ${marker ?? 'null'},
      "flag": ${flag ?? 'null'},
      "inputs": [$inputsJson],
      "outputs": [$outputsJson],
      "witness": $witnessJson,
      "locktime": $locktime,
    }''';
  }

  factory Transaction.fromJson(String json) {
    final data = jsonDecode(json);
    final inputs = (data['inputs'] as List)
        .map((input) => TxIn.fromJson(input as String))
        .toList();
    final outputs = (data['outputs'] as List)
        .map((output) => TxOut.fromJson(output as String))
        .toList();
    List<TxWitness> witness = [];
    if (data['witness'] != null) {
      witness = (data['witness'] as List)
          .map((w) => TxWitness.fromJson(w as String))
          .toList();
    }
    return Transaction(
      version: data['version'] as int,
      marker: data['marker'] as int?,
      flag: data['flag'] as int?,
      inputs: inputs,
      outputs: outputs,
      witness: witness,
      locktime: data['locktime'] as int,
    );
  }
}
