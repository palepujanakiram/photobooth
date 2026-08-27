import 'package:photobooth/services/kiosk_manager.dart';

class FakeKioskManager extends KioskManager {
  FakeKioskManager({this.code, this.operatingModeOffline = false});

  String? code;
  String? lastSavedCode;
  bool operatingModeOffline;

  @override
  Future<String?> getKioskCode() async => code;

  @override
  Future<void> setKioskCode(String? kioskCode) async {
    lastSavedCode = kioskCode;
    code = kioskCode;
  }

  @override
  Future<bool> isOperatingModeOffline() async => operatingModeOffline;
}
