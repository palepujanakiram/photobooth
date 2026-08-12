import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/kiosk_info_model.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/kiosk_manager.dart';
import 'package:photobooth/utils/classic_photos_enabled_sync.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../fakes/fake_api_service.dart';
import '../helpers/mock_api_dio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await KioskManager().clearClassicPhotosEnabled();
    await KioskManager().clearKioskCode();
    KioskManager.resetClassicPhotosCacheForTests();
  });

  test('syncClassicPhotosEnabled updates stale false from API true', () async {
    final km = KioskManager();
    await km.setKioskCode('FOTO');
    await km.setClassicPhotosEnabled(false);
    expect(await km.isClassicPhotosEnabled(), isFalse);

    final mock = createMockApiDio();
    final api = ApiService(dio: mock.dio);
    mock.adapter.onGet(
      '/api/kiosk/by-code/FOTO',
      (server) => server.reply(200, {
        'id': 'k1',
        'code': 'FOTO',
        'classicPhotosEnabled': true,
      }),
    );

    final enabled = await syncClassicPhotosEnabled(api: api, kiosk: km);
    expect(enabled, isTrue);
    expect(await km.isClassicPhotosEnabled(), isTrue);
  });

  test('syncClassicPhotosEnabled falls back to cache when API misses', () async {
    final km = KioskManager();
    await km.setKioskCode('FOTO');
    await km.setClassicPhotosEnabled(false);

    final mock = createMockApiDio();
    final api = ApiService(dio: mock.dio);
    mock.adapter.onGet(
      '/api/kiosk/by-code/FOTO',
      (server) => server.reply(404, {}),
    );

    final enabled = await syncClassicPhotosEnabled(api: api, kiosk: km);
    expect(enabled, isFalse);
  });

  test('syncClassicPhotosEnabled with no kiosk code uses cache default', () async {
    final km = KioskManager();
    final mock = createMockApiDio();
    final api = ApiService(dio: mock.dio);
    expect(await syncClassicPhotosEnabled(api: api, kiosk: km), isTrue);
  });

  test('syncClassicPhotosEnabled falls back to cache when API throws', () async {
    final km = KioskManager();
    await km.setKioskCode('FOTO');
    await km.setClassicPhotosEnabled(true);

    final enabled = await syncClassicPhotosEnabled(
      api: _ThrowingKioskApi(),
      kiosk: km,
    );
    expect(enabled, isTrue);
  });
}

class _ThrowingKioskApi extends FakeApiService {
  @override
  Future<KioskInfoModel?> fetchKioskByCode(String kioskCode) async {
    throw Exception('network down');
  }
}
