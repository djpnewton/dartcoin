import 'package:dartcoin/dartcoin.dart';
import 'package:dartcoin/web.dart';

/// Returns [DcWebSocket.connect] – the WebSocket backend for the browser.
///
/// Bitcoin nodes do not speak WebSocket natively; this backend expects a proxy
/// (e.g. websockify) that tunnels the Bitcoin P2P protocol over binary
/// WebSocket frames.
DcSocketFactory socketFactory() => DcWebSocket.connect;
