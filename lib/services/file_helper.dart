// Export the correct implementation based on platform
export 'file_helper_io.dart'
    if (dart.library.html) 'file_helper_web.dart'
    if (dart.library.js) 'file_helper_web.dart';

