import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_station_models.dart';

void main() {
  test('parses theme jobs from {jobs: []}', () {
    final jobs = parseEventThemeJobs({
      'jobs': [
        {
          'id': 'j1',
          'sessionId': 's1',
          'status': 'PENDING',
          'previewUrls': ['https://cdn/a.jpg', ''],
        },
        {'id': '', 'sessionId': 's2'},
      ],
    });
    expect(jobs, hasLength(1));
    expect(jobs.first.id, 'j1');
    expect(jobs.first.previewUrls, ['https://cdn/a.jpg']);
  });

  test('parses nested claimed theme job', () {
    final job = EventThemeStationJob.fromJson({
      'job': {'id': 'j2', 'sessionId': 's2', 'status': 'CLAIMED'},
      'previewUrls': ['https://cdn/b.jpg'],
    });
    expect(job.isValid, isTrue);
    expect(job.status, 'CLAIMED');
    expect(job.previewUrls, ['https://cdn/b.jpg']);
  });

  test('parses print jobs from a list', () {
    final jobs = parseEventPrintJobs([
      {
        'id': 'p1',
        'sessionId': 's1',
        'imageUrl': 'https://cdn/p.jpg',
        'printSize': 's6x4',
      },
    ]);
    expect(jobs.single.printSize, 's6x4');
    expect(jobs.single.isValid, isTrue);
    expect(jobs.single.status, 'PENDING');
  });

  test('nested print job defaults print size', () {
    final job = EventPrintStationJob.fromJson({
      'job': {'id': 'p2', 'sessionId': 's2', 'imageUrl': '/api/img/x'},
    });
    expect(job.printSize, 's4x6');
  });

  test('empty payloads yield no jobs', () {
    expect(parseEventThemeJobs(null), isEmpty);
    expect(parseEventPrintJobs({'jobs': <Object>[]}), isEmpty);
  });

  test('parses station board and buckets print PRINTING to CLAIMED', () {
    final board = EventStationBoard.fromJson({
      'stats': {
        'captures': 3,
        'themePending': 1,
        'themeClaimed': 0,
        'themeDone': 2,
        'printPending': 1,
        'printClaimed': 1,
        'printDone': 4,
      },
      'captures': [
        {
          'sessionId': 's1',
          'status': 'PENDING',
          'previewUrls': ['https://cdn/a.jpg'],
        },
      ],
      'themeJobs': [
        {'id': 'j1', 'sessionId': 's1', 'status': 'SKIPPED'},
      ],
      'printJobs': [
        {
          'id': 'p1',
          'sessionId': 's1',
          'imageUrl': 'https://cdn/p.jpg',
          'status': 'PRINTING',
        },
        {
          'id': 'p2',
          'sessionId': 's1',
          'imageUrl': 'https://cdn/q.jpg',
          'status': 'DONE',
          'canReissue': true,
        },
      ],
    });
    expect(board.stats.captures, 3);
    expect(board.captures.single.sessionId, 's1');
    expect(board.themeJobs.single.status, 'DONE');
    expect(board.printJobs.first.status, 'CLAIMED');
    expect(board.printJobs.last.canReissue, isTrue);
    expect(captureCarouselUrls(board.captures), ['https://cdn/a.jpg']);
    expect(
      stationStatusCount(board.printJobs, 'CLAIMED', (j) => j.status),
      1,
    );
  });

  test('board ignores empty maps', () {
    expect(EventStationBoard.fromJson(null).captures, isEmpty);
    expect(EventStationStats.fromJson({}).captures, 0);
  });

  test('parses stats from nums and totals them', () {
    final stats = EventStationStats.fromJson({
      'captures': 1.0,
      'themePending': '2',
      'themeClaimed': 1,
      'themeDone': 3,
      'printPending': 4,
      'printClaimed': 0,
      'printDone': 5,
    });
    expect(stats.captures, 1);
    expect(stats.themeTotal, 6);
    expect(stats.printTotal, 9);
  });

  test('buckets unknown and failed print statuses', () {
    expect(
      EventCaptureStationItem.fromJson({'id': '', 'previewUrls': []}).isValid,
      isFalse,
    );
    final failed = EventPrintStationJob.fromJson({
      'id': 'p3',
      'sessionId': 's3',
      'imageUrl': 'https://cdn/f.jpg',
      'rawStatus': 'FAILED',
      'status': 'PENDING',
    });
    expect(failed.status, 'PENDING');
    expect(failed.canReissue, isTrue);
    final claimed = EventPrintStationJob.fromJson({
      'id': 'p4',
      'sessionId': 's4',
      'imageUrl': 'https://cdn/c.jpg',
      'status': 'CLAIMED',
    });
    expect(claimed.canReissue, isTrue);
    expect(
      itemsForStationStatus([claimed], 'claimed', (j) => j.status),
      hasLength(1),
    );
  });

  test('stamps guest session and station codes onto protected image URLs', () {
    final board = EventStationBoard.fromJson({
      'captures': [
        {
          'sessionId': 's1',
          'status': 'PENDING',
          'previewUrls': ['/api/img/generated/a.jpg'],
        },
      ],
      'themeJobs': [
        {
          'id': 'j1',
          'sessionId': 's1',
          'status': 'PENDING',
          'previewUrls': ['/api/img/previews/t.jpg'],
        },
      ],
      'printJobs': [
        {
          'id': 'p1',
          'sessionId': 's1',
          'imageUrl': '/api/img/generated/p.jpg',
          'status': 'PENDING',
        },
      ],
    }).withStationImageAuth(kioskCode: 'K1', eventCode: 'GALA');
    expect(board.captures.single.previewUrls.single, contains('sessionId=s1'));
    expect(board.captures.single.previewUrls.single, contains('kioskCode=K1'));
    expect(board.themeJobs.single.previewUrls.single, contains('eventCode=GALA'));
    expect(board.printJobs.single.imageUrl, contains('sessionId=s1'));
    expect(
      stampEventStationImageUrl(
        url: 'https://cdn/a.jpg',
        sessionId: 's1',
        kioskCode: 'K1',
        eventCode: 'GALA',
      ),
      'https://cdn/a.jpg',
    );
  });
}
