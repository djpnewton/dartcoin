import 'package:dartcoin/dartcoin.dart';

/// Returns the platform [DcSocketFactory].
///
/// Throws on platforms where no socket backend has been wired up.
DcSocketFactory socketFactory() {
  throw UnimplementedError(
    'No DcSocketFactory implementation for this platform. '
    'Use socket_native.dart (dart:io) or socket_web.dart (dart:js_interop).',
  );
}
