// ignore_for_file: avoid_relative_lib_imports

import 'package:logging/logging.dart';
import 'package:test/test.dart';

import '../lib/src/bitcoin_core/core_process.dart';
//import '../lib/src/node.dart';

void initLogger() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
}

void main() {
  initLogger();
  late CoreProcess proc;
  setUp(() async {
    proc = CoreProcess(verbose: true);
    await proc.start();
    await proc.waitTillInitialized();
  });
  tearDown(() {
    proc.stop(noDataDirCleanup: true);
  });
  test('example', () async {
    expect(proc.pid, isNonNegative);
    final bcInfo = await proc.rpc.getBlockchainInfo();
    expect(bcInfo['chain'], equals('regtest'));
    expect(bcInfo['blocks'], equals(0));
    expect(bcInfo['headers'], equals(0));
    expect(bcInfo['bestblockhash'], equals('0f9188f13cb7b2c71f2a335e3a4fc328bf5beb436012afca590b1a11466e2206'));
  });
}
