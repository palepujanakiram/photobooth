export 'device_memory_info_stub.dart'
    if (dart.library.io) 'device_memory_info_io.dart'
    if (dart.library.html) 'device_memory_info_web.dart';
