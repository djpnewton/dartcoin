import 'dart:async';

import 'package:flutter/material.dart';

import 'package:dartcoin/dartcoin.dart';

// A testnet block in raw hex for the demo.
const _blockHex =
    '00000020fd305f734ed7db58b215d18b5f5982843f0be3055d51de0f5e20000000000000a48cedccd2ae4f9854f9c3b50a07423214db68754b95abf1aacc5b0ffb0c660df0973e66c0ff3f1ae09b96dc0d010000000001010000000000000000000000000000000000000000000000000000000000000000ffffffff2b027a4e0004e7973e6604597117240cb4ec3d6620090000000000000f2f636f696e6661756365742e65752fffffffff029cf8052a01000000160014e4812bd0b7e9a7c5713a6e93acf91fec533386f60000000000000000266a24aa21a9ed2a3ebe5ecce10e58913cdb39c6c7de0843efab1b6d41f89f07f89be10aa88bbb012000000000000000000000000000000000000000000000000000000000000000000000000002000000000101564c440f353c42295862c566954cbe03dbfc18be568485ad919db36456c0eb300000000000fdffffff0276060000000000001600149946c1d23bf018309206a9e0ce1a08ede07399300564150200000000160014feb715b8482e3bee123cd7b97200c50256b341e502473044022077a86a595b98bd367298c2b20ddc2e792fede81dd81621b6c87022341b6397df02206736e05e7da4aa8b2285dd971cc78534401e68afe9114ad6b2b6644edc1cf1cf012103a44823db79850eab0d58aa08e4d121e860110b31a8e094e74df2bad416b299766c4e000002000000000101550130c4d097c62b9902e1fadb53838d09e3c3338e1c4e6bfb4546237bef4bcb0000000000fdffffff0206040000000000001600149946c1d23bf018309206a9e0ce1a08ede07399301e94f6bc00000000160014a33d1f8a4165560bfc8af382dcde7b923244204d0247304402204129755c55be1c3032a59c39a9ae8474ffcf586162689512e09d0f79d5243ad90220503a6ff65cc79f6e22073d0046389b50d7deacb8c0ebeb67d944447f7bc51c4d012102063d832bfd5386dc63243e8b8f93ecafc0b3cec5037e3cc3ffc0043af30591886c4e0000020000000001010783a2369d9e0fb11ac8fad7891eea47dd6ac37cea53f84258d580bb14a04a760000000000fdffffff02b1060000000000001600149946c1d23bf018309206a9e0ce1a08ede0739930fc6c1800000000001600147c5bf408f08db93cdf8611287b2732224bec1ac10247304402201768ca964c691dc87f147ac3f59ffb7e3f88269343906b5fc832e692e5708e9a0220648fbd4586314c94876c79c3894a1b096bee91a810bab0e3a376fc3e94665032012102c360efe980c7cc4b0cf546db358f971a957b1ae11471741e39d3341f71c04db06c4e0000020000000001019f6a405a2d612812d95b054315982833fb01ad6a9df6aae2e099d7fb4c5f2a990100000000fdffffff025460c702000000001600148db34f7b173cc36bd37efb1079c00164ce0e381fab060000000000001600149946c1d23bf018309206a9e0ce1a08ede073993002473044022018525a110585471ca94e36bcced8bfba0339891e21b71f5440523572fbfe285d022075dc75b3ec96a2b886b42c477356bf8e94aae23b3939da47dd103d1fe96df652012103b1c079338bf3806331523cd1bf8a38a8e02ef761dceb59346b55db77867721be6c4e000002000000000101690db38f568b9fcd8eb20e50081433235946627d5e471142505eb6db172897d10100000000fdffffff0235070000000000001600149946c1d23bf018309206a9e0ce1a08ede073993032e3000000000000160014230d803b9d1873dfd169bed277419441296ec79a02473044022037578fb2faf4c873512f27a79b65b12feeed861341df636c6a8486137993e7f30220202372275dd7c56b56df03e2fafc6620ffe9d0dd34a9bf47d6ee9a6f02fbd074012103a90b13b98370ec82bdb21b43bea3deae834e019ec4f4684cdc1bb33285ccd9ab654e0000020000000001019c5b5846452d19081f1d1a4f6c275f58365ac5771be709fe30ff18db5a2856f80000000000fdffffff02f7040000000000001600149946c1d23bf018309206a9e0ce1a08ede073993019110100000000001600149c9f9dd48a46237e98a13b0024159143d1a002f40247304402204373bb9c143cc730d8469e5e06e698ca3cc417f04669a77925c2023606aa03180220672786f0cdcdfdfc180cbbb1c0a861663abdc1e338adfc3dbeea1aa1ea06ab8b012103d9a39a1c85d14e002f3051217b6d30e2e22f5aeea92b0c0bd7fff6f099d7ad626c4e0000020000000001013e5a1fdb2afca4b33677128eafecd8bcfb6c046f50ad3c2a193787af12377be40000000000fdffffff026ad100000000000016001443be6af7bc80741a79e0468c076609792e234a4386070000000000001600149946c1d23bf018309206a9e0ce1a08ede07399300247304402201f29676c139dd458c039aac87f1f16deae5907a648f723aee7386d97d3c845ac02200a291528aaafa74773bc370b88d709de8186f77a18a41e8b5d9c60112698bf09012103338bf2f93559a1647b1fd63f08d72cae106e35c388869c83d295d2c3cc71cdf76c4e00000200000000010139aa8c50d0acc804e337f24f8d02416264b55465dd737a2fe4d8a78776805e480100000000fdffffff029b040000000000001600149946c1d23bf018309206a9e0ce1a08ede07399307cb32601000000001600147efa1ac9c21c58c6e6561170449fe04dddd7a1b802473044022061748e634c0b01e5214cad844d1f34bd6ba96985c6ae850be469f4fb17e83f6a02200d12ca38d219dcb48817407e42b1310919fa3fccbad041db9abe0667d6ca313201210376ceb7c67c511172d542831049d80d92b771fa031b69dcfb9bff482c074e0d656c4e000002000000000101c3374a3701f5adc441cb55e5e592d4e11f529398f04c01222eb3c43dab5a23350100000000fdffffff02c5060000000000001600149946c1d23bf018309206a9e0ce1a08ede0739930298df50200000000160014893286ca29b3968d20a9362e7c0e9d34f84b12f30247304402202778cce1f63287e482e95b5030156bcd6d2591329b527a74a025dc2e0db074550220432ca4cbd944ee66265cc3b80ed7bed9aff7b8affdf3429a20081ba78d8e39c601210366d4662d8ae71697f3c0699bb6f001b197e1cfe5b2ee269665a876a78966cd576c4e0000020000000001017dc0cca3dd4bbc882260f0de3e6944875121776878b57c921908ddfbc29650c60100000000fdffffff0214070000000000001600149946c1d23bf018309206a9e0ce1a08ede07399306d0b0a0000000000160014848560a1934cddaa1982781691b357a7ef023ed0024730440220719865a970ea1f3706ab3697021b59096248e966c4ad1e692ae0db4b5a9347870220779be9dcc1a74ae722be68e96a93d566d0f722ad238fe26f51f4da22cdaf814e0121029fc776464dd9d895222053e2db42cf4f39af729898b08b06c2ebb7d280c7a4096c4e000002000000000101fb286ebc6bc51873d75e4b7acb4e9cb0824b8de7569c6e078b0dc84e2cd1736b0000000000fdffffff02504cb6b400000000160014f075e5e85d85b6eb38ae4d4f6cd0dec332e31cd8b1060000000000001600149946c1d23bf018309206a9e0ce1a08ede0739930024730440220676b482af935255078762ee0baaa0a228f81d2d555ec87f89a7b7041480cab1d02206ea4d678c03919c46d4362cb06a1ba5a2a3cb3e539cd3c506db14dd2d30bf00c01210306a36bf4d7025ed5330df342c19a05b6b5968730a5d9d16be24a4bea00feac8c6c4e000002000000000101d90dac5a33882ea05521e2c2303e1a5ca0d2fde66cd6d6464ffa124db0583cd60100000000fdffffff0246050000000000001600149946c1d23bf018309206a9e0ce1a08ede07399308ba2080000000000160014d6a23591c96d45147e31029a9dc309d99f9ac8100247304402207432e55d3cca0cc1a8cb4acad07ab6f2b903015f4d1ebc26eaa1d1573769d1d602205834a65088d150b68d887a56776c979bfa480cf2a96d35270c4e6ffe3508f6e40121024f758944b4fd50e78c8cb7ec189939574e4f8e113e42fd54705e2d92ff27f39e6c4e0000';

void main() {
  // init logger for console output
  initConsoleLogger();
  // Set the WebSocket bridge host and port for the web socket backend. from
  // environment variables
  setWebSocketBridgeHostPort(
    const String.fromEnvironment('WS_BRIDGE_PROTOCOL', defaultValue: 'ws'),
    const String.fromEnvironment('WS_BRIDGE_HOST', defaultValue: 'localhost'),
    int.parse(
      const String.fromEnvironment('WS_BRIDGE_PORT', defaultValue: '3001'),
    ),
  );
  // Run the demo app.
  runApp(const BlockStorageDemoApp());
}

class BlockStorageDemoApp extends StatelessWidget {
  const BlockStorageDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dartcoin Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const _AppShell(),
    );
  }
}

class _AppShell extends StatelessWidget {
  const _AppShell();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
          title: const Text('Dartcoin Demo'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.storage), text: 'Block Storage'),
              Tab(icon: Icon(Icons.wifi_find), text: 'Peer Finder'),
              Tab(icon: Icon(Icons.account_tree), text: 'Light Node'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [BlockStorageDemoPage(), PeerFinderPage(), LightNodePage()],
        ),
      ),
    );
  }
}

enum DemoStep { idle, initializing, saving, retrieving, done, error }

class _StepResult {
  final DemoStep step;
  final String label;
  final String? detail;
  final bool success;

  const _StepResult({
    required this.step,
    required this.label,
    this.detail,
    this.success = true,
  });
}

class BlockStorageDemoPage extends StatefulWidget {
  const BlockStorageDemoPage({super.key});

  @override
  State<BlockStorageDemoPage> createState() => _BlockStorageDemoPageState();
}

class _BlockStorageDemoPageState extends State<BlockStorageDemoPage> {
  DemoStep _current = DemoStep.idle;
  final List<_StepResult> _results = [];
  Block? _retrieved;

  Future<void> _runDemo() async {
    setState(() {
      _current = DemoStep.idle;
      _results.clear();
      _retrieved = null;
    });

    final block = Block.fromBytes(_blockHex.toBytes());
    final blockHash = block.hash();
    final blockStore = defaultBlockStoreFactory('blocks');
    await blockStore.init();

    setState(() => _current = DemoStep.initializing);
    try {
      _addResult(DemoStep.initializing, 'Storage initialised', success: true);
    } catch (e) {
      _addResult(
        DemoStep.initializing,
        'Init failed',
        detail: '$e',
        success: false,
      );
      setState(() => _current = DemoStep.error);
      return;
    }

    setState(() => _current = DemoStep.saving);
    try {
      await blockStore.store(block);
      _addResult(
        DemoStep.saving,
        'Block saved',
        detail: 'hash: ${block.header.hashNice()}',
      );
    } catch (e) {
      _addResult(DemoStep.saving, 'Save failed', detail: '$e', success: false);
      setState(() => _current = DemoStep.error);
      return;
    }

    setState(() => _current = DemoStep.retrieving);
    try {
      final loaded = await blockStore.read(blockHash);
      if (loaded == null) throw StateError('block not found in storage');
      _retrieved = loaded;
      _addResult(DemoStep.retrieving, 'Block retrieved', success: true);
    } catch (e) {
      _addResult(
        DemoStep.retrieving,
        'Retrieve failed',
        detail: '$e',
        success: false,
      );
      setState(() => _current = DemoStep.error);
      return;
    }

    setState(() => _current = DemoStep.done);
  }

  void _addResult(
    DemoStep step,
    String label, {
    String? detail,
    bool success = true,
  }) {
    setState(() {
      _results.add(
        _StepResult(step: step, label: label, detail: detail, success: success),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StepsCard(results: _results, current: _current),
            const SizedBox(height: 20),
            if (_current == DemoStep.done && _retrieved != null)
              _BlockDetailsCard(block: _retrieved!),
            if (_current == DemoStep.done) const _StorageInfoCard(),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed:
            _current == DemoStep.initializing ||
                _current == DemoStep.saving ||
                _current == DemoStep.retrieving
            ? null
            : _runDemo,
        label: const Text('Run Demo'),
        icon: const Icon(Icons.play_arrow),
      ),
    );
  }
}

class _StepsCard extends StatelessWidget {
  final List<_StepResult> results;
  final DemoStep current;

  const _StepsCard({required this.results, required this.current});

  static const _steps = [
    (DemoStep.initializing, 'Initialise storage'),
    (DemoStep.saving, 'Save block'),
    (DemoStep.retrieving, 'Retrieve block'),
  ];

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Steps', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final (step, label) in _steps)
              _StepTile(
                label: label,
                result: results.where((r) => r.step == step).lastOrNull,
                running: current == step,
              ),
            if (results.isEmpty && current == DemoStep.idle)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Press Run Demo to start.',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final String label;
  final _StepResult? result;
  final bool running;

  const _StepTile({
    required this.label,
    required this.result,
    required this.running,
  });

  @override
  Widget build(BuildContext context) {
    Widget leading;
    if (running) {
      leading = const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    } else if (result != null) {
      leading = Icon(
        result!.success ? Icons.check_circle : Icons.error,
        color: result!.success ? Colors.green : Colors.red,
        size: 20,
      );
    } else {
      leading = const Icon(
        Icons.radio_button_unchecked,
        size: 20,
        color: Colors.grey,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label),
                if (result?.detail != null)
                  Text(
                    result!.detail!,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BlockDetailsCard extends StatelessWidget {
  final Block block;

  const _BlockDetailsCard({required this.block});

  @override
  Widget build(BuildContext context) {
    final h = block.header;
    final dt = DateTime.fromMillisecondsSinceEpoch(h.time * 1000, isUtc: true);
    final rows = <(String, String)>[
      ('Hash', h.hashNice()),
      ('Previous', headerHashNice(h.previousBlockHeaderHash)),
      ('Time', dt.toIso8601String()),
      ('Version', '0x${h.version.toRadixString(16).padLeft(8, '0')}'),
      ('Bits', '0x${h.nBits.toRadixString(16).padLeft(8, '0')}'),
      ('Nonce', h.nonce.toString()),
      ('Transactions', block.transactionCount.toString()),
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Block details',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            for (final (key, value) in rows)
              _DetailRow(label: key, value: value),
          ],
        ),
      ),
    );
  }
}

class _StorageInfoCard extends StatelessWidget {
  const _StorageInfoCard();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Storage backend',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            _DetailRow(
              label: 'Backend',
              value: defaultBlockStoreFactory('blocks').runtimeType.toString(),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

enum _FindState { idle, queryingDns, connecting, found, notFound, error }

class PeerFinderPage extends StatefulWidget {
  const PeerFinderPage({super.key});

  @override
  State<PeerFinderPage> createState() => _PeerFinderPageState();
}

class _PeerFinderPageState extends State<PeerFinderPage> {
  _FindState _state = _FindState.idle;
  Network _network = Network.mainnet;
  final List<String> _log = [];
  Peer? _peer;

  bool get _busy =>
      _state == _FindState.queryingDns || _state == _FindState.connecting;

  void _addLog(String msg) => setState(() => _log.add(msg));

  Future<void> _run() async {
    setState(() {
      _state = _FindState.idle;
      _log.clear();
      _peer = null;
    });

    // Step 1: DNS seeds
    setState(() => _state = _FindState.queryingDns);
    final List<String> ips;
    try {
      ips = await Peer.ipsFromDnsSeeds(_network);
      _addLog('DNS: found ${ips.length} candidate IP(s)');
    } catch (e) {
      _addLog('DNS failed: $e');
      setState(() => _state = _FindState.error);
      return;
    }
    if (ips.isEmpty) {
      _addLog('No IPs returned from DNS seeds.');
      setState(() => _state = _FindState.notFound);
      return;
    }

    // Step 2: connect
    setState(() => _state = _FindState.connecting);
    final manager = PeerManager(network: _network);
    final port = Peer.defaultPort(_network);
    Peer? found;
    for (final ip in ips) {
      if (!mounted) return;
      _addLog('Trying $ip...');
      final peer = await manager.connectPeer(PeerCandidate(ip: ip, port: port));
      if (peer != null) {
        found = peer;
        _addLog('Connected to $ip:$port ✓');
        break;
      }
    }

    if (found != null) {
      setState(() {
        _peer = found;
        _state = _FindState.found;
      });
    } else {
      _addLog('No suitable peer found after trying all candidates.');
      setState(() => _state = _FindState.notFound);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Network selector
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Text('Network:'),
                const SizedBox(width: 12),
                DropdownButton<Network>(
                  value: _network,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() => _network = v!),
                  items: const [
                    DropdownMenuItem(
                      value: Network.mainnet,
                      child: Text('Mainnet'),
                    ),
                    DropdownMenuItem(
                      value: Network.testnet,
                      child: Text('Testnet'),
                    ),
                    DropdownMenuItem(
                      value: Network.testnet4,
                      child: Text('Testnet4'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Log
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: _log.isEmpty && _state == _FindState.idle
                    ? const Center(
                        child: Text(
                          'Press Find Peer to start.',
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length + (_busy ? 1 : 0),
                        itemBuilder: (context, i) {
                          if (i == _log.length) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    _state == _FindState.queryingDns
                                        ? 'Querying DNS seeds...'
                                        : 'Connecting...',
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ],
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              _log[i],
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ),
          // Result / error card
          if (_state == _FindState.found && _peer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: _PeerInfoCard(peer: _peer!),
            ),
          if (_state == _FindState.notFound || _state == _FindState.error)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Card(
                color: Colors.red.shade700,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Icon(Icons.error, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        _state == _FindState.notFound
                            ? 'No suitable peer found.'
                            : 'An error occurred — see log.',
                        style: const TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _busy ? null : _run,
        label: const Text('Find Peer'),
        icon: const Icon(Icons.search),
      ),
    );
  }
}

class _PeerInfoCard extends StatelessWidget {
  final Peer peer;

  const _PeerInfoCard({required this.peer});

  @override
  Widget build(BuildContext context) {
    final flags = peer.serviceFlags;
    final rows = <(String, String)>[
      ('Address', '${peer.ip}:${peer.port}'),
      ('Status', peer.status.name),
      ('Compact filters', peer.nodeCompactFiltersSupport ? 'Yes ✓' : 'No'),
      if (flags != null) ('Services', '0x${flags.toRadixString(16)}'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Peer found', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final (label, value) in rows)
              _DetailRow(label: label, value: value),
          ],
        ),
      ),
    );
  }
}

enum _NodeRunState {
  idle,
  initializing,
  discovering,
  connecting,
  syncing,
  stopped,
  error,
}

class LightNodePage extends StatefulWidget {
  const LightNodePage({super.key});

  @override
  State<LightNodePage> createState() => _LightNodePageState();
}

class _LightNodePageState extends State<LightNodePage> {
  _NodeRunState _state = _NodeRunState.idle;
  Network _network = Network.testnet4;
  Node? _node;
  Timer? _pollTimer;
  bool _stopping = false;
  final ScrollController _logScrollController = ScrollController();
  final List<String> _log = [];

  // wallet config (editable only when stopped)
  final TextEditingController _addressesCtrl = TextEditingController(
    text: 'tb1q65v5vkjk6w08najsk2eu52yedq0p5fxmz62sk9',
  );
  final TextEditingController _birthdayCtrl = TextEditingController(
    text: '108000',
  );

  /// Log records buffered by the global log handler; flushed on each poll tick
  /// so we never call setState from within the node's processing.
  final List<String> _pendingLogs = [];

  // polled stats
  int _headerHeight = 0;
  int _filterHeaderHeight = 0;
  int _filterHeight = 0;
  String _bestHash = '';
  String _connectedPeer = '';
  int _unspentCoins = 0;
  int _balanceSat = 0;
  int _txCount = 0;

  /// Logger modules whose INFO messages are forwarded to the UI log.
  static const _uiModules = {'Node', 'Peer', 'PeerManager'};

  bool get _canStart =>
      _state == _NodeRunState.idle ||
      _state == _NodeRunState.stopped ||
      _state == _NodeRunState.error;

  void _installLogCapture() {
    initCustomLogger((record) {
      // Keep full console output.
      final lvl = record.level.name.toUpperCase().padRight(7);
      final t = record.time;
      final ts =
          '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')} '
          '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
      // ignore: avoid_print
      print('$lvl: $ts: ${record.loggerName} : ${record.message}');

      // Buffer for UI: selected modules at INFO+, or any WARNING/SEVERE.
      final forUi =
          _uiModules.contains(record.loggerName) ||
          record.level >= LogLevel.warning;
      if (!forUi) return;
      final now = record.time;
      final uts =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}:'
          '${now.second.toString().padLeft(2, '0')}';
      _pendingLogs.add('[$uts][${record.loggerName}] ${record.message}');
    });
  }

  void _uninstallLogCapture() => initConsoleLogger();

  void _addLog(String msg) {
    final now = DateTime.now();
    final ts =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';
    setState(() => _log.add('[$ts] $msg'));
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_logScrollController.hasClients) {
        _logScrollController.animateTo(
          _logScrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _node?.shutdown();
    _uninstallLogCapture();
    _logScrollController.dispose();
    _addressesCtrl.dispose();
    _birthdayCtrl.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    // Parse wallet config before clearing state.
    final addresses = _addressesCtrl.text
        .split(RegExp(r'[,\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final birthday = int.tryParse(_birthdayCtrl.text.trim()) ?? 0;

    setState(() {
      _state = _NodeRunState.initializing;
      _log.clear();
      _pendingLogs.clear();
      _headerHeight = 0;
      _filterHeaderHeight = 0;
      _filterHeight = 0;
      _bestHash = '';
      _connectedPeer = '';
      _unspentCoins = 0;
      _balanceSat = 0;
      _txCount = 0;
    });

    _stopping = false;
    _installLogCapture();

    try {
      // 1. Create + initialise node
      _addLog('Creating node (${_network.name})…');
      final wallet = addresses.isNotEmpty
          ? Wallet(
              addresses: addresses,
              birthdayBlock: birthday,
              txProvider: BlockDnTxProvider(_network),
            )
          : null;
      if (wallet != null) {
        _addLog(
          'Wallet: ${addresses.length} address(es), birthday block $birthday',
        );
      }
      _node = defaultNodeFactory(
        network: _network,
        txProvider: BlockDnTxProvider(_network),
        syncBlockFilterHeaders: true,
        verbose: true,
        wallet: wallet,
      );
      await _node!.init();
      if (_stopping || !mounted) return;
      _addLog('Node initialised');

      // 2. Discover + connect to a peer that supports compact block filters
      setState(() => _state = _NodeRunState.discovering);
      _addLog('Searching for peer with compact filter support…');
      final manager = PeerManager(network: _network, verbose: true);
      final peer = await manager.findPeer();
      if (_stopping || !mounted) return;

      if (peer == null) {
        setState(() => _state = _NodeRunState.error);
        _addLog('Could not find a peer with compact filter support');
        return;
      }

      setState(() {
        _state = _NodeRunState.connecting;
        _connectedPeer = '${peer.ip}:${peer.port}';
      });
      _addLog('Found peer ✓  ${peer.ip}:${peer.port}');

      // Hand the already-handshaked peer to the node to start syncing.
      _node!.add(peer: peer);

      // 3. Syncing — fast poll flushes logs + updates stats
      setState(() => _state = _NodeRunState.syncing);
      _addLog('Syncing…');
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 300),
        (_) => _poll(),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _state = _NodeRunState.error);
        _addLog('Error: $e');
      }
    }
  }

  void _poll() {
    if (!mounted || _node == null) return;
    try {
      final h = _node!.blockCount();
      final fh = _node!.blockFilterHeaderCount();
      final ff = _node!.blockFilterCount();
      final bh = h > 0 ? _node!.bestBlockHash() : '';
      final wallet = _node!.wallet;
      final unspent = wallet?.unspentCoins.length ?? 0;
      final balance = wallet?.unspentCoins.fold(0, (s, c) => s + c.amount) ?? 0;
      final txCount = wallet?.transactions.length ?? 0;

      // Drain the pending log buffer in one setState call.
      final incoming = List<String>.from(_pendingLogs);
      _pendingLogs.clear();

      setState(() {
        _headerHeight = h;
        _filterHeaderHeight = fh;
        _filterHeight = ff;
        _bestHash = bh;
        _unspentCoins = unspent;
        _balanceSat = balance;
        _txCount = txCount;
        _log.addAll(incoming);
        // Keep the list bounded so the ListView stays fast.
        if (_log.length > 500) _log.removeRange(0, _log.length - 500);
      });
      if (incoming.isNotEmpty) _scrollToBottom();
    } catch (_) {}
  }

  void _stop() {
    _stopping = true;
    _pollTimer?.cancel();
    _pollTimer = null;
    _node?.shutdown();
    _node = null;
    _uninstallLogCapture();
    if (mounted) {
      setState(() => _state = _NodeRunState.stopped);
      _addLog('Node stopped');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _LnNetworkPicker(
            value: _network,
            enabled: _canStart,
            onChanged: (n) => setState(() => _network = n),
          ),
          const SizedBox(height: 12),
          _LnWalletConfigCard(
            addressesCtrl: _addressesCtrl,
            birthdayCtrl: _birthdayCtrl,
            enabled: _canStart,
          ),
          const SizedBox(height: 12),
          _LnStatusChip(state: _state),
          const SizedBox(height: 12),
          _LnStatsRow(
            headerHeight: _headerHeight,
            filterHeaderHeight: _filterHeaderHeight,
            filterHeight: _filterHeight,
            connectedPeer: _connectedPeer,
          ),
          if (_node?.wallet != null) ...[
            const SizedBox(height: 8),
            _LnWalletStatsRow(
              unspentCoins: _unspentCoins,
              balanceSat: _balanceSat,
              txCount: _txCount,
            ),
          ],
          if (_bestHash.isNotEmpty) ...[
            const SizedBox(height: 8),
            _LnBestHashCard(hash: _bestHash),
          ],
          const SizedBox(height: 12),
          SizedBox(
            height: 280,
            child: Card(
              child: _log.isEmpty
                  ? const Center(
                      child: Text(
                        'Press Start to run the node.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.builder(
                      controller: _logScrollController,
                      padding: const EdgeInsets.all(10),
                      itemCount: _log.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(
                          _log[i],
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
      floatingActionButton: _canStart
          ? FloatingActionButton.extended(
              onPressed: _start,
              label: const Text('Start'),
              icon: const Icon(Icons.play_arrow),
            )
          : FloatingActionButton.extended(
              onPressed: _stop,
              backgroundColor: Colors.red.shade700,
              label: const Text('Stop'),
              icon: const Icon(Icons.stop),
            ),
    );
  }
}

class _LnWalletConfigCard extends StatelessWidget {
  final TextEditingController addressesCtrl;
  final TextEditingController birthdayCtrl;
  final bool enabled;

  const _LnWalletConfigCard({
    required this.addressesCtrl,
    required this.birthdayCtrl,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Wallet', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 10),
            TextField(
              controller: addressesCtrl,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Addresses to scan',
                hintText: 'Comma or newline separated',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: birthdayCtrl,
              enabled: enabled,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Birthday block',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _LnWalletStatsRow extends StatelessWidget {
  final int unspentCoins;
  final int balanceSat;
  final int txCount;

  const _LnWalletStatsRow({
    required this.unspentCoins,
    required this.balanceSat,
    required this.txCount,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LnStatCard(
            label: 'Transactions',
            value: txCount > 0 ? txCount.toString() : '—',
            icon: Icons.swap_horiz,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LnStatCard(
            label: 'Unspent Coins',
            value: unspentCoins > 0 ? unspentCoins.toString() : '—',
            icon: Icons.toll,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LnStatCard(
            label: 'Balance',
            value: balanceSat > 0 ? '$balanceSat sat' : '—',
            icon: Icons.account_balance_wallet,
          ),
        ),
      ],
    );
  }
}

class _LnNetworkPicker extends StatelessWidget {
  final Network value;
  final bool enabled;
  final ValueChanged<Network> onChanged;

  const _LnNetworkPicker({
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    const networks = [Network.mainnet, Network.testnet, Network.testnet4];
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            const Text(
              'Network:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            for (final n in networks)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: Text(n.name),
                  selected: n == value,
                  onSelected: enabled ? (_) => onChanged(n) : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LnStatusChip extends StatelessWidget {
  final _NodeRunState state;

  const _LnStatusChip({required this.state});

  static const _labels = {
    _NodeRunState.idle: 'Idle',
    _NodeRunState.initializing: 'Initialising…',
    _NodeRunState.discovering: 'Discovering peers…',
    _NodeRunState.connecting: 'Connecting…',
    _NodeRunState.syncing: 'Syncing',
    _NodeRunState.stopped: 'Stopped',
    _NodeRunState.error: 'Error',
  };

  static const _colors = {
    _NodeRunState.idle: Colors.grey,
    _NodeRunState.initializing: Colors.orange,
    _NodeRunState.discovering: Colors.orange,
    _NodeRunState.connecting: Colors.orange,
    _NodeRunState.syncing: Colors.green,
    _NodeRunState.stopped: Colors.grey,
    _NodeRunState.error: Colors.red,
  };

  @override
  Widget build(BuildContext context) {
    final label = _labels[state]!;
    final color = _colors[state]!;
    final busy =
        state == _NodeRunState.initializing ||
        state == _NodeRunState.discovering ||
        state == _NodeRunState.connecting ||
        state == _NodeRunState.syncing;

    return Row(
      children: [
        if (busy)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: color),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            border: Border.all(color: color),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

class _LnStatsRow extends StatelessWidget {
  final int headerHeight;
  final int filterHeaderHeight;
  final int filterHeight;
  final String connectedPeer;

  const _LnStatsRow({
    required this.headerHeight,
    required this.filterHeaderHeight,
    required this.filterHeight,
    required this.connectedPeer,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _LnStatCard(
            label: 'Block Headers',
            value: headerHeight > 0 ? headerHeight.toString() : '—',
            icon: Icons.link,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LnStatCard(
            label: 'Filter Headers',
            value: filterHeaderHeight > 0 ? filterHeaderHeight.toString() : '—',
            icon: Icons.filter_list,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LnStatCard(
            label: 'Filters',
            value: filterHeight > 0 ? filterHeight.toString() : '—',
            icon: Icons.filter_alt,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _LnStatCard(
            label: 'Peer',
            value: connectedPeer.isNotEmpty ? connectedPeer : '—',
            icon: Icons.wifi,
          ),
        ),
      ],
    );
  }
}

class _LnStatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _LnStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: Colors.grey),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _LnBestHashCard extends StatelessWidget {
  final String hash;

  const _LnBestHashCard({required this.hash});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.tag, size: 13, color: Colors.grey),
            const SizedBox(width: 6),
            const Text(
              'Best block  ',
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
            Expanded(
              child: SelectableText(
                hash,
                style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
