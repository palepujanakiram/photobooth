import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/transformation_details/transformation_details_helpers.dart';

void main() {
  group('parseIdentityVerification', () {
    test('reads top-level identity_verification', () {
      final result = parseIdentityVerification(
        payload: {
          'identity_verification': {
            'passed': true,
            'minFaceScore': 0.86,
          },
        },
        run: {},
        steps: [],
      );
      expect(result?['passed'], isTrue);
      expect(result?['minFaceScore'], 0.86);
    });

    test('reads from generation log on payload', () {
      final result = parseIdentityVerification(
        payload: {
          'generationLog': {
            'identityVerification': {'passed': false, 'retryCount': 2},
          },
        },
        run: {},
        steps: [],
      );
      expect(result?['passed'], isFalse);
      expect(result?['retryCount'], 2);
    });

    test('reads flattened embedding fields on run object', () {
      final result = parseIdentityVerification(
        payload: {},
        run: {
          'passed': true,
          'embeddingMinSimilarity': 88,
          'embeddingAvgSimilarity': 92,
          'embeddingThresholdUsed': 80,
          'personCountMatch': true,
        },
        steps: [],
      );
      expect(result?['passed'], isTrue);
      expect(result?['embeddingMinSimilarity'], 88);
    });

    test('reads from any step metadata not only ai_generation', () {
      final result = parseIdentityVerification(
        payload: {},
        run: {},
        steps: [
          {
            'stage': 'c2pa_sign',
            'metadata': {
              'identity_verification': {
                'passed': true,
                'embeddingMinSimilarity': 100,
              },
            },
          },
        ],
      );
      expect(result?['embeddingMinSimilarity'], 100);
    });
  });

  group('identityVerificationSummaryLines', () {
    test('formats embedding* backend fields', () {
      final lines = identityVerificationSummaryLines({
        'passed': true,
        'personCountMatch': true,
        'embeddingThresholdUsed': 75,
        'embeddingMinSimilarity': 100,
        'embeddingAvgSimilarity': 100,
        'embeddingFailedFaceIndices': [],
      });
      expect(lines, contains('Result: Passed'));
      expect(lines, contains('Face count match: Yes'));
      expect(lines, contains('Threshold: 75%'));
      expect(lines, contains('Min face score: 100%'));
      expect(lines, contains('Avg face score: 100%'));
    });

    test('formats scores and failed indices', () {
      final lines = identityVerificationSummaryLines({
        'passed': true,
        'thresholdUsed': 0.8,
        'minFaceScore': 0.84,
        'avgFaceScore': 0.88,
        'perFaceScores': [0.84, 0.92],
        'failedFaceIndices': [],
        'retryCount': 1,
        'themeName': 'Royal Mughal',
        'promptSnippet': 'IDENTITY LOCK',
      });
      expect(lines, contains('Result: Passed'));
      expect(lines, contains('Threshold: 80%'));
      expect(lines, contains('Min face score: 84%'));
      expect(lines, contains('Per-face scores: 84%, 92%'));
      expect(lines, contains('Theme: Royal Mughal'));
      expect(lines.any((l) => l.startsWith('Prompt snippet:')), isTrue);
    });
  });

  group('log support fields', () {
    test('sessionIdFromRun and runIdFromRun read ids', () {
      expect(
        sessionIdFromRun({'sessionId': ' sess-1 '}),
        'sess-1',
      );
      expect(runIdFromRun({'id': 'run-9'}), 'run-9');
      expect(runIdFromRun({'runId': 'run-alt'}), 'run-alt');
    });

    test('formatClientDisplayElapsed and formatServerDurationMs', () {
      expect(formatClientDisplayElapsed(42), '42s');
      expect(formatClientDisplayElapsed(null), '—');
      expect(formatServerDurationMs(1234.6), '1235 ms');
      expect(formatServerDurationMs('x'), '—');
    });

    test('buildTransformationLogClipboardText bundles ids and timing', () {
      expect(
        buildTransformationLogClipboardText(
          sessionId: 'sess-1',
          runId: 'run-9',
          clientDisplayElapsedSeconds: 38,
          serverDurationMs: 41000,
        ),
        'sessionId=sess-1 runId=run-9 displaySeconds=38 serverDurationMs=41000',
      );
    });
  });
}
