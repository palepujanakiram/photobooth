import 'print_file.dart';

PrintFile createPrintFile(String path) => _UnsupportedPrintFile(path);

class _UnsupportedPrintFile implements PrintFile {
  _UnsupportedPrintFile(this._path);
  final String _path;

  @override
  bool existsSync() => false;

  @override
  Future<void> delete() async {}

  @override
  String get path => _path;

  @override
  dynamic get retrofitFile => null;

  @override
  Future<void> writeAsBytes(List<int> bytes) async {}
}

