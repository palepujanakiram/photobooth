import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_station_models.dart';
import 'package:photobooth/screens/event_station/event_capture_station_viewmodel.dart';
import 'package:photobooth/screens/event_station/event_print_station_viewmodel.dart';
import 'package:photobooth/screens/event_station/event_theme_station_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/api_service.dart';
import 'package:photobooth/services/event_station_api.dart';
import 'package:photobooth/utils/exceptions.dart';
import 'package:dio/dio.dart';

class _FakeStationApi extends EventStationApi {
  _FakeStationApi() : super(dio: Dio());

  List<EventCaptureStationItem> captures = const [];
  List<EventThemeStationJob> themeJobs = const [];
  List<EventPrintStationJob> printJobs = const [];
  EventStationStats stats = const EventStationStats();
  Object? themeClaimError;
  Object? themeCompleteError;
  Object? printClaimError;
  Object? printCompleteError;
  Object? reissueError;
  Object? listError;
  String? completedThemeId;
  String? reissuedJobId;
  bool? lastPrintSuccess;

  Completer<void>? claimHold;

  @override
  Future<EventStationBoard> fetchBoard() async {
    if (listError != null) throw listError!;
    return EventStationBoard(
      stats: stats,
      captures: captures,
      themeJobs: themeJobs,
      printJobs: printJobs,
    );
  }

  @override
  Future<List<EventThemeStationJob>> listThemeJobs({String status = 'PENDING'}) async {
    if (listError != null) throw listError!;
    return themeJobs;
  }

  @override
  Future<EventThemeStationJob> claimThemeJob(String jobId) async {
    if (claimHold != null) await claimHold!.future;
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
    if (claimHold != null) await claimHold!.future;
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

  @override
  Future<EventPrintStationJob> reissuePrintJob(String jobId) async {
    if (reissueError != null) throw reissueError!;
    reissuedJobId = jobId;
    final src = printJobs.firstWhere((j) => j.id == jobId);
    return EventPrintStationJob(
      id: 'copy-$jobId',
      sessionId: src.sessionId,
      imageUrl: src.imageUrl,
      printSize: src.printSize,
    );
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

  test('capture station polls carousel urls', () async {
    final api = _FakeStationApi()
      ..captures = [
        const EventCaptureStationItem(
          sessionId: 's1',
          status: 'PENDING',
          previewUrls: ['https://cdn/a.jpg', 'https://cdn/b.jpg'],
        ),
      ]
      ..stats = const EventStationStats(captures: 1, themePending: 1);
    final vm = EventCaptureStationViewModel(
      stationApi: api,
      pollInterval: const Duration(hours: 1),
    );
    vm.startPolling();
    await Future<void>.delayed(Duration.zero);
    expect(vm.carouselUrls, ['https://cdn/a.jpg', 'https://cdn/b.jpg']);
    expect(vm.stats.captures, 1);
    expect(vm.captures, hasLength(1));
    expect(vm.statusFilter, 'PENDING');
    vm.setStatusFilter('DONE');
    expect(vm.filteredCaptures, isEmpty);
    api.listError = ApiException('down');
    await vm.refreshBoard();
    expect(vm.errorMessage, 'down');
    api.listError = StateError('x');
    await vm.refreshBoard();
    vm.dispose();
  });

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

  test('print station reissues a finished job', () async {
    final job = EventPrintStationJob(
      id: 'p9',
      sessionId: 's1',
      imageUrl: 'https://cdn/p.jpg',
      status: 'DONE',
      canReissue: true,
    );
    final api = _FakeStationApi()..printJobs = [job];
    final vm = EventPrintStationViewModel(
      api: api,
      downloadImage: (url) async => _tmpPrintFile(),
      pollInterval: const Duration(hours: 1),
    );
    expect(await vm.reissueJob(job), isTrue);
    expect(api.reissuedJobId, 'p9');
    expect(vm.statusFilter, 'PENDING');

    api.reissueError = ApiException('nope');
    expect(await vm.reissueJob(job), isFalse);
    api.reissueError = StateError('x');
    expect(await vm.reissueJob(job), isFalse);
    expect(
      await vm.reissueJob(
        const EventPrintStationJob(
          id: 'p0',
          sessionId: 's',
          imageUrl: 'https://cdn/x.jpg',
        ),
      ),
      isFalse,
    );
    vm.dispose();
  });

  test('theme station filters status buckets', () async {
    final api = _FakeStationApi()
      ..themeJobs = [
        waiting,
        const EventThemeStationJob(
          id: 'j2',
          sessionId: 's2',
          status: 'DONE',
        ),
      ];
    final vm = EventThemeStationViewModel(
      api: api,
      loadThemes: () async => [_theme('t1')],
      pollInterval: const Duration(hours: 1),
    );
    await vm.refreshQueue();
    expect(vm.queue, hasLength(1));
    vm.setStatusFilter('DONE');
    expect(vm.filteredJobs, hasLength(1));
    expect(vm.filteredJobs.single.id, 'j2');
    vm.dispose();
  });

  test('print station ignores overlapping printJob', () async {
    final job = EventPrintStationJob(
      id: 'p8',
      sessionId: 's1',
      imageUrl: 'https://cdn/p.jpg',
    );
    final hold = Completer<void>();
    final api = _FakeStationApi()
      ..printJobs = [job]
      ..claimHold = hold;
    final vm = EventPrintStationViewModel(
      api: api,
      downloadImage: (url) async => _tmpPrintFile(),
      pollInterval: const Duration(hours: 1),
    );
    final first = vm.printJob(job);
    await Future<void>.delayed(Duration.zero);
    expect(await vm.printJob(job), isFalse);
    hold.complete();
    expect(await first, isTrue);
    vm.dispose();
  });

  test('station viewmodels expose stats and skip polls while busy', () async {
    final printHold = Completer<void>();
    final printApi = _FakeStationApi()
      ..printJobs = [
        const EventPrintStationJob(
          id: 'p8',
          sessionId: 's1',
          imageUrl: 'https://cdn/p.jpg',
        ),
      ]
      ..stats = const EventStationStats(captures: 2, printPending: 1)
      ..claimHold = printHold;
    final printVm = EventPrintStationViewModel(
      api: printApi,
      downloadImage: (url) async => _tmpPrintFile(),
      pollInterval: const Duration(milliseconds: 5),
    );
    printVm.startPolling();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    printVm.setStatusFilter('DONE');
    expect(printVm.filteredJobs, isEmpty);
    printVm.setStatusFilter('PENDING');
    expect(printVm.stats.printPending, 1);
    expect(printVm.statusFilter, 'PENDING');
    expect(printVm.filteredJobs, hasLength(1));
    expect(printVm.active, isNull);
    final printing = printVm.printJob(printApi.printJobs.first);
    await Future<void>.delayed(Duration.zero);
    expect(printVm.isBusy, isTrue);
    expect(printVm.active?.id, 'p8');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    printHold.complete();
    expect(await printing, isTrue);
    expect(printVm.errorMessage, isNull);
    printVm.dispose();

    final downloadApi = _FakeStationApi()..printJobs = [printApi.printJobs.first];
    final downloaded = EventPrintStationViewModel(
      api: downloadApi,
      mediaApi: _FakeMediaApi(),
      pollInterval: const Duration(hours: 1),
    );
    expect(await downloaded.printJob(downloadApi.printJobs.first), isTrue);
    downloaded.dispose();

    final failApi = _FakeStationApi()..printJobs = [printApi.printJobs.first];
    final failed = EventPrintStationViewModel(
      api: failApi,
      downloadImage: (url) async => throw ApiException('dl'),
      pollInterval: const Duration(hours: 1),
    );
    expect(await failed.printJob(failApi.printJobs.first), isFalse);
    failed.dispose();

    final themeApi = _FakeStationApi()..themeJobs = [waiting];
    final themeVm = EventThemeStationViewModel(
      api: themeApi,
      loadThemes: () async => [_theme('t1')],
      pollInterval: const Duration(milliseconds: 5),
    );
    await themeVm.refreshQueue();
    await themeVm.claimNext();
    expect(themeVm.stats.captures, 0);
    expect(themeVm.statusFilter, 'PENDING');
    expect(themeVm.looks, isNotEmpty);
    themeVm.startPolling();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(themeVm.hasClaimedJob, isTrue);
    themeVm.dispose();

    final busyTheme = Completer<void>();
    final busyApi = _FakeStationApi()
      ..themeJobs = [waiting]
      ..claimHold = busyTheme;
    final busyVm = EventThemeStationViewModel(
      api: busyApi,
      loadThemes: () async => [_theme('t1')],
      pollInterval: const Duration(milliseconds: 5),
    );
    busyVm.startPolling();
    final claiming = busyVm.claimJob('j1');
    await Future<void>.delayed(Duration.zero);
    expect(busyVm.isBusy, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    busyTheme.complete();
    expect(await claiming, isTrue);
    busyVm.dispose();

    EventPrintStationViewModel().dispose();
    EventThemeStationViewModel().dispose();
    EventCaptureStationViewModel().dispose();

    final defaultThemes = EventThemeStationViewModel(
      api: _FakeStationApi()..themeJobs = [waiting],
      pollInterval: const Duration(milliseconds: 5),
    );
    defaultThemes.startPolling();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await defaultThemes.claimJob('j1');
    defaultThemes.dispose();
  });
}

class _FakeMediaApi extends ApiService {
  _FakeMediaApi() : super(dio: Dio());

  @override
  Future<XFile> downloadImageToTemp(
    String imageUrl, {
    void Function(String message)? onProgress,
  }) async {
    return _tmpPrintFile();
  }
}
