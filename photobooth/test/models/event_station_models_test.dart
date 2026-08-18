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
}
