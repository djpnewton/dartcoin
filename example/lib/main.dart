import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';

import 'package:args/command_runner.dart';

import 'package:dartcoin/dartcoin.dart';

import 'node_sqlite.dart';

final _log = ColorLogger('main');

class ProfileCommand extends Command<void> {
  @override
  final name = 'profile';
  @override
  final description = 'Run a specific code area to profile.';

  ProfileCommand();

  @override
  void run() {
    while (true) {
      sleep(Duration(seconds: 1));
      _log.info('Running profile command. Press Ctrl+C to stop.');
      // run some code here that you want to profile
      // for example, you could run a specific benchmark or test function in a loop
      // or you could run some code that exercises a specific area of the library
      // and then use the Dart DevTools profiler to analyze the performance
    }
  }
}

class KeyGenCommand extends Command<void> {
  @override
  final name = 'key-gen';
  @override
  final description = 'An example command to demonstrate key generation.';

  KeyGenCommand() {
    argParser.addOption(
      'entropy',
      abbr: 'e',
      help: 'Optional entropy in hex or utf8 format to generate the mnemonic.',
    );
  }

  @override
  void run() {
    // try to parse entropy as hex, if fails, use utf8
    final entropyInput = argResults?.option('entropy');
    final Uint8List? entropy = processEntropy(entropyInput);
    final mnemonic = entropy != null
        ? mnemonicFromEntropy(entropy)
        : 'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
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

    final childPubKey2 = masterKey.childPublicKey(2);
    address = childPubKey2.address(network: Network.mainnet);
    _log.info('P2PKH Address (m/2): $address');
    address = childPubKey2.address(network: Network.testnet);
    _log.info('P2PKH Address (m/2) Testnet: $address');
    address = childPubKey2.address(
      network: Network.mainnet,
      scriptType: ScriptType.p2shP2wpkh,
    );
    _log.info('P2SH-P2WPKH Address (m/2): $address');
    address = childPubKey2.address(
      network: Network.testnet,
      scriptType: ScriptType.p2shP2wpkh,
    );
    _log.info('P2SH-P2WPKH Address (m/2) Testnet: $address');
    address = childPubKey2.address(
      network: Network.mainnet,
      scriptType: ScriptType.p2wpkh,
    );
    _log.info('P2WPKH Address (m/2): $address');
    address = childPubKey2.address(
      network: Network.testnet,
      scriptType: ScriptType.p2wpkh,
    );
    _log.info('P2WPKH Address (m/2) Testnet: $address');
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
      final signature = derSignMessage(pk, utf8.encode(message));
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
      final result = derVerifyMessage(
        pk,
        utf8.encode(message),
        hexToBytes(signature),
      );
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
    argParser.addFlag(
      'sync-block-headers',
      abbr: 'b',
      help: 'Enable syncing of block headers.',
      defaultsTo: true,
    );
    argParser.addFlag(
      'sync-block-filter-headers',
      abbr: 'f',
      help: 'Enable syncing of compact block filter headers.',
      defaultsTo: true,
    );
    argParser.addMultiOption(
      'wallet-addresses',
      abbr: 'a',
      help: 'Scan for wallet addresses in block filters.',
    );
    argParser.addOption(
      'birthday-block',
      abbr: 's',
      help: 'The starting block to use for scanning wallet addresses.',
    );
    argParser.addOption(
      'sqlite-filename',
      abbr: 'd',
      help: 'Optional filename for SQLite storage of chain data.',
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
    _log.info('Network: ${network.name}', color: LogColor.brightBlue);
    final peerRaw = argResults?.option('peer');
    if (peerRaw != null) {
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
    final syncBlockHeaders = argResults?.flag('sync-block-headers') ?? true;
    final syncBlockFilterHeaders =
        argResults?.flag('sync-block-filter-headers') ?? true;
    final walletAddresses =
        argResults?.multiOption('wallet-addresses') ?? <String>[];
    final birthdayBlockRaw = argResults?.option('birthday-block');
    int? birthdayBlock = birthdayBlockRaw != null
        ? int.tryParse(birthdayBlockRaw)
        : null;
    final sqliteFilename = argResults?.option('sqlite-filename');

    _log.info(
      '\n'
      '    Sync Block Headers: $syncBlockHeaders\n'
      '    Sync Block Filter Headers: $syncBlockFilterHeaders\n'
      '    Wallet Addresses: $walletAddresses\n'
      '    Birthday Block: $birthdayBlock\n'
      '    Sqlite Filename: ${sqliteFilename ?? "None"}',
      color: LogColor.brightBlue,
    );

    if (walletAddresses.isNotEmpty) {
      if (!syncBlockHeaders) {
        _log.severe(
          'Block headers must be synced (--sync-block-headers) when scanning addresses.',
        );
        return;
      }
      if (!syncBlockFilterHeaders) {
        _log.severe(
          'Block filter headers must be synced (--sync-block-filter-headers) when scanning addresses.',
        );
        return;
      }
      if (birthdayBlock == null) {
        _log.severe(
          'Birthday block must be provided (--birthday-block) when scanning addresses.',
        );
        return;
      }
    }

    final peerManager = PeerManager(network: network, verbose: true);
    Peer? peer;
    if (ip == null || port == null) {
      _log.info('Using dns seed to find peer.');
      peer = await peerManager.findPeer();
    } else {
      _log.info('Connecting to peer $ip:$port.');
      peer = await peerManager.connectPeer(PeerCandidate(ip: ip, port: port));
    }
    if (peer == null) {
      _log.warning(
        'No suitable peer found that supports compact block filters.',
      );
      return;
    }
    _log.info('Found suitable peer: ${peer.ip}:${peer.port}');
    final wallet = walletAddresses.isNotEmpty
        ? Wallet(
            addresses: walletAddresses,
            birthdayBlock: birthdayBlock!,
            txProvider: BlockDnTxProvider(network),
          )
        : null;
    final node = sqliteFilename != null
        ? NodeSqliteStorage(
            network: network,
            dbFilename: sqliteFilename,
            verbose: true,
            syncBlockFilterHeaders: syncBlockFilterHeaders,
            syncBlockHeaders: syncBlockHeaders,
            wallet: wallet,
            txProvider: BlockDnTxProvider(network),
          )
        : NodeFileStorage(
            network: network,
            verbose: true,
            syncBlockFilterHeaders: syncBlockFilterHeaders,
            syncBlockHeaders: syncBlockHeaders,
            wallet: wallet,
            txProvider: BlockDnTxProvider(network),
          );
    node.add(peer: peer);
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
    final dummyAddr1 = 'mgTgHVFXFdMEJiMmLhGrxu75waDYjCjDvN';
    final dummyAddr2 = 'mjcNxNEUrMs29U3wSdd7UZ54KGweZAehn6';
    _log.info('Starting bitcoin core in regtest mode...');
    final proc1 = CoreProcess(verbose: false, p2pPort: 18444, rpcPort: 18443);
    await proc1.start();
    final proc2 = CoreProcess(verbose: false, p2pPort: 18544, rpcPort: 18543);
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
      _log.info(
        'proc2: "addnode ${proc1.p2pHost}:${proc1.p2pPort} add" command executed.',
      );
      await proc1.rpc.generateToAddress(50, dummyAddr1);
      final hash50 = await proc1.rpc.getBestBlockHash();
      _log.info('proc1: Best block hash after 50 blocks: $hash50');
      await proc1.rpc.generateToAddress(50, dummyAddr1);
      _log.info('Waiting for block count to reach 100 on proc2...');
      await proc2.rpc.waitForBlockCount(100);
      _log.info('proc2: invalidating block $hash50');
      await proc2.rpc.invalidateBlock(hash50);
      final hash49 = await proc2.rpc.getBestBlockHash();
      _log.info('proc2: Best block hash after invalidation: $hash49');
      await proc2.rpc.generateToAddress(100, dummyAddr2);
      _log.info('proc2: Generated 100 blocks after invalidation.');
      final hash149 = await proc2.rpc.getBestBlockHash();
      _log.info('proc2: Best block hash after generating 100 blocks: $hash149');
      _log.info('Waiting for proc1 to reach block count 149...');
      await proc1.rpc.waitForBlockCount(149);
      final bestHashProc1 = await proc1.rpc.getBestBlockHash();
      _log.info(
        'proc1: Best block hash after generating 100 blocks: $bestHashProc1',
      );
      if (hash149 == bestHashProc1) {
        _log.info(
          'Both processes have the same best block hash after chain reorg.',
        );
      } else {
        _log.warning(
          'Best block hashes differ between processes: proc1: $bestHashProc1, proc2: $hash149',
        );
      }
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

class CreateTxCommand extends Command<void> {
  @override
  final name = 'create-tx';
  @override
  final description = 'Create a transaction.';

  CreateTxCommand() {
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
    argParser.addOption(
      'recipient',
      abbr: 'r',
      help: 'The recipient address for the transaction.',
      mandatory: true,
    );
    argParser.addOption(
      'change-recipient',
      abbr: 'c',
      help: 'The change recipient address for the transaction.',
    );
    argParser.addOption(
      'amount',
      abbr: 'a',
      help: 'The amount to send in satoshis.',
      mandatory: true,
    );
    argParser.addOption('fee', abbr: 'f', help: 'The fee to pay in satoshis.');
    argParser.addOption(
      'coins',
      abbr: 'i',
      help:
          'The coins to use as inputs in the format txid:vout (e.g. "txid1:vout1,txid2:vout2").',
      mandatory: true,
    );
  }

  @override
  void run() async {
    final network = switch (argResults?.option('network')) {
      'mainnet' => Network.mainnet,
      'testnet' => Network.testnet,
      'testnet4' => Network.testnet4,
      _ => throw ArgumentError('Invalid network type.'),
    };
    final recipient = argResults?.option('recipient');
    final changeRecipient = argResults?.option('change-recipient');
    final amountRaw = argResults?.option('amount');
    int? amount = amountRaw != null ? int.tryParse(amountRaw) : null;
    if (recipient == null || amount == null) {
      _log.info('Please provide both a recipient address and an amount.');
      return;
    }
    if (amount <= 0) {
      _log.info('Amount must be a positive integer.');
      return;
    }
    final feeRaw = argResults?.option('fee');
    int? fee = feeRaw != null ? int.tryParse(feeRaw) : null;
    if (fee == null || fee < 0) {
      _log.info('Fee must be a non-negative integer.');
      return;
    }
    final coins = argResults?.option('coins');
    if (coins == null) {
      _log.info('Please provide coins to use as inputs.');
      return;
    }
    _log.info('Creating transaction...');
    _log.info(
      'Network: ${network.name}, Recipient: $recipient, Change Recipient: $changeRecipient, Amount: $amount',
    );
    _log.info('Coins: $coins');
    // create inputs from coins
    final inputs = coins.split(',').map((coin) {
      final parts = coin.split(':');
      if (parts.length != 2) {
        throw ArgumentError('Invalid coin format: $coin. Use txid:vout.');
      }
      final txid = parts[0];
      final vout = int.tryParse(parts[1]);
      if (vout == null || vout < 0) {
        throw ArgumentError('Invalid vout number: ${parts[1]} in coin: $coin');
      }
      return TxIn(
        txid: txid,
        vout: vout,
        scriptSig: Uint8List(0),
        sequence: 0xFFFFFFFF,
      );
    }).toList();
    // sum input amounts
    var totalInputAmount = 0;
    for (var input in inputs) {
      final inputTx = await BlockDnTxProvider(network).fromTxid(input.txid);
      final inputAmount = inputTx.outputs[input.vout].value;
      totalInputAmount += inputAmount;
    }
    _log.info('Total input amount: $totalInputAmount satoshis');
    if (totalInputAmount < amount) {
      _log.info(
        'Total input amount is less than the amount to send. Please provide sufficient inputs.',
      );
      return;
    }
    // calc change
    final changeAmount = totalInputAmount - amount - fee;
    if (changeAmount < 0) {
      _log.info(
        'Total input amount is less than the amount plus fee. Please provide sufficient inputs or reduce the amount/fee.',
      );
      return;
    }
    if (changeAmount > 0 && changeRecipient != null) {
      _log.info('Change amount: $changeAmount satoshis');
    } else if (changeAmount > 0 && changeRecipient == null) {
      _log.info(
        'Change amount: $changeAmount satoshis. No change recipient provided, so change would be lost.',
      );
      return;
    }
    // create outputs
    final outputs = [
      TxOut(
        value: amount,
        scriptPubKey: AddressData.parseAddress(recipient).script,
      ),
      if (changeRecipient != null)
        TxOut(
          value: changeAmount,
          scriptPubKey: AddressData.parseAddress(changeRecipient).script,
        ),
    ];
    // create tx
    final tx = Transaction(
      type: TxType.segwit,
      version: 1,
      inputs: inputs,
      outputs: outputs,
      locktime: 0,
    );
    assert(tx.type() == TxType.segwit);
    _log.info('Transaction created');
    _log.info('JSON:');
    _log.info(tx.toJson());
    _log.info('Hex:');
    _log.info(bytesToHex(tx.toBytes()));
  }
}

class SignTxCommand extends Command<void> {
  @override
  final name = 'sign-tx';
  @override
  final description = 'Sign a transaction with a private key.';

  SignTxCommand() {
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
    argParser.addOption(
      'entropy',
      abbr: 'e',
      help: 'Entropy in hex or utf8 format to generate the mnemonic.',
      mandatory: true,
    );
    argParser.addOption(
      'transaction',
      abbr: 't',
      help: 'The transaction to sign in hex format.',
      mandatory: true,
    );
    argParser.addOption(
      'fee',
      abbr: 'f',
      help: 'The expected fee to pay in satoshis.',
      mandatory: true,
    );
  }

  @override
  void run() async {
    final network = switch (argResults?.option('network')) {
      'mainnet' => Network.mainnet,
      'testnet' => Network.testnet,
      'testnet4' => Network.testnet4,
      _ => throw ArgumentError('Invalid network type.'),
    };
    final entropyInput = argResults?.option('entropy');
    final entropy = processEntropy(entropyInput);
    if (entropy == null) {
      _log.info('Please provide valid entropy.');
      return;
    }
    final txHex = argResults?.option('transaction');
    if (txHex == null) {
      _log.info('Please provide a transaction to sign.');
      return;
    }
    final feeRaw = argResults?.option('fee');
    if (feeRaw == null) {
      _log.info('Please provide a fee to pay.');
      return;
    }
    int? fee = int.tryParse(feeRaw);
    if (fee == null || fee < 0) {
      _log.info('Fee must be a non-negative integer.');
      return;
    }
    // parse transaction from hex
    Transaction tx;
    try {
      tx = Transaction.fromBytes(hexToBytes(txHex));
    } catch (e) {
      _log.info(
        'Invalid transaction format. Please provide a valid transaction in hex format.',
      );
      _log.info('Error: $e');
      return;
    }
    // get the privkeys and previous outputs for the inputs
    List<Transaction> prevTxs = [];
    List<TxOut> previousOutputs = [];
    List<PrivateKey> privKeys = [];
    for (var input in tx.inputs) {
      final prevTx = await BlockDnTxProvider(network).fromTxid(input.txid);
      prevTxs.add(prevTx);
      final prevOutput = prevTx.outputs[input.vout];
      previousOutputs.add(prevOutput);
      // get the pubkey hash from the prev output scriptPubKey
      final spkMatch = matchScriptPubKey(prevOutput.scriptPubKey);
      final pubkeyHash = switch (spkMatch.scriptType) {
        ScriptType.p2pkh => spkMatch.payload,
        ScriptType.p2wpkh => spkMatch.payload,
        _ => throw ArgumentError(
          'Unsupported script type: ${spkMatch.scriptType}',
        ),
      };
      // search for the private key that corresponds pubkey hash
      final mnemonic = mnemonicFromEntropy(entropy);
      final seed = mnemonicToSeed(mnemonic);
      final masterKey = PrivateKey.fromSeed(hexToBytes(seed));
      // search the first 100 child keys for a matching pubkey hash
      PrivateKey? foundKey;
      for (var i = 0; i < 100; i++) {
        final childKey = masterKey.childPrivateKey(i, hardened: false);
        final childPubKey = childKey.publicKey;
        final childPubKeyHash = hash160(childPubKey);
        if (listEquals(childPubKeyHash, pubkeyHash)) {
          foundKey = childKey;
          _log.info(
            'Found matching private key for input ${input.txid}:${input.vout} at index $i',
          );
          break;
        }
      }
      if (foundKey == null) {
        _log.info(
          'No matching private key found for input ${input.txid}:${input.vout} in the first 100 child keys. Cannot sign this transaction.',
        );
        return;
      }
      privKeys.add(foundKey);
    }
    // sign the transaction
    final signedTx = signTransaction(
      tx: tx,
      privKeys: privKeys,
      previousOutputs: previousOutputs,
      fee: fee,
    );
    _log.info('Transaction signed');
    _log.info('Hex: ${bytesToHex(signedTx.toBytes())}');
  }
}

class VerifyTxCommand extends Command<void> {
  @override
  final name = 'verify-tx';
  @override
  final description = 'Verify a transaction.';

  VerifyTxCommand() {
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
    argParser.addOption(
      'transaction',
      abbr: 't',
      help: 'The transaction to verify in hex format.',
      mandatory: true,
    );
  }

  @override
  void run() async {
    final network = switch (argResults?.option('network')) {
      'mainnet' => Network.mainnet,
      'testnet' => Network.testnet,
      'testnet4' => Network.testnet4,
      _ => throw ArgumentError('Invalid network type.'),
    };
    final txHex = argResults?.option('transaction');
    if (txHex == null) {
      _log.info('Please provide a transaction to verify.');
      return;
    }
    // parse transaction from hex
    Transaction tx;
    try {
      tx = Transaction.fromBytes(hexToBytes(txHex));
    } catch (e) {
      _log.info(
        'Invalid transaction format. Please provide a valid transaction in hex format.',
      );
      return;
    }
    // print transaction details
    _log.info('Transaction details:');
    _log.info(tx.toJson());
    // get the prev outputs for the inputs
    List<TxOut> previousOutputs = [];
    for (var input in tx.inputs) {
      final prevTx = await BlockDnTxProvider(network).fromTxid(input.txid);
      final prevOutput = prevTx.outputs[input.vout];
      previousOutputs.add(prevOutput);
    }
    // verify the transaction
    final isValid = verifyTransaction(tx: tx, previousOutputs: previousOutputs);
    _log.info('Transaction is ${isValid ? 'valid' : 'invalid'}.');
  }
}

void main(List<String> args) {
  initConsoleLogger();

  final runner =
      CommandRunner<void>(
          'dartcoin',
          'A command line interface for the dartcoin library.',
        )
        ..addCommand(ProfileCommand())
        ..addCommand(KeyGenCommand())
        ..addCommand(SignCommand())
        ..addCommand(VerifyCommand())
        ..addCommand(PrivateKeyCommand())
        ..addCommand(TestP2pCommand())
        ..addCommand(RegtestExampleCommand())
        ..addCommand(CreateTxCommand())
        ..addCommand(SignTxCommand())
        ..addCommand(VerifyTxCommand());

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

Uint8List? processEntropy(String? entropyInput) {
  if (entropyInput == null) return null;
  Uint8List entropy;
  try {
    entropy = hexToBytes(entropyInput);
    _log.info('Using entropy (hex): $entropyInput');
  } catch (e) {
    entropy = utf8.encode(entropyInput);
    _log.info('Using entropy (utf8): $entropyInput');
  }
  if (entropy.lengthInBytes > 32) {
    // if greater than 256 bits, truncate to 256 bits
    entropy = entropy.sublist(0, 32);
    _log.info('Entropy truncated to 256 bits.');
  } else if (entropy.lengthInBytes < 16) {
    // if less than 128 bits, pad with zeros to 128 bits
    final padded = Uint8List(16);
    padded.setRange(0, entropy.lengthInBytes, entropy);
    entropy = padded;
    _log.info('Entropy padded to 128 bits.');
  } else if (entropy.lengthInBytes % 4 != 0) {
    // pad to nearest multiple of 32 bits
    final newLength =
        ((entropy.lengthInBytes + 3) ~/ 4) * 4; // round up to nearest 4
    final padded = Uint8List(newLength);
    padded.setRange(0, entropy.lengthInBytes, entropy);
    entropy = padded;
    _log.info('Entropy padded to nearest multiple of 32 bits.');
  }
  return entropy;
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
