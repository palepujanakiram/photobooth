import '../models/kiosk_info_model.dart';
import 'catalog_disk_cache.dart';

/// Persists [KioskInfoModel] from `/api/kiosk/by-code` so splash can resume
/// offline after this device has bound the code at least once online.
class KioskInfoDiskCache {
  KioskInfoDiskCache({CatalogDiskCache? diskCache})
      : _disk = diskCache ?? CatalogDiskCache();

  final CatalogDiskCache _disk;

  static String diskKey(String kioskCode) {
    final safe = kioskCode.trim().toUpperCase().replaceAll(
          RegExp(r'[^a-zA-Z0-9._-]'),
          '_',
        );
    return 'kiosk_${safe.isEmpty ? 'default' : safe}';
  }

  Future<void> save(KioskInfoModel info) async {
    if (!info.isValid) return;
    await _disk.writeJson(diskKey(info.code), info.toJson());
  }

  Future<KioskInfoModel?> read(String kioskCode) async {
    final code = kioskCode.trim().toUpperCase();
    if (code.isEmpty) return null;
    final raw = await _disk.readJson(diskKey(code));
    if (raw is! Map) return null;
    final model = KioskInfoModel.fromJson(Map<String, dynamic>.from(raw));
    if (!model.isValid) return null;
    // Require exact code match so a corrupted/renamed file cannot bind wrong.
    if (model.code.trim().toUpperCase() != code) return null;
    return model;
  }

  Future<void> delete(String kioskCode) async {
    await _disk.delete(diskKey(kioskCode));
  }
}
