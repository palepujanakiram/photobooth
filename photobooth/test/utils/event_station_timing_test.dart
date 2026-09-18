import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/event_station_timing.dart';

void main() {
  test('parseEventStationDate accepts ISO, epoch, and DateTime', () {
    final iso = parseEventStationDate('2026-09-07T10:00:00.000Z')!;
    expect(iso.toUtc().hour, 10);
    expect(parseEventStationDate(0), isNull);
    expect(
      parseEventStationDate(1000),
      DateTime.fromMillisecondsSinceEpoch(1000, isUtc: true),
    );
    final now = DateTime.utc(2026, 1, 2);
    expect(parseEventStationDate(now), now);
    expect(parseEventStationDate(''), isNull);
    expect(parseEventStationDate(null), isNull);
  });

  test('formatEventStationDuration compact labels', () {
    expect(formatEventStationDuration(const Duration(seconds: 9)), '9s');
    expect(formatEventStationDuration(const Duration(minutes: 8)), '8m');
    expect(formatEventStationDuration(const Duration(hours: 2)), '2h');
    expect(
      formatEventStationDuration(const Duration(hours: 1, minutes: 3)),
      '1h 3m',
    );
    expect(formatEventStationDuration(-const Duration(seconds: 4)), '0s');
    expect(formatEventStationAge(null), '—');
    final clock = DateTime.utc(2026, 1, 1, 12);
    expect(
      formatEventStationAge(
        clock.subtract(const Duration(seconds: 12)),
        now: clock,
      ),
      '12s',
    );
  });

  test('queue summary covers wait vs processing', () {
    final now = DateTime.utc(2026, 9, 7, 12);
    final queued = EventStationJobTimes(
      createdAt: now.subtract(const Duration(minutes: 8)),
    );
    expect(
      eventStationQueueSummary(queued, now: now),
      'Queued 8m',
    );
    final claimed = EventStationJobTimes(
      createdAt: now.subtract(const Duration(minutes: 8)),
      claimedAt: now.subtract(const Duration(seconds: 45)),
    );
    expect(
      eventStationQueueSummary(claimed, now: now),
      'Queued 8m · 45s processing',
    );
    final done = EventStationJobTimes(
      createdAt: now.subtract(const Duration(minutes: 10)),
      claimedAt: now.subtract(const Duration(minutes: 6)),
      completedAt: now.subtract(const Duration(minutes: 4)),
      rawStatus: 'DONE',
    );
    expect(
      eventStationQueueSummary(done, now: now),
      'Queued 10m · 2m processing',
    );
    expect(
      eventStationQueueSummary(
        EventStationJobTimes(
          createdAt: DateTime.now().subtract(const Duration(seconds: 2)),
        ),
      ),
      startsWith('Queued '),
    );
  });

  test('display status prefers FAILED and SKIPPED raw values', () {
    expect(
      eventStationDisplayStatus(
        'PENDING',
        const EventStationJobTimes(rawStatus: 'FAILED'),
      ),
      'FAILED',
    );
    expect(
      eventStationDisplayStatus(
        'DONE',
        const EventStationJobTimes(rawStatus: 'SKIPPED'),
      ),
      'SKIPPED',
    );
    expect(
      eventStationDisplayStatus(
        'CLAIMED',
        const EventStationJobTimes(rawStatus: 'PRINTING'),
      ),
      'PRINTING',
    );
    expect(
      eventStationDisplayStatus('pending', const EventStationJobTimes()),
      'PENDING',
    );
    expect(
      eventStationDisplayStatus('', const EventStationJobTimes()),
      'PENDING',
    );
  });

  test('EventStationJobTimes.fromJson maps aliases and trims errors', () {
    final times = EventStationJobTimes.fromJson({
      'created_at': '2026-09-07T10:00:00.000Z',
      'claimed_at': '2026-09-07T10:01:00.000Z',
      'completed_at': '2026-09-07T10:02:00.000Z',
      'raw_status': 'failed',
      'error_message': '  boom  ',
    });
    expect(times.isFailed, isTrue);
    expect(times.errorMessage, 'boom');
    expect(times.createdAt, isNotNull);
    expect(
      EventStationJobTimes.fromJson({'errorMessage': '  '}).errorMessage,
      isNull,
    );
  });
}
