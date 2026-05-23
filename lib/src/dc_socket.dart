import 'dart:async';
import 'dart:typed_data';

export 'dc_socket_factory_stub.dart'
    if (dart.library.io) 'dc_socket_io.dart'
    if (dart.library.js_interop) 'dc_socket_web.dart'
    show defaultSocketFactory, internetAddressLookupIPv4;

/// variables to hold the WebSocket bridge host and port, with a setter function
var wsBridgeProtocol = 'ws';
var wsBridgeHost = 'localhost';
var wsBridgePort = 3001;
void setWebSocketBridgeHostPort(String protocol, String host, int port) {
  wsBridgeProtocol = protocol;
  wsBridgeHost = host;
  wsBridgePort = port;
}

/// Minimal abstraction over a bidirectional binary stream so that [Peer] can
/// work on top of both a raw TCP socket ([DcTcpSocket]) and a WebSocket proxy
/// ([DcWebSocket]) without carrying platform-specific imports.
abstract interface class DcSocket {
  /// Sends [data] to the remote end.
  void add(List<int> data);

  /// Subscribes to the incoming byte stream.
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  });

  /// Closes the connection immediately, discarding any buffered data.
  void destroy();
}

/// Signature of a factory that opens a [DcSocket] to [ip]:[port].
typedef DcSocketFactory =
    Future<DcSocket> Function(String ip, int port, {Duration? timeout});
