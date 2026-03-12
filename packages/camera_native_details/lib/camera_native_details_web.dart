import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// Web implementation: no native code. Dart API returns default values via conditional import.
class CameraNativeDetailsWeb {
  static void registerWith(Registrar registrar) {
    // No method channel on web; lib uses conditional import and returns default values.
  }
}
