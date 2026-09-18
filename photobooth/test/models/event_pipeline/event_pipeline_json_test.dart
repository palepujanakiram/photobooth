import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/event_pipeline/media_item.dart';
import 'package:photobooth/models/event_pipeline/pipeline_job.dart';
import 'package:photobooth/services/event_pipeline/event_pipeline_stats.dart';

void main() {
  test('MediaItem JSON round-trips camelCase', () {
    const item = MediaItem(
      id: 'mi-1',
      eventId: 'ev',
      source: MediaSource.ptp,
      sourceRef: 'ref',
      contentKey: 'ck',
      originalFilename: 'a.jpg',
      capturedAtMs: 9,
      originalBytes: 12,
      stage: MediaStage.queued,
      remoteSessionId: 's',
      remotePhotoId: 'p',
      steps: ['ai', 'print'],
      stepIndex: 1,
      selectedAtMs: 11,
      aiSkipped: true,
      lastError: 'e',
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    final copy = MediaItem.fromJson(item.toJson());
    expect(copy.id, 'mi-1');
    expect(copy.sourceRef, 'ref');
    expect(copy.steps, ['ai', 'print']);
    expect(copy.aiSkipped, isTrue);
    expect(copy.updatedAtMs, 2);
  });

  test('MediaItem.fromJson accepts snake_case', () {
    final item = MediaItem.fromJson(const {
      'id': 'mi-2',
      'source': 'sdcard',
      'source_ref': 'b',
      'content_key': 'k',
      'stage': 'INGESTED',
      'created_at_ms': 3,
      'updated_at_ms': 4,
    });
    expect(item.sourceRef, 'b');
    expect(item.contentKey, 'k');
  });

  test('PipelineJob JSON round-trips', () {
    const job = PipelineJob(
      id: 'pj-1',
      kind: 'print',
      mediaId: 'mi-1',
      eventId: 'ev',
      status: PipelineJobStatus.pending,
      payload: {'copies': 2},
      createdAtMs: 1,
      updatedAtMs: 2,
    );
    final copy = PipelineJob.fromJson(job.toJson());
    expect(copy.mediaId, 'mi-1');
    expect(copy.payload['copies'], 2);
  });

  test('PipelineJob JSON reads a payload_json string', () {
    final job = PipelineJob.fromJson(const {
      'id': 'pj-2',
      'kind': 'ai',
      'media_id': 'mi-2',
      'status': 'PENDING',
      'created_at_ms': 1,
      'updated_at_ms': 2,
      'payload_json': '{"theme":"x"}',
    });
    expect(job.payload['theme'], 'x');
  });

  test('EventPipelineStats JSON round-trips', () {
    const stats = EventPipelineStats(imported: 3, done: 4, queuePaused: true);
    final copy = EventPipelineStats.fromJson(stats.toJson());
    expect(copy.imported, 3);
    expect(copy.done, 4);
    expect(copy.queuePaused, isTrue);
    expect(
      EventPipelineStats.fromJson(const {
        'print_paused': true,
        'queue_paused': true,
        'imported': 1,
      }).printPaused,
      isTrue,
    );
    expect(copy.inFlight, 0);
  });

  test('MediaItem.fromJson drops a bad steps value', () {
    final item = MediaItem.fromJson(const {
      'id': 'mi-3',
      'source': 'ptp',
      'sourceRef': 'r',
      'contentKey': 'k',
      'stage': 'INGESTED',
      'createdAtMs': 1,
      'updatedAtMs': 1,
      'steps': 'not-a-list',
    });
    expect(item.steps, isEmpty);
  });
}
