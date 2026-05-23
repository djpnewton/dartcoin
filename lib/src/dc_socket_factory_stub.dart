import 'dart:async';

import 'dc_socket.dart';

Future<DcSocket> _unsupportedSocketFactory(
  String ip,
  int port, {
  Duration? timeout,
}) {
  throw UnsupportedError(
    'No DcSocketFactory implementation for this platform. '
    'Ensure you are running on a supported platform (native or web).',
  );
}

/// Placeholder [DcSocketFactory] used on platforms where neither `dart:io`
/// nor `dart:js_interop` is available. Always throws [UnsupportedError].
const DcSocketFactory defaultSocketFactory = _unsupportedSocketFactory;

/// Placeholder DNS lookup - always throws [UnsupportedError].
Future<List<String>> internetAddressLookupIPv4(
  String host,
  DcSocketFactory socketFactory, {
  String dnsServer = '8.8.8.8',
  Duration timeout = const Duration(seconds: 5),
}) {
  throw UnsupportedError('DNS lookup not available on this platform.');
}
