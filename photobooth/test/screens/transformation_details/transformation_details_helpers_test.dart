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

    test('reads from ai_generation step metadata', () {
      final result = parseIdentityVerification(
        payload: {},
        run: {},
        steps: [
          {
            'stage': 'ai_generation',
            'metadata': {
              'identity_verification': {
                'avgFaceScore': 0.91,
                'perFaceScores': [0.9, 0.92],
              },
            },
          },
        ],
      );
      expect(result?['avgFaceScore'], 0.91);
      expect(result?['perFaceScores'], [0.9, 0.92]);
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
}
