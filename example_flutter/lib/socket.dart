export 'socket_stub.dart'
    if (dart.library.io) 'socket_native.dart'
    if (dart.library.js_interop) 'socket_web.dart';
