import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/transformation_run_id.dart';

void main() {
  test('transformationRunIdFromSessionMap reads active run keys', () {
    expect(
      transformationRunIdFromSessionMap({
        'activeTransformationRunId': 'run-1',
      }),
      'run-1',
    );
    expect(
      transformationRunIdFromSessionMap({
        'session': {'active_transformation_run_id': 'run-2'},
      }),
      'run-2',
    );
    expect(transformationRunIdFromSessionMap(null), isNull);
    expect(transformationRunIdFromSessionMap({'id': 's'}), isNull);
  });

  test('latestTransformationRunIdFromRunsResponse picks last id', () {
    expect(
      latestTransformationRunIdFromRunsResponse({
        'runs': [
          {'id': 'a'},
          {'id': 'b'},
        ],
      }),
      'b',
    );
    expect(latestTransformationRunIdFromRunsResponse({'runs': []}), isNull);
    expect(latestTransformationRunIdFromRunsResponse(null), isNull);
  });
}
