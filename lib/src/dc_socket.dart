import 'dart:async';
import 'dart:typed_data';

export 'dc_socket_factory_stub.dart'
    if (dart.library.io) 'dc_socket_io.dart'
    if (dart.library.js_interop) 'dc_socket_web.dart'
    show defaultSocketFactory;

/// variables to hold the WebSocket bridge host and port, with a setter function
var wsBridgeHost = 'localhost';
var wsBridgePort = 3001;
void setWebSocketBridgeHostPort(String host, int port) {
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

/// DNS-over-TCP (RFC 1035 §4.2.2, RFC 7766) lookup of IPv4 (A) records for
/// [host], using [socketFactory] to open the transport connection.
///
/// This is a drop-in alternative to `InternetAddress.lookup` (from `dart:io`)
/// that works on platforms where that API is unavailable (e.g. Flutter Web),
/// because it uses [socketFactory] — which on web routes through the WebSocket
/// bridge — instead of the OS resolver.
///
/// [dnsServer] defaults to Google's `8.8.8.8`. [timeout] controls both the
/// socket-connect and the response-wait deadline (default 5 s).
Future<List<String>> internetAddressLookupIPv4(
  String host,
  DcSocketFactory socketFactory, {
  String dnsServer = '8.8.8.8',
  Duration timeout = const Duration(seconds: 5),
}) async {
  final socket = await socketFactory(dnsServer, 53, timeout: timeout);

  final completer = Completer<List<String>>();
  final buf = <int>[];

  final sub = socket.listen(
    (data) {
      buf.addAll(data);
      // DNS/TCP: first 2 bytes = big-endian message length
      if (buf.length < 2) return;
      final msgLen = (buf[0] << 8) | buf[1];
      if (buf.length < 2 + msgLen) return;
      final msg = Uint8List.fromList(buf.sublist(2, 2 + msgLen));
      if (!completer.isCompleted) completer.complete(_parseDnsARecords(msg));
    },
    onDone: () {
      if (!completer.isCompleted) completer.complete([]);
    },
    onError: (Object e) {
      if (!completer.isCompleted) completer.completeError(e);
    },
  );

  // Build and send the query with its 2-byte TCP length prefix.
  final query = _buildDnsQuery(host);
  socket.add([(query.length >> 8) & 0xff, query.length & 0xff, ...query]);

  try {
    return await completer.future.timeout(timeout);
  } finally {
    await sub.cancel();
    socket.destroy();
  }
}

/// Builds a minimal DNS query for the A records of [host].
Uint8List _buildDnsQuery(String host) {
  final b = BytesBuilder();
  // Header
  b.add([0x00, 0x01]); // transaction ID
  b.add([0x01, 0x00]); // flags: standard query, RD=1
  b.add([0x00, 0x01]); // QDCOUNT = 1
  b.add([0x00, 0x00]); // ANCOUNT = 0
  b.add([0x00, 0x00]); // NSCOUNT = 0
  b.add([0x00, 0x00]); // ARCOUNT = 0
  // QNAME: length-prefixed labels terminated by 0x00
  for (final label in host.split('.')) {
    final bytes = label.codeUnits;
    b.addByte(bytes.length);
    b.add(bytes);
  }
  b.addByte(0x00); // end of name
  b.add([0x00, 0x01]); // QTYPE  = A (1)
  b.add([0x00, 0x01]); // QCLASS = IN (1)
  return b.toBytes();
}

/// Parses a raw DNS response message and returns all IPv4 addresses from the
/// A records in the answer section.
List<String> _parseDnsARecords(Uint8List msg) {
  if (msg.length < 12) return [];
  final qdCount = (msg[4] << 8) | msg[5];
  final anCount = (msg[6] << 8) | msg[7];

  var offset = 12;

  // Skip question section.
  for (var i = 0; i < qdCount && offset < msg.length; i++) {
    offset = _dnsSkipName(msg, offset);
    offset += 4; // QTYPE + QCLASS
  }

  // Parse answer section.
  final ips = <String>[];
  for (var i = 0; i < anCount && offset + 10 <= msg.length; i++) {
    offset = _dnsSkipName(msg, offset);
    if (offset + 10 > msg.length) break;
    final type = (msg[offset] << 8) | msg[offset + 1];
    // class at [offset+2..3], TTL at [offset+4..7] — skipped
    final rdLen = (msg[offset + 8] << 8) | msg[offset + 9];
    offset += 10;
    if (type == 1 && rdLen == 4 && offset + 4 <= msg.length) {
      // A record: 4-byte IPv4 address
      ips.add(
        '${msg[offset]}.${msg[offset + 1]}.${msg[offset + 2]}.${msg[offset + 3]}',
      );
    }
    offset += rdLen;
  }
  return ips;
}

/// Advances [offset] past a DNS name field, following compression pointers.
int _dnsSkipName(Uint8List msg, int offset) {
  while (offset < msg.length) {
    final len = msg[offset];
    if (len == 0) return offset + 1; // end of name
    if ((len & 0xC0) == 0xC0) return offset + 2; // compression pointer
    offset += 1 + len;
  }
  return offset;
}
