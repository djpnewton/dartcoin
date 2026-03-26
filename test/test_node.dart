// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';

import 'package:test/test.dart';

import '../lib/src/bitcoin_core/core_process.dart';
import '../lib/src/block_filter.dart';
import '../lib/src/node.dart';
import '../lib/src/peer.dart';
import '../lib/src/common.dart';

int _getTimestampOfGenesisInHeaderFile(Node node) {
  expect(File(node.blockHeadersFilePath).existsSync(), isTrue);
  final lines = File(node.blockHeadersFilePath).readAsLinesSync();
  for (final line in lines) {
    final fields = line.split(',');
    if (fields.length == 4) {
      final timestamp = int.tryParse(fields[1]);
      if (timestamp != null) {
        return timestamp;
      }
    }
  }
  throw StateError('Genesis block header not found in file');
}

void main() {
  final dummyAddr1 = 'mgTgHVFXFdMEJiMmLhGrxu75waDYjCjDvN';
  final dummyAddr2 = 'mjcNxNEUrMs29U3wSdd7UZ54KGweZAehn6';
  late CoreProcess proc1;
  late CoreProcess proc2;
  late String nodeDataDir;
  late Node node;
  setUp(() async {
    // start two regtest processes
    proc1 = CoreProcess(verbose: false, p2pPort: 18444, rpcPort: 18443);
    proc2 = CoreProcess(verbose: false, p2pPort: 18544, rpcPort: 18543);
    await proc1.start();
    await proc2.start();
    await proc1.waitTillInitialized();
    await proc2.waitTillInitialized();
    // find a unique data directory for the node in the temporary directory
    int count = 0;
    while (Directory(
      '${Directory.systemTemp.path}/dartcoin_node_$count',
    ).existsSync()) {
      count++;
    }
    nodeDataDir = '${Directory.systemTemp.path}/dartcoin_node_$count';
    // initialize the node with the unique data directory
    node = Node(
      network: Network.regtest,
      dataDir: nodeDataDir,
      txProvider: RegtestTxProvider(proc1),
    );
  });
  tearDown(() async {
    // shutdown the node
    node.shutdown();
    // delete the node data directory
    if (Directory(nodeDataDir).existsSync()) {
      Directory(nodeDataDir).deleteSync(recursive: true);
    }
    // stop the regtest processes
    await proc1.stop();
    await proc2.stop();
  });
  test('regtest connection', () async {
    expect(proc1.pid, isNonNegative);
    final bcInfo = await proc1.rpc.getBlockchainInfo();
    expect(bcInfo['chain'], equals('regtest'));
    expect(bcInfo['blocks'], equals(0));
    expect(bcInfo['headers'], equals(0));
    expect(
      bcInfo['bestblockhash'],
      equals(
        '0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206',
      ),
    );
  });
  test('dartcoin reorg - block headers', () async {
    // connect the node to the first regtest process
    node.connect(ip: proc1.p2pHost, port: proc1.p2pPort);
    var gotPeerStatus = await node.waitForPeerStatus(
      proc1.p2pHost,
      proc1.p2pPort,
      PeerStatus.blockFilterGetLatestBlock,
    );
    expect(gotPeerStatus, isTrue);
    // connect the second regtest process to the first
    await proc2.rpc.addNode('${proc1.p2pHost}:${proc1.p2pPort}', 'add');
    // generate 20 blocks in the first process
    await proc1.rpc.generateToAddress(20, dummyAddr1);
    final hash20 = await proc1.rpc.getBestBlockHash();
    // wait for the node to catch up
    await node.waitForBlockCount(20);
    // check if the node has the same best block hash as the first process
    expect(node.bestBlockHash(), equals(hash20));
    // generate a further 20 blocks in the first process
    await proc1.rpc.generateToAddress(20, dummyAddr1);
    // wait for the second process and our node to catch up
    await proc2.rpc.waitForBlockCount(40);
    await node.waitForBlockCount(40);
    final hash40 = await proc1.rpc.getBestBlockHash();
    // get our nodes header file creation time
    expect(node.blockHeadersFilePath, isNotNull);
    final genesisTimestamp = _getTimestampOfGenesisInHeaderFile(node);
    // invalidate the block 20 in the second process
    await proc2.rpc.invalidateBlock(hash20);
    // generate 41 blocks in the second process (reorg the first chain)
    await proc2.rpc.generateToAddress(41, dummyAddr2);
    // record the best block hash after reorg
    final hash60 = await proc2.rpc.getBestBlockHash();
    // wait for the first process and our node to catch up to the reorg
    await proc1.rpc.waitForBlockCount(60);
    await node.waitForBlockCount(60);
    // get the best block hash in the first process and our node
    final bestHashProc1 = await proc1.rpc.getBestBlockHash();
    final bestHashNode = node.bestBlockHash();
    // check if both processes and the node have the same best block hash
    expect(bestHashProc1, equals(hash60));
    expect(bestHashNode, equals(hash60));
    // check that the node's block headers file has been rewritten (_blockHeadersFileWriteOrAppend will rewrite the file if the chain head has reorged past the file head)
    final newGenesisTimestamp = _getTimestampOfGenesisInHeaderFile(node);
    expect(newGenesisTimestamp, greaterThan(genesisTimestamp));
    // invalidate block 60 in the first process
    await proc1.rpc.invalidateBlock(hash60);
    // generate 1 block
    await proc1.rpc.generateToAddress(1, dummyAddr1);
    final rivalHash60 = await proc1.rpc.getBestBlockHash();
    expect(hash60, isNot(rivalHash60));
    // wait for our node to catch up
    await node.waitForHashInChainHeads(rivalHash60);
    final chainHeadHashes = node
        .chainHeads()
        .map((head) => head.header.hashNice())
        .toList();
    // should have 3 chain heads, one for the best chain and one for the rival chain and the original chain
    expect(chainHeadHashes.length, equals(3));
    expect(chainHeadHashes, contains(hash40));
    expect(chainHeadHashes, contains(hash60));
    expect(chainHeadHashes, contains(rivalHash60));
    // should still have the same best block hash
    expect(node.bestBlockHash(), equals(hash60));
    // generate 60 blocks to remove the alternate chain heads
    await proc1.rpc.generateToAddress(60, dummyAddr1);
    // wait for our node to catch up
    await node.waitForBlockCount(120);
    // should have only one chain head now
    expect(node.chainHeads().length, equals(1));
  });
  test('dartcoin reorg - block filter headers', () async {
    // connect the node to the first regtest process
    node.connect(ip: proc1.p2pHost, port: proc1.p2pPort);
    var gotPeerStatus = await node.waitForPeerStatus(
      proc1.p2pHost,
      proc1.p2pPort,
      PeerStatus.blockFilterGetLatestBlock,
    );
    expect(gotPeerStatus, isTrue);
    // connect the second regtest process to the first
    await proc2.rpc.addNode('${proc1.p2pHost}:${proc1.p2pPort}', 'add');
    // generate 20 blocks in the first process
    await proc1.rpc.generateToAddress(20, dummyAddr1);
    // wait for the node to catch up
    await node.waitForBlockCount(20);
    await node.waitForBlockFilterHeaderCount(
      20,
      timeout: const Duration(seconds: 5),
    );
    // check the block filter header at height 20
    final hash20 = await proc1.rpc.getBlockHash(20);
    final blockFilter20 = await proc1.rpc.getBlockFilter(hash20);
    final nodeFilterHeader20 = node.blockFilterHeaderForHeight(20);
    expect(nodeFilterHeader20, isNotNull);
    expect(nodeFilterHeader20, equals(blockFilter20.header));
    // create a reorg by invalidating block 11 and generating 20 new blocks
    await proc2.rpc.waitForBlockCount(20);
    final hash11 = await proc2.rpc.getBlockHash(11);
    await proc2.rpc.invalidateBlock(hash11);
    await proc2.rpc.generateToAddress(20, dummyAddr2);
    // wait for the node to catch up
    await node.waitForBlockCount(30);
    // wait for the block filter header count to reach 30
    await node.waitForBlockFilterHeaderCount(30);
    // check the block filter header at height 30
    final hash30 = await proc2.rpc.getBlockHash(30);
    final blockFilter30 = await proc2.rpc.getBlockFilter(hash30);
    final nodeFilterHeader30 = node.blockFilterHeaderForHeight(30);
    expect(nodeFilterHeader30, isNotNull);
    expect(nodeFilterHeader30, equals(blockFilter30.header));
  });
}
