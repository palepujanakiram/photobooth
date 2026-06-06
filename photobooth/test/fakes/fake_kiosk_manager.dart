import 'package:photobooth/services/kiosk_manager.dart';

class FakeKioskManager extends KioskManager {
  FakeKioskManager({this.code});

  String? code;
  String? lastSavedCode;

  @override
  Future<String?> getKioskCode() async => code;

  @override
  Future<void> setKioskCode(String? kioskCode) async {
    lastSavedCode = kioskCode;
    code = kioskCode;
  }
}
