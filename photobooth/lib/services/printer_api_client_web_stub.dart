// Web stub for File and Platform types
// On web, we'll handle file conversion differently
class File {
  final String path;
  File(this.path);
}

class Platform {
  static const pathSeparator = '/';
}
