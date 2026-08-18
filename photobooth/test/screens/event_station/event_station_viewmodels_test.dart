import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_station_models.dart';
import 'package:photobooth/screens/event_station/event_print_station_viewmodel.dart';
import 'package:photobooth/screens/event_station/event_theme_station_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/event_station_api.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:dio/dio.dart';

class _FakeStationApi extends EventStationApi {
  _FakeStationApi() : super(dio: Dio());

  List<EventThemeStationJob> themeJobs = const [];
  List<EventPrintStationJob> printJobs = const [];
  Object? themeClaimError;
  Object? themeCompleteError;
  Object? printClaimError;
  Object? printCompleteError;
  Object? listError;
  String? completedThemeId;
  bool? lastPrintSuccess;

  @override
  Future<List<EventThemeStationJob>> listThemeJobs({String status = 'PENDING'}) async {
    if (listError != null) throw listError!;
    return themeJobs;
  }

  @override
  Future<EventThemeStationJob> claimThemeJob(String jobId) async {
    if (themeClaimError != null) throw themeClaimError!;
    return themeJobs.firstWhere((j) => j.id == jobId);
  }

  @override
  Future<void> completeThemeJob({required String jobId, required String themeId}) async {
    if (themeCompleteError != null) throw themeCompleteError!;
    completedThemeId = themeId;
  }

  @override
  Future<List<EventPrintStationJob>> listPrintJobs() async {
    if (listError != null) throw listError!;
    return printJobs;
  }

  @override
  Future<EventPrintStationJob> claimPrintJob(String jobId) async {
    if (printClaimError != null) throw printClaimError!;
    return printJobs.firstWhere((j) => j.id == jobId);
  }

  @override
  Future<void> completePrintJob({
    required String jobId,
    required bool success,
    String? error,
  }) async {
    if (printCompleteError != null) throw printCompleteError!;
    lastPrintSuccess = success;
  }
}

XFile _tmpPrintFile() =>
    XFile.fromData(Uint8List.fromList(const [1, 2, 3]), name: 'p.jpg');

ThemeModel _theme(String id) => ThemeModel(
      id: id,
      categoryId: 'c',
      name: 'Look $id',
      description: 'd',
      promptText: 'p',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final waiting = EventThemeStationJob(
    id: 'j1',
    sessionId: 's1',
    status: 'PENDING',
    previewUrls: const ['https://cdn/a.jpg'],
  );

  test('theme station polls claims and completes', () async {
    final api = _FakeStationApi()..themeJobs = [waiting];
    final vm = EventThemeStationViewModel(
      api: api,
      loadThemes: () async => [_theme('t1'), _theme('t2')],
      pollInterval: const Duration(hours: 1),
    );
    vm.startPolling();
    await Future<void>.delayed(Duration.zero);
    expect(vm.queue, hasLength(1));
    expect(await vm.claimNext(), isTrue);
    expect(vm.hasClaimedJob, isTrue);
    expect(vm.selectedThemeId, 't1');
    vm.selectTheme('t2');
    expect(await vm.completeSelected(), isTrue);
    expect(api.completedThemeId, 't2');
    expect(vm.claimed, isNull);
    vm.dispose();
  });

  test('theme station handles claim and complete failures', () async {
    final api = _FakeStationApi()..themeJobs = [waiting];
    final vm = EventThemeStationViewModel(
      api: api,
      loadThemes: () async => [_theme('t1')],
      pollInterval: const Duration(hours: 1),
    );
    await vm.refreshQueue();
    expect(await vm.claimNext(), isTrue);

    api.themeCompleteError = ApiException('nope');
    expect(await vm.completeSelected(), isFalse);
    expect(vm.errorMessage, 'nope');

    api.themeCompleteError = StateError('boom');
    expect(await vm.completeSelected(), isFalse);

    vm.releaseClaimed();
    expect(vm.claimed, isNull);
    expect(await vm.completeSelected(), isFalse);
    api.themeJobs = const [];
    await vm.refreshQueue();
    expect(await vm.claimNext(), isFalse);

    api.themeClaimError = ApiException('taken');
    api.themeJobs = [waiting];
    expect(await vm.claimJob('j1'), isFalse);
    expect(vm.errorMessage, 'taken');

    api.themeClaimError = StateError('x');
    expect(await vm.claimJob('j1'), isFalse);

    api.listError = ApiException('poll-fail');
    await vm.refreshQueue();
    expect(vm.errorMessage, 'poll-fail');
    api.listError = StateError('poll-boom');
    await vm.refreshQueue();
    vm.dispose();
  });

  test('print station prints then completes', () async {
    final job = EventPrintStationJob(
      id: 'p1',
      sessionId: 's1',
      imageUrl: 'https://cdn/p.jpg',
    );
    final api = _FakeStationApi()..printJobs = [job];
    var printed = false;
    final vm = EventPrintStationViewModel(
      api: api,
      printFn: (file, {required printSize}) async {
        printed = true;
      },
        downloadImage: (url) async => _tmpPrintFile(),
      pollInterval: const Duration(hours: 1),
    );
    vm.startPolling();
    await Future<void>.delayed(Duration.zero);
    expect(await vm.printNext(), isTrue);
    expect(printed, isTrue);
    expect(api.lastPrintSuccess, isTrue);
    vm.dispose();
  });

  test('print station completes without a printer callback', () async {
    final job = EventPrintStationJob(
      id: 'p2',
      sessionId: 's1',
      imageUrl: 'https://cdn/p.jpg',
    );
    final api = _FakeStationApi()..printJobs = [job];
    final vm = EventPrintStationViewModel(
      api: api,
      downloadImage: (url) async => _tmpPrintFile(),
      pollInterval: const Duration(hours: 1),
    );
    expect(await vm.printJob(job), isTrue);
    expect(api.lastPrintSuccess, isTrue);
    vm.dispose();
  });

  test('print station claim failure does not complete', () async {
    final job = EventPrintStationJob(
      id: 'p1',
      sessionId: 's1',
      imageUrl: 'https://cdn/p.jpg',
    );
    final api = _FakeStationApi()
      ..printJobs = [job]
      ..printClaimError = ApiException('taken');
    final vm = EventPrintStationViewModel(
      api: api,
      downloadImage: (url) async => _tmpPrintFile(),
      pollInterval: const Duration(hours: 1),
    );
    expect(await vm.printJob(job), isFalse);
    expect(api.lastPrintSuccess, isNull);

    api.printClaimError = null;
    api.printCompleteError = StateError('ignore');
    expect(
      await EventPrintStationViewModel(
        api: api,
        printFn: (file, {required printSize}) async {
          throw StateError('printer');
        },
        downloadImage: (url) async => _tmpPrintFile(),
        pollInterval: const Duration(hours: 1),
      ).printJob(job),
      isFalse,
    );

    api.listError = ApiException('down');
    await vm.refreshQueue();
    api.listError = StateError('x');
    await vm.refreshQueue();
    api.printJobs = const [];
    expect(await vm.printNext(), isFalse);
    vm.dispose();
  });
}
