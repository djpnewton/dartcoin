import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:http/http.dart' as http;

final _log = Logger('CoreJsonRpc');

class CoreBlockFilter {
  final String filter;
  final String header;

  CoreBlockFilter({required this.filter, required this.header});
}

class CoreJsonRpc {
  static const String defaultHost = '127.0.0.1';
  static const int defaultPort = 18443; // regtest default port
  static const String defaultUser = 'user';
  static const String defaultPassword = 'password';

  final String host;
  final int port;
  final String username;
  final String password;
  final bool verbose;
  final http.Client _client;

  int _requestId = 0;

  CoreJsonRpc({
    this.host = defaultHost,
    this.port = defaultPort,
    this.username = defaultUser,
    this.password = defaultPassword,
    this.verbose = false,
  }) : _client = http.Client() {
    if (verbose) {
      _log.info('http client connected to: $host:$port');
    }
  }

  String get _baseUrl => 'http://$host:$port';

  String get _authHeader {
    final credentials = base64Encode(utf8.encode('$username:$password'));
    return 'Basic $credentials';
  }

  void close() {
    _client.close();
  }

  Future<Map<String, dynamic>> call(
    String method, [
    List<dynamic>? params,
  ]) async {
    final requestId = ++_requestId;
    final request = {
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      if (params != null) 'params': params,
    };

    final response = await _client.post(
      Uri.parse(_baseUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': _authHeader,
      },
      body: jsonEncode(request),
    );

    if (response.statusCode != 200) {
      throw Exception('HTTP ${response.statusCode}: ${response.body}');
    }

    final responseData = jsonDecode(response.body) as Map<String, dynamic>;

    if (responseData['error'] != null) {
      final error = responseData['error'] as Map<String, dynamic>;
      throw Exception('RPC Error ${error['code']}: ${error['message']}');
    }

    if (verbose) {
      _log.info('RPC call: $method -> ${responseData['result']}');
    }
    return responseData;
  }

  //
  // blockchain RPCs
  //

  Future<String> getBestBlockHash() async {
    final response = await call('getbestblockhash');
    return response['result'] as String;
  }

  Future<Map<String, dynamic>> getBlock(
    String blockHash, [
    int? verbosity,
  ]) async {
    final response = await call('getblock', [blockHash, verbosity]);
    return response['result'] as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> getBlockchainInfo() async {
    final response = await call('getblockchaininfo');
    return response['result'] as Map<String, dynamic>;
  }

  Future<int> getBlockCount() async {
    final response = await call('getblockcount');
    return response['result'] as int;
  }

  Future<CoreBlockFilter> getBlockFilter(
    String blockHash, [
    String filterType = 'basic',
  ]) async {
    final response = await call('getblockfilter', [blockHash, filterType]);
    return CoreBlockFilter(
      filter: response['result']['filter'] as String,
      header: response['result']['header'] as String,
    );
  }

  Future<String> getBlockHash(int height) async {
    final response = await call('getblockhash', [height]);
    return response['result'] as String;
  }

  Future<bool> waitForBlockCount(
    int targetCount, {
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final startTime = DateTime.now();
    while (DateTime.now().difference(startTime) < timeout) {
      final count = await getBlockCount();
      if (count >= targetCount) {
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  //
  // generating RPCs
  //

  Future<List<dynamic>> generateToAddress(int nblocks, String address) async {
    final response = await call('generatetoaddress', [nblocks, address]);
    return response['result'] as List<dynamic>;
  }

  //
  // network RPCs
  //

  Future<void> addNode(String node, String command) async {
    await call('addnode', [node, command]);
  }

  Future<List<dynamic>> getPeerInfo() async {
    final response = await call('getpeerinfo');
    return response['result'] as List<dynamic>;
  }

  //
  // wallet RPCs
  //

  Future<String> getNewAddress([String? label]) async {
    final params = label != null ? [label] : null;
    final response = await call('getnewaddress', params);
    return response['result'] as String;
  }

  Future<Map<String, dynamic>> getWalletInfo() async {
    final response = await call('getwalletinfo');
    return response['result'] as Map<String, dynamic>;
  }

  //
  // hidden RPCs
  //

  Future<void> invalidateBlock(String blockHash) async {
    await call('invalidateblock', [blockHash]);
  }

  Future<void> reconsiderBlock(String blockHash) async {
    await call('reconsiderblock', [blockHash]);
  }
}
