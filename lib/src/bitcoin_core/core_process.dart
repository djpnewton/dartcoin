import 'dart:io';

import 'package:logging/logging.dart';

import 'core_rpc.dart';

final _log = Logger('CoreProcess');

Future<void> _processCleanup(
  Process? process,
  String dataDir, {
  bool noDataDirCleanup = false,
  bool verbose = false,
}) async {
  process?.kill();
  if (verbose) {
    _log.info('Core process killed (PID: ${process?.pid})');
  }
  final exitCode = await process?.exitCode;
  if (verbose) {
    _log.info(
      'Core process exited (PID: ${process?.pid}, exit code: $exitCode)',
    );
  }
  // clean up the data directory
  if (!noDataDirCleanup) {
    // once the process is stopped we will be able to delete the data directory
    while (Directory(dataDir).existsSync()) {
      Directory(dataDir).deleteSync(recursive: true);
      if (verbose) {
        _log.info('Data directory $dataDir deleted');
      }
    }
  }
}

class CoreProcess {
  late final String _executablePath;
  late final String _dataDir;
  final bool verbose;
  Process? _process;
  late final Finalizer<Process> _processFinalizer;
  bool _coreInitialized = false;
  late final int _p2pPort;
  late final int _rpcPort;
  late final CoreJsonRpc _rpc;

  int get p2pPort => _p2pPort;
  String get p2pHost => '127.0.0.1';
  CoreJsonRpc get rpc => _rpc;
  String get rpcHost => '127.0.0.1';
  int get rpcPort => _rpcPort;

  CoreProcess({
    String? executablePath,
    String? dataDir,
    this.verbose = false,
    int p2pPort = 18444,
    int rpcPort = 18443,
  }) {
    // init p2p
    _p2pPort = p2pPort;
    // init rpc
    _rpcPort = rpcPort;
    _rpc = CoreJsonRpc(port: _rpcPort);
    _log.info('RPC host: $rpcHost, port: $_rpcPort');
    // initialize the executable path
    if (executablePath == null || executablePath.isEmpty) {
      // check the BITCOIN_CORE_BIN environment variable
      executablePath = Platform.environment['BITCOIN_CORE_BIN'];
    }
    if (executablePath == null || executablePath.isEmpty) {
      // find the OS-specific executable path
      final pathCandidates = <String>[];
      if (Platform.isWindows) {
        pathCandidates.add('C:\\Program Files\\Bitcoin\\daemon\\bitcoind.exe');
      } else {
        throw UnsupportedError(
          '${Platform.operatingSystem}: please specify the executable path',
        );
      }
      bool found = false;
      for (final path in pathCandidates) {
        if (File(path).existsSync()) {
          _executablePath = path;
          found = true;
          break;
        }
      }
      if (!found) {
        throw FileSystemException(
          'Bitcoin Core executable not found. Please specify the path.',
        );
      }
    } else {
      _executablePath = executablePath;
    }
    // initialize the data directory
    if (dataDir == null || dataDir.isEmpty) {
      int count = 0;
      while (Directory(
        '${Directory.systemTemp.path}/dartcoin_test_${_rpcPort}_$count',
      ).existsSync()) {
        count++;
      }
      _dataDir =
          '${Directory.systemTemp.path}/dartcoin_test_${_rpcPort}_$count';
    } else {
      _dataDir = dataDir;
    }
    if (!Directory(_dataDir).existsSync()) {
      Directory(_dataDir).createSync(recursive: true);
      if (verbose) {
        _log.info('Data directory $_dataDir created');
      }
    }
    // initialize the finalizer
    _processFinalizer = Finalizer<Process>((process) {
      _processCleanup(process, _dataDir, verbose: verbose);
    });
  }

  int get pid => _process?.pid ?? -1;

  Future<void> start() async {
    if (_process != null) {
      throw StateError('Core process is already running');
    }
    _process = await Process.start(
      _executablePath,
      [
        '-regtest',
        '-port=$_p2pPort',
        '-bind=$p2pHost',
        '-server',
        '-rpcport=$_rpcPort',
        '-rpcbind=$rpcHost',
        '-rpcallowip=$rpcHost/24',
        '-rpcuser=user',
        '-rpcpassword=password',
        '-datadir=$_dataDir',
        '-debug=net',
      ],
      //mode: ProcessStartMode.detached
    );
    // drain stdout/stderr streams so the process does not block
    _process!.stdout.listen((data) {
      // convert int list to string
      final output = String.fromCharCodes(data);
      output.split('\n').forEach((line) {
        if (line.isNotEmpty) {
          // set _coreInitialized to true when we hit a specific log line
          if (line.contains('dnsseed thread exit')) {
            _coreInitialized = true;
            if (verbose) {
              _log.info('Core process initialized (PID: ${_process!.pid})');
            }
          }
        }
      });
    });
    _process!.stderr.listen((data) {
      // drop the data to avoid blocking (can read debug.log)
    });
    _processFinalizer.attach(this, _process!);
    if (verbose) {
      _log.info('Core process started (PID: ${_process!.pid})');
    }
  }

  Future<bool> waitTillInitialized({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    if (_coreInitialized) return true;
    final endTime = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(endTime)) {
      if (_coreInitialized) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    return false;
  }

  Future<void> stop({bool noDataDirCleanup = false}) async {
    await _processCleanup(
      _process,
      _dataDir,
      noDataDirCleanup: noDataDirCleanup,
      verbose: verbose,
    );
    _process = null;
    _processFinalizer.detach(this);
    _coreInitialized = false;
  }
}
