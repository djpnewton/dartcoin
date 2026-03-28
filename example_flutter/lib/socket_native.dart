import 'package:dartcoin/dartcoin.dart';
import 'package:dartcoin/native.dart';

/// Returns [DcTcpSocket.connect] – the raw TCP backend for native platforms
/// (Linux / macOS / Windows / Android / iOS).
DcSocketFactory socketFactory() => DcTcpSocket.connect;
