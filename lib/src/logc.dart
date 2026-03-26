/// A minimal self-contained logging framework with ANSI color support.
///
/// Initialise once at startup with [initConsoleLogger] or
/// [initCustomLogger], then create per-module loggers with [ColorLogger]:
///
/// ```dart
/// final log = ColorLogger('MyModule', color: LogColor.cyan);
/// log.info('hello');                         // cyan (default)
/// log.warning('alert', color: LogColor.red); // per-call override
/// ```
library;

/// Severity levels in ascending order.
enum LogLevel {
  finest,
  finer,
  fine,
  info,
  warning,
  severe,
  shout;

  bool operator >=(LogLevel other) => index >= other.index;
}

/// ANSI terminal color codes.
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

class LogRecord {
  final LogLevel level;
  final String loggerName;
  final String message;
  final DateTime time;

  /// Optional ANSI color to apply when rendering this record.
  final LogColor? color;

  LogRecord({
    required this.level,
    required this.loggerName,
    required this.message,
    required this.time,
    this.color,
  });
}

void Function(LogRecord)? _handler;
LogLevel _minLevel = LogLevel.info;

/// Configure logging to print colored output to the console.
///
/// Records below [level] are silently dropped.
void initConsoleLogger({LogLevel level = LogLevel.info}) {
  _minLevel = level;
  _handler = (record) {
    String msg = record.message;
    if (record.color != null) {
      msg = '${record.color!.code}$msg${LogColor.reset.code}';
    }
    final t = record.time;
    final ts =
        '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    // ignore: avoid_print
    print(
      '${record.level.name.toUpperCase().padRight(7)}: $ts: ${record.loggerName} : $msg',
    );
  };
}

/// Configure logging with a custom handler function.
///
/// Records below [level] are silently dropped before [handler] is called.
void initCustomLogger(
  void Function(LogRecord record) handler, {
  LogLevel level = LogLevel.info,
}) {
  _minLevel = level;
  _handler = handler;
}

void _emit(LogRecord record) {
  if (record.level >= _minLevel) _handler?.call(record);
}

/// A named logger that supports per-instance and per-call ANSI color.
///
/// ```dart
/// final log = ColorLogger('MyModule', color: LogColor.cyan);
/// log.info('hello');                         // cyan (module default)
/// log.warning('alert', color: LogColor.red); // per-call override
/// ```
class ColorLogger {
  final String name;

  /// Default color applied to every log call unless overridden per-call.
  final LogColor? color;

  const ColorLogger(this.name, {this.color});

  void _log(LogLevel level, Object? message, LogColor? callColor) => _emit(
    LogRecord(
      level: level,
      loggerName: name,
      message: message.toString(),
      time: DateTime.now(),
      color: callColor ?? color,
    ),
  );

  void finest(Object? message, {LogColor? color}) =>
      _log(LogLevel.finest, message, color);

  void finer(Object? message, {LogColor? color}) =>
      _log(LogLevel.finer, message, color);

  void fine(Object? message, {LogColor? color}) =>
      _log(LogLevel.fine, message, color);

  void info(Object? message, {LogColor? color}) =>
      _log(LogLevel.info, message, color);

  void warning(Object? message, {LogColor? color}) =>
      _log(LogLevel.warning, message, color);

  void severe(Object? message, {LogColor? color}) =>
      _log(LogLevel.severe, message, color);

  void shout(Object? message, {LogColor? color}) =>
      _log(LogLevel.shout, message, color);
}
