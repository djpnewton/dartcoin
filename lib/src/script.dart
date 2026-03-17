import 'dart:typed_data';

import 'common.dart';

Uint8List? matchP2pkh(Uint8List scriptPubKey) {
  if (scriptPubKey.length == 25 &&
      scriptPubKey[0] == 0x76 && // OP_DUP
      scriptPubKey[1] == 0xa9 && // OP_HASH160
      scriptPubKey[2] == 0x14 && // Push 20 bytes
      scriptPubKey[23] == 0x88 && // OP_EQUALVERIFY
      scriptPubKey[24] == 0xac) {
    // OP_CHECKSIG
    return scriptPubKey.sublist(3, 23); // Return the 20-byte hash
  }
  return null;
}

Uint8List? matchP2sh(Uint8List scriptPubKey) {
  if (scriptPubKey.length == 23 &&
      scriptPubKey[0] == 0xa9 && // OP_HASH160
      scriptPubKey[1] == 0x14 && // Push 20 bytes
      scriptPubKey[22] == 0x87) {
    // OP_EQUAL
    return scriptPubKey.sublist(2, 22); // Return the 20-byte hash
  }
  return null;
}

Uint8List? matchP2wpkh(Uint8List scriptPubKey) {
  if (scriptPubKey.length == 22 &&
      scriptPubKey[0] == 0x00 && // OP_0
      scriptPubKey[1] == 0x14) {
    // Push 20 bytes
    return scriptPubKey.sublist(2, 22); // Return the 20-byte hash
  }
  return null;
}

Uint8List? matchP2wsh(Uint8List scriptPubKey) {
  if (scriptPubKey.length == 34 &&
      scriptPubKey[0] == 0x00 && // OP_0
      scriptPubKey[1] == 0x20) {
    // Push 32 bytes
    return scriptPubKey.sublist(2, 34); // Return the 32-byte hash
  }
  return null;
}

class ScriptPubKeyMatch {
  final ScriptType scriptType;
  final Uint8List payload;

  const ScriptPubKeyMatch({required this.scriptType, required this.payload});
}

ScriptPubKeyMatch matchScriptPubKey(Uint8List scriptPubKey) {
  final pubkeyHash = matchP2pkh(scriptPubKey);
  if (pubkeyHash != null) {
    return ScriptPubKeyMatch(scriptType: ScriptType.p2pkh, payload: pubkeyHash);
  }
  final scriptHash = matchP2sh(scriptPubKey);
  if (scriptHash != null) {
    return ScriptPubKeyMatch(scriptType: ScriptType.p2sh, payload: scriptHash);
  }
  final witnessPubkeyHash = matchP2wpkh(scriptPubKey);
  if (witnessPubkeyHash != null) {
    return ScriptPubKeyMatch(
      scriptType: ScriptType.p2wpkh,
      payload: witnessPubkeyHash,
    );
  }
  final witnessScriptHash = matchP2wsh(scriptPubKey);
  if (witnessScriptHash != null) {
    return ScriptPubKeyMatch(
      scriptType: ScriptType.p2wsh,
      payload: witnessScriptHash,
    );
  }
  throw ArgumentError('Unsupported or unrecognized script pubkey format');
}
