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
  Future<void> writeAsBytes(List<int> bytes) async {}

  @override
  Future<void> delete() async {}

  @override
  dynamic get retrofitFile => null;
}

