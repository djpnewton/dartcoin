import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'dc_socket.dart';

/// [DcSocket] backed by a raw TCP [Socket] from `dart:io`.
///
/// Use [DcTcpSocket.connect] as the [DcSocketFactory] when running on a native
/// platform (Linux / macOS / Windows / Android / iOS).
class DcTcpSocket implements DcSocket {
  final Socket _socket;

  DcTcpSocket._(this._socket);

  /// Connects to [ip]:[port] and returns a [DcTcpSocket].
  static Future<DcSocket> connect(
    String ip,
    int port, {
    Duration? timeout,
  }) async {
    final socket = await Socket.connect(
      ip,
      port,
      timeout: timeout ?? const Duration(seconds: 5),
    );
    return DcTcpSocket._(socket);
  }

  @override
  void add(List<int> data) {
    _socket.add(data);
  }

  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event) onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _socket.listen(
      (data) {
        onData(data);
      },
      onError: onError,
      onDone: () {
        onDone?.call();
      },
      cancelOnError: cancelOnError,
    );
  }

  @override
  void destroy() {
    _socket.destroy();
  }
}

/// The raw TCP [DcSocketFactory] for native platforms (Linux / macOS / Windows / Android / iOS).
const DcSocketFactory defaultSocketFactory = DcTcpSocket.connect;

/// DNS lookup for IPv4 (A) records using [dart:io]'s [InternetAddress.lookup].
///
/// The [socketFactory] and [dnsServer] parameters are accepted for API
/// compatibility with the web counterpart but are not used here – the OS
/// resolver handles everything.
Future<List<String>> internetAddressLookupIPv4(
  String host,
  DcSocketFactory socketFactory, {
  String dnsServer = '8.8.8.8',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final addresses = await InternetAddress.lookup(
    host,
    type: InternetAddressType.IPv4,
  ).timeout(timeout);
  return addresses.map((a) => a.address).toList();
}
