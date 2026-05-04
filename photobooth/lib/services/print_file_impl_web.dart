import 'print_file.dart';

PrintFile createPrintFile(String path) => WebPrintFile(path);

class WebPrintFile implements PrintFile {
  WebPrintFile(this._path);
  final String _path;

  @override
  String get path => _path;

  @override
  bool existsSync() => false;

  @override
  Future<void> writeAsBytes(List<int> bytes) async {
    throw UnsupportedError(
      'PrintFile.writeAsBytes is not supported on this platform; '
      'use the bytes-direct print path instead.',
    );
  }

  @override
  Future<void> delete() async {
    throw UnsupportedError(
      'PrintFile.delete is not supported on this platform.',
    );
  }

  @override
  dynamic get retrofitFile => null;
}

