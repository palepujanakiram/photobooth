import 'print_file_impl_stub.dart'
    if (dart.library.io) 'print_file_impl_io.dart'
    if (dart.library.html) 'print_file_impl_web.dart' as impl;

/// Thin abstraction over a platform file used for printing flows.
abstract class PrintFile {
  String get path;
  bool existsSync();
  Future<void> writeAsBytes(List<int> bytes);
  Future<void> delete();

  /// Object to pass into Retrofit client methods that expect a `File` on IO.
  dynamic get retrofitFile;
}

PrintFile createPrintFile(String path) => impl.createPrintFile(path);

