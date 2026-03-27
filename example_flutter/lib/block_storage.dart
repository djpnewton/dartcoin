export 'block_storage_stub.dart'
    if (dart.library.io) 'block_storage_file.dart' // For mobile/native
    if (dart.library.js_interop) 'block_storage_web.dart'; // For web
