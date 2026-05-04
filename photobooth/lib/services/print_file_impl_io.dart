import 'dart:io';

import 'print_file.dart';

PrintFile createPrintFile(String path) => IoPrintFile(File(path));

class IoPrintFile implements PrintFile {
  IoPrintFile(this._file);
  final File _file;

  @override
  String get path => _file.path;

  @override
  bool existsSync() => _file.existsSync();

  @override
  Future<void> writeAsBytes(List<int> bytes) => _file.writeAsBytes(bytes);

  @override
  Future<void> delete() => _file.delete();

  @override
  dynamic get retrofitFile => _file;
}

