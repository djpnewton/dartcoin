import 'package:logging/logging.dart';

/// ANSI terminal colors for use with [ColorLogger].
enum LogColor {
  reset('\x1B[0m'),
  black('\x1B[30m'),
  red('\x1B[31m'),
  green('\x1B[32m'),
  yellow('\x1B[33m'),
  blue('\x1B[34m'),
  magenta('\x1B[35m'),
  cyan('\x1B[36m'),
  white('\x1B[37m'),
  brightBlack('\x1B[90m'),
  brightRed('\x1B[91m'),
  brightGreen('\x1B[92m'),
  brightYellow('\x1B[93m'),
  brightBlue('\x1B[94m'),
  brightMagenta('\x1B[95m'),
  brightCyan('\x1B[96m'),
  brightWhite('\x1B[97m');

  final String code;
  const LogColor(this.code);
}

void initGlobalLogger() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    // ignore: avoid_print
    print('${record.level.name}: ${record.time}: ${record.message}');
  });
}

/// A [Logger] wrapper that prefixes messages with an ANSI color code.
///
/// ```dart
/// final log = ColorLogger('MyModule', color: LogColor.cyan);
/// log.info('hello');           // cyan
/// log.info('alert', color: LogColor.red);  // override per-call
/// log.warning('uh oh');        // cyan (default)
///
/// final plain = ColorLogger('MyModule'); // no color by default
/// plain.info('no color');      // unstyled
/// plain.info('red!', color: LogColor.red); // per-call color still works
/// ```
class ColorLogger {
  final Logger _logger;

  /// Default color applied to every log call unless overridden per-call.
  /// If null, messages are passed through unstyled.
  final LogColor? color;

  ColorLogger(String name, {this.color}) : _logger = Logger(name);

  String _wrap(String message, LogColor? c) =>
      c == null ? message : '${c.code}$message${LogColor.reset.code}';

  void info(Object? message, {LogColor? color}) =>
      _logger.info(_wrap(message.toString(), color ?? this.color));

  void warning(Object? message, {LogColor? color}) =>
      _logger.warning(_wrap(message.toString(), color ?? this.color));

  void severe(Object? message, {LogColor? color}) =>
      _logger.severe(_wrap(message.toString(), color ?? this.color));

  void fine(Object? message, {LogColor? color}) =>
      _logger.fine(_wrap(message.toString(), color ?? this.color));

  void finer(Object? message, {LogColor? color}) =>
      _logger.finer(_wrap(message.toString(), color ?? this.color));

  void finest(Object? message, {LogColor? color}) =>
      _logger.finest(_wrap(message.toString(), color ?? this.color));

  void shout(Object? message, {LogColor? color}) =>
      _logger.shout(_wrap(message.toString(), color ?? this.color));

  /// Access the underlying [Logger] directly if needed.
  Logger get logger => _logger;
}
