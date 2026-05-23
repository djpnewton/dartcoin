import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:universal_web/web.dart';

import 'dc_socket.dart';

/// [DcSocket] backed by a browser [WebSocket].
///
/// Bitcoin nodes do not speak WebSocket natively, so this backend is intended
/// for use with a proxy that bridges between websocket and raw TCP sockets,
/// Specifically: https://github.com/MutinyWallet/websocket-proxy
/// In the format of [ws://WS_BRIDGE_HOST:WS_BRIDGE_PORT/v1/127_0_0_1/8080]
///
/// Use [DcWebSocket.connect] as the [DcSocketFactory] when targeting the web
/// platform.
class DcWebSocket implements DcSocket {
  final WebSocket _ws;
  final StreamController<Uint8List> _sc;

  DcWebSocket._(this._ws, this._sc);

  /// Opens a WebSocket connection to `ws://[ip]:[port]` and returns a
  /// [DcWebSocket] once the connection is established.
  static Future<DcSocket> connect(String ip, int port, {Duration? timeout}) {
    final sc = StreamController<Uint8List>.broadcast();
    final url =
        '$wsBridgeProtocol://$wsBridgeHost:$wsBridgePort/v1/${ip.replaceAll('.', '_')}/$port';
    final ws = WebSocket(url);
    ws.binaryType = 'arraybuffer';

    final completer = Completer<DcSocket>();
    final socket = DcWebSocket._(ws, sc);

    ws.addEventListener(
      'open',
      ((Event _) {
        if (!completer.isCompleted) completer.complete(socket);
      }).toJS,
    );

    ws.addEventListener(
      'error',
      ((Event e) {
        final err = Exception('WebSocket connection failed: $url (event: $e)');
        if (!completer.isCompleted) {
          completer.completeError(err);
        } else {
          sc.addError(err);
        }
      }).toJS,
    );

    ws.addEventListener(
      'message',
      ((MessageEvent event) {
        final data = event.data;
        if (data != null) {
          // WebSocket.binaryType = 'arraybuffer' guarantees binary frames
          // arrive as ArrayBuffer; cast and convert.
          final bytes = (data as JSArrayBuffer).toDart.asUint8List();
          sc.add(bytes);
        }
      }).toJS,
    );

    ws.addEventListener(
      'close',
      ((CloseEvent e) {
        if (!sc.isClosed) sc.close();
      }).toJS,
    );

    final future = completer.future;
    if (timeout != null) return future.timeout(timeout);
    return future;
  }

  @override
  void add(List<int> data) {
    // Send as a binary ArrayBuffer frame.
    _ws.send(Uint8List.fromList(data).toJS as JSObject);
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _sc.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void destroy() {
    _ws.close();
    if (!_sc.isClosed) _sc.close();
  }
}

/// The WebSocket-bridge [DcSocketFactory] for the browser.
///
/// Configure the bridge address with [setWebSocketBridgeHostPort] before use.
const DcSocketFactory defaultSocketFactory = DcWebSocket.connect;

/// DNS lookup for IPv4 (A) records using DNS-over-HTTPS (DoH).
///
/// Queries Cloudflare's DoH endpoint (`1.1.1.1/dns-query`) over standard
/// HTTPS, which is always reachable from a browser regardless of firewall
/// rules that block raw port-53 TCP.  The [socketFactory] and [dnsServer]
/// parameters are accepted for API compatibility but are not used here.
Future<List<String>> internetAddressLookupIPv4(
  String host,
  DcSocketFactory socketFactory, {
  String dnsServer = '8.8.8.8',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final uri = Uri.https('1.1.1.1', '/dns-query', {'name': host, 'type': 'A'});
  final response = await http
      .get(uri, headers: {'Accept': 'application/dns-json'})
      .timeout(timeout);
  if (response.statusCode != 200) return [];
  final data = jsonDecode(response.body) as Map<String, dynamic>;
  if ((data['Status'] as int?) != 0) return [];
  final answers = (data['Answer'] as List?)?.cast<Map<String, dynamic>>() ?? [];
  return answers
      .where((a) => (a['type'] as int?) == 1) // type 1 = A record
      .map((a) => a['data'] as String)
      .toList();
}
