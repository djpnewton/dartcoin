import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:args/command_runner.dart';
import 'package:logging/logging.dart';

import 'package:dartcoin/dartcoin.dart';

final _log = Logger('main');

void initLogger() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
}

class ExampleCommand extends Command<void> {
  @override
  final name = 'example';
  @override
  final description = 'An example command to demonstrate key generation.';

  ExampleCommand();

  @override
  void run() {
    final mnemonic =
        'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
    _log.info('Mnemonic words: $mnemonic');

    _log.info('Validating mnemonic: ${mnemonicValid(mnemonic)}');

    final seed = mnemonicToSeed(mnemonic);
    _log.info('Seed (hex): $seed');

    final masterKey = PrivateKey.fromSeed(hexToBytes(seed));
    _log.info('Master Extended Key:');
    _log.info('  Private Key: ${bytesToHex(masterKey.privateKey)}');
    _log.info('  Public Key:  ${bytesToHex(masterKey.publicKey)}');
    _log.info('  Chain Code:  ${bytesToHex(masterKey.chainCode)}');

    final childKey = masterKey.childPrivateKey(0x80000000, hardened: true);
    _log.info('Child Extended Key m/0\':');
    _log.info('  Private Key:  ${bytesToHex(childKey.privateKey)}');
    _log.info('  Public Key:   ${bytesToHex(childKey.publicKey)}');
    _log.info('  Chain Code:   ${bytesToHex(childKey.chainCode)}');
    _log.info('  Depth:        ${intToHex(childKey.depth)}');
    _log.info('  Parent Fingerprint: ${intToHex(childKey.parentFingerprint)}');
    _log.info('  Child Number: ${intToHex(childKey.childNumber)}');
    final xprv = childKey.xprv();
    _log.info('  xprv: $xprv');
    final childKeyParsed = PrivateKey.fromXPrv(xprv);
    _log.info('Parsed Child Extended Key:');
    _log.info('  Private Key:  ${bytesToHex(childKeyParsed.privateKey)}');
    _log.info('  Public Key:   ${bytesToHex(childKeyParsed.publicKey)}');
    _log.info('  Chain Code:   ${bytesToHex(childKeyParsed.chainCode)}');
    _log.info('  Depth:        ${intToHex(childKeyParsed.depth)}');
    _log.info(
      '  Parent Fingerprint: ${intToHex(childKeyParsed.parentFingerprint)}',
    );
    _log.info('  Child Number: ${intToHex(childKeyParsed.childNumber)}');

    final childPubKey = masterKey.childPublicKey(1);
    _log.info('Child Public Key m/1:');
    _log.info('  Public Key:   ${bytesToHex(childPubKey.publicKey)}');
    _log.info('  Chain Code:   ${bytesToHex(childPubKey.chainCode)}');
    _log.info('  Depth:        ${intToHex(childPubKey.depth)}');
    _log.info(
      '  Parent Fingerprint: ${intToHex(childPubKey.parentFingerprint)}',
    );
    _log.info('  Child Number: ${intToHex(childPubKey.childNumber)}');
    final xpub = childPubKey.xpub();
    _log.info('  xpub: $xpub');
    final childPubKeyParsed = PublicKey.fromXPub(xpub);
    _log.info('Parsed Child Public Key:');
    _log.info('  Public Key:   ${bytesToHex(childPubKeyParsed.publicKey)}');
    _log.info('  Chain Code:   ${bytesToHex(childPubKeyParsed.chainCode)}');
    _log.info('  Depth:        ${intToHex(childPubKeyParsed.depth)}');
    _log.info(
      '  Parent Fingerprint: ${intToHex(childPubKeyParsed.parentFingerprint)}',
    );
    _log.info('  Child Number: ${intToHex(childPubKeyParsed.childNumber)}');

    var address = childPubKey.address(network: Network.mainnet);
    _log.info('P2PKH Address (m/1): $address');
    address = childPubKey.address(network: Network.testnet);
    _log.info('P2PKH Address (m/1) Testnet: $address');
    address = childPubKey.address(
      network: Network.mainnet,
      scriptType: ScriptType.p2shP2wpkh,
    );
    _log.info('P2SH-P2WPKH Address (m/1): $address');
    address = childPubKey.address(
      network: Network.testnet,
      scriptType: ScriptType.p2shP2wpkh,
    );
    _log.info('P2SH-P2WPKH Address (m/1) Testnet: $address');
    address = childPubKey.address(
      network: Network.mainnet,
      scriptType: ScriptType.p2wpkh,
    );
    _log.info('P2WPKH Address (m/1): $address');
    address = childPubKey.address(
      network: Network.testnet,
      scriptType: ScriptType.p2wpkh,
    );
    _log.info('P2WPKH Address (m/1) Testnet: $address');
  }
}

class SignCommand extends Command<void> {
  @override
  final name = 'sign';
  @override
  final description = 'Sign a message with a private key.';

  SignCommand() {
    argParser.addOption(
      'private-key',
      abbr: 'p',
      help:
          'The private key filename (single line file in hex/WIF/xpriv format).',
      mandatory: true,
    );
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The message to sign as a utf8 string',
      mandatory: true,
    );
    argParser.addOption(
      'type',
      abbr: 't',
      help: 'The type of signature to create.',
      allowed: ['bitcoin-signmessage', 'DER'],
      defaultsTo: 'bitcoin-signmessage',
      allowedHelp: {
        'bitcoin-signmessage':
            'Create a signature for a Bitcoin signed message.',
        'DER': 'Create a DER formatted signature.',
      },
    );
    argParser.addOption(
      'network',
      abbr: 'n',
      help: 'The Bitcoin network to use for bitcoin-signmessage signing.',
      allowed: ['mainnet', 'testnet'],
      defaultsTo: 'mainnet',
      allowedHelp: {
        'mainnet': 'Use the main Bitcoin network.',
        'testnet': 'Use the Bitcoin test network.',
      },
    );
    argParser.addOption(
      'script-type',
      abbr: 's',
      help: 'The script type for bitcoin-signmessage.',
      allowed: ['p2pkh', 'p2shP2wpkh', 'p2wpkh'],
      defaultsTo: 'p2pkh',
      allowedHelp: {
        'p2pkh': 'Pay-to-Public-Key-Hash (P2PKH) script type.',
        'p2shP2wpkh':
            'Pay-to-Script-Hash wrapped Pay-to-Witness-Public-Key-Hash.',
        'p2wpkh': 'Pay-to-Witness-Public-Key-Hash (P2WPKH) script type.',
      },
    );
  }

  @override
  void run() {
    final pkFilename = argResults?.option('private-key');
    final message = argResults?.option('message');
    if (pkFilename == null || message == null) {
      // should not happen due to mandatory options, but just in case
      _log.info(
        'Please provide both a private key filename and a message to sign.',
      );
      return;
    }
    // load private key from file
    String pkRaw;
    if (!File(pkFilename).existsSync()) {
      _log.info('Private key file not found: $pkFilename');
      return;
    }
    try {
      pkRaw = File(pkFilename).readAsStringSync().trim();
      if (pkRaw.isEmpty) {
        _log.info('Private key file is empty: $pkFilename');
        return;
      }
    } catch (e) {
      _log.info('Error reading private key file: $pkFilename');
      return;
    }
    // load private key from hex, WIF, or xpriv
    PrivateKey pk;
    try {
      final pkBytes = hexToBytes(pkRaw);
      pk = PrivateKey.fromPrivateKey(pkBytes);
    } catch (e) {
      // If the private key is not in hex format, try WIF or xpriv
      try {
        pk = PrivateKey.fromWif(pkRaw);
      } catch (e) {
        try {
          pk = PrivateKey.fromXPrv(pkRaw);
        } catch (e) {
          _log.info('Invalid private key format: $pkRaw');
          return;
        }
      }
    }
    final type = argResults?.option('type') ?? 'bitcoin-signmessage';
    if (type == 'DER') {
      // sign the message hash in DER format
      final signature = derSign(pk, utf8.encode(message));
      // print the signature in hex format
      _log.info('Public Key: ${bytesToHex(signature.publicKey)}');
      _log.info('Signature (DER): ${bytesToHex(signature.signature)}');
    } else if (type == 'bitcoin-signmessage') {
      // get the network and script type
      final network = switch (argResults?.option('network')) {
        'mainnet' => Network.mainnet,
        'testnet' => Network.testnet,
        _ => throw ArgumentError('Invalid network type.'),
      };
      final scriptType = switch (argResults?.option('script-type')) {
        'p2pkh' => ScriptType.p2pkh,
        'p2shP2wpkh' => ScriptType.p2shP2wpkh,
        'p2wpkh' => ScriptType.p2wpkh,
        _ => throw ArgumentError('Invalid script type.'),
      };
      // sign the message hash
      final signature = bitcoinSignedMessageSign(
        pk,
        utf8.encode(message),
        network,
        scriptType,
      );
      // print the signature
      _log.info('Address: ${signature.address}');
      _log.info('Signature: ${signature.signature}');
    }
  }
}

class VerifyCommand extends Command<void> {
  @override
  final name = 'verify';
  @override
  final description = 'Verify a signed message with a public key.';

  VerifyCommand() {
    argParser.addOption(
      'public-key',
      abbr: 'p',
      help: 'The public key in hex format. Or a Bitcoin address.',
      mandatory: true,
    );
    argParser.addOption(
      'message',
      abbr: 'm',
      help: 'The original message that was signed.',
      mandatory: true,
    );
    argParser.addOption(
      'signature',
      abbr: 's',
      help: 'The signature to verify.',
      mandatory: true,
    );
  }

  @override
  void run() {
    final pubKeyRaw = argResults?.option('public-key');
    final message = argResults?.option('message');
    final signature = argResults?.option('signature');
    if (pubKeyRaw == null || message == null || signature == null) {
      _log.info(
        'Please provide a public key, message, and signature to verify.',
      );
      return;
    }
    try {
      // check if valid public key
      final pubKeyBytes = hexToBytes(pubKeyRaw);
      final pk = PublicKey.fromPublicKey(pubKeyBytes);
      // verify the signature
      final result = derVerify(pk, utf8.encode(message), hexToBytes(signature));
      _log.info('Signature valid: $result');
    } catch (e) {
      // if not a valid public key, try to parse it as a Bitcoin address
      try {
        final result = bitcoinSignedMessageVerify(
          pubKeyRaw,
          utf8.encode(message),
          signature,
        );
        _log.info('Signature valid: $result');
      } catch (e) {
        _log.info('Invalid public key or Bitcoin address: $pubKeyRaw');
        return;
      }
    }
  }
}

class PrivateKeyCommand extends Command<void> {
  @override
  final name = 'private-key';
  @override
  final description = 'Format a private key to WIF';
  PrivateKeyCommand() {
    argParser.addOption(
      'private-key',
      abbr: 'p',
      help: 'The private key file (single line in hex format).',
      mandatory: true,
    );
  }
  @override
  void run() {
    final pkFilename = argResults?.option('private-key');
    if (pkFilename == null) {
      _log.info('Please provide a private key file.');
      return;
    }
    // check if the file exists
    if (!File(pkFilename).existsSync()) {
      _log.info('Private key file not found: $pkFilename');
      return;
    }
    // read the private key from the file
    String pkRaw;
    try {
      pkRaw = File(pkFilename).readAsStringSync().trim();
      if (pkRaw.isEmpty) {
        _log.info('Private key file is empty: $pkFilename');
        return;
      }
    } catch (e) {
      _log.info('Error reading private key file: $pkFilename');
      return;
    }
    try {
      final pkBytes = hexToBytes(pkRaw);
      final pk = PrivateKey.fromPrivateKey(pkBytes);
      final wif = Wif(Network.mainnet, pk.privateKey, true);
      _log.info('WIF: ${wif.toWifString()}');
    } catch (e) {
      _log.info('Invalid private key format: $pkRaw');
    }
  }
}

class TestP2pCommand extends Command<void> {
  @override
  final name = 'test-p2p';
  @override
  final description = 'Test P2P functionality.';

  TestP2pCommand() {
    argParser.addOption(
      'peer',
      abbr: 'p',
      help:
          'The peer to connect to in the format <ip>:<port>. If ommitted, a dns seed will be used.',
    );
    argParser.addOption(
      'network',
      abbr: 'n',
      help: 'The Bitcoin network to use.',
      allowed: ['mainnet', 'testnet', 'testnet4'],
      defaultsTo: 'mainnet',
      allowedHelp: {
        'mainnet': 'Use the main Bitcoin network.',
        'testnet': 'Use the Bitcoin test network 3.',
        'testnet4': 'Use the Bitcoin test network 4.',
      },
    );
  }

  @override
  void run() async {
    String? ip;
    int? port;
    final network = switch (argResults?.option('network')) {
      'mainnet' => Network.mainnet,
      'testnet' => Network.testnet,
      'testnet4' => Network.testnet4,
      _ => throw ArgumentError('Invalid network type.'),
    };
    _log.info('Network: ${network.name}');
    final peerRaw = argResults?.option('peer');
    if (peerRaw == null) {
      _log.info('Using dns seed to find peer.');
      ip = await Peer.ipFromDnsSeed(network);
      port = Peer.defaultPort(network);
    } else {
      final parts = peerRaw.split(':');
      if (parts.length != 2) {
        _log.info('Invalid peer format. Use <ip>:<port>.');
        return;
      }
      ip = parts[0];
      port = int.tryParse(parts[1]);
      if (port == null || port <= 0 || port > 65535) {
        _log.info('Invalid port number: $parts[1]');
        return;
      }
    }
    final node = Node(network: network);
    node.connect(ip: ip, port: port);
  }
}

class RegtestExampleCommand extends Command<void> {
  @override
  final name = 'regtest-example';
  @override
  final description = 'An example command for regtest network.';

  RegtestExampleCommand();

  @override
  void run() async {
    _log.info('Starting bitcoin core in regtest mode...');
    final proc1 = CoreProcess(verbose: true, p2pPort: 18444, rpcPort: 18443);
    await proc1.start();
    final proc2 = CoreProcess(verbose: true, p2pPort: 18544, rpcPort: 18543);
    await proc2.start();

    // Listen for SIGINT (Ctrl+C)
    ProcessSignal.sigint.watch().listen((signal) async {
      _log.info('Ctrl+C detected. Cleaning up...');
      await proc1.stop();
      await proc2.stop();
      exit(0); // Exit the program gracefully
    });

    await proc1.waitTillInitialized();
    await proc2.waitTillInitialized();

    try {
      await proc2.rpc.addNode('${proc1.p2pHost}:${proc1.p2pPort}', 'add');
      _log.info('proc2: "addnode ${proc1.p2pHost}:${proc1.p2pPort} add" command executed.');
      final info = await proc1.rpc.getBlockchainInfo();
      _log.info('proc1: Blockchain info: $info');
      final blockCount = await proc1.rpc.getBlockCount();
      _log.info('proc1: Block count: $blockCount');
      final gen = await proc1.rpc.generateToAddress(
        2,
        'mgTgHVFXFdMEJiMmLhGrxu75waDYjCjDvN',
      );
      _log.info('proc1: Generate to address: $gen');
      final peerInfo = await proc2.rpc.getPeerInfo();
      _log.info('proc2: Peer info: $peerInfo');
      final info2 = await proc2.rpc.getBlockchainInfo();
      _log.info('proc2: Blockchain info: $info2');
    } catch (e) {
      _log.severe('Error connecting to regtest node: $e');
    }
    //sleep(const Duration(seconds: 50)); // wait for a bit to see the logs
    await proc1.stop();
    await proc2.stop();
    _log.info('Regtest example command completed.');
    exit(0); // not sure why this is needed :(
  }
}

void main(List<String> args) {
  initLogger();

  final runner =
      CommandRunner<void>(
          'dartcoin',
          'A command line interface for the dartcoin library.',
        )
        ..addCommand(ExampleCommand())
        ..addCommand(SignCommand())
        ..addCommand(VerifyCommand())
        ..addCommand(PrivateKeyCommand())
        ..addCommand(TestP2pCommand())
        ..addCommand(RegtestExampleCommand());
  runner
      .run(args)
      .catchError((dynamic e) {
        // ignore: avoid_print
        print(e);
        exit(64); // Exit code 64 indicates a usage error.
      }, test: (e) => e is UsageException)
      .catchError((dynamic e) {
        // ignore: avoid_print
        print(e);
        exit(1);
      });
}

Uint8List intToBytes(int value) {
  if (value < 0) {
    throw ArgumentError('Value must be non-negative');
  }
  final byteList = <int>[];
  while (value > 0) {
    byteList.add(value & 0xFF);
    value >>= 8;
  }
  return Uint8List.fromList(byteList.reversed.toList());
}

String intToHex(int value) {
  return bytesToHex(intToBytes(value));
}
