import 'package:cross_file/cross_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/models/parallel_generation_result.dart';
import 'package:photobooth/screens/photo_capture/photo_model.dart';
import 'package:photobooth/screens/photo_review/photo_review_viewmodel.dart';
import 'package:photobooth/screens/theme_selection/theme_model.dart';
import 'package:photobooth/services/session_manager.dart';
import 'package:photobooth/utils/exceptions.dart';

import 'fakes/fake_api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final photo = PhotoModel(
    id: 'p1',
    imageFile: XFile('/tmp/x.jpg'),
    capturedAt: DateTime(2026, 1, 1),
  );
  final theme = ThemeModel(
    id: 't1',
    categoryId: 'c1',
    name: 'Test',
    description: 'd',
    promptText: 'prompt',
    sampleImageUrl: '/sample.jpg',
    backgroundColor: '#000000',
  );

  test('transformPhoto returns null when session missing', () async {
    SessionManager().clearSession();
    final vm = ReviewViewModel(
      photo: photo,
      theme: theme,
      apiService: FakeApiService(),
    );
    final result = await vm.transformPhoto();
    expect(result, isNull);
    expect(vm.errorMessage, contains('session'));
  });

  test('transformPhoto surfaces ApiException message', () async {
    SessionManager().setSessionFromResponse({
      'id': 'sess-1',
      'termsAccepted': true,
      'termsAcceptedAt': DateTime.utc(2026, 1, 1).toIso8601String(),
      'attemptsUsed': 0,
      'generatedImages': [],
      'expiresAt':
          DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
    });
    final vm = ReviewViewModel(
      photo: photo,
      theme: theme,
      apiService: _FailingGenerateApiService(),
      sessionManager: SessionManager(),
    );
    final result = await vm.transformPhoto();
    expect(result, isNull);
    expect(vm.errorMessage, contains('fail gen'));
  });
}

class _FailingGenerateApiService extends FakeApiService {
  @override
  Future<ParallelGenerationResult> generateImages({
    required String sessionId,
    required int count,
    required int attempt,
    required String originalPhotoId,
    required String themeId,
    void Function(String message)? onProgress,
    void Function(String eventType, Map<String, dynamic> json)? onSseEvent,
  }) async {
    throw ApiException('fail gen');
  }
}
