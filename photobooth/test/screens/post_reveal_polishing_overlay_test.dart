import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/screens/photo_generate/photo_generate_viewmodel.dart';
import 'package:photobooth/screens/photo_generate/post_reveal_polishing_overlay.dart';

GenerationRunStepPreview _step(String stage, String status) =>
    GenerationRunStepPreview(stage: stage, status: status);

void main() {
  test('postRevealPolishStepCopy maps polish stages', () {
    expect(postRevealPolishStepCopy('scene_lighting'), 'Matching scene lighting');
    expect(postRevealPolishStepCopy('storage'), 'Preparing print file');
    expect(postRevealPolishStepCopy('unknown_x'), 'unknown_x');
  });

  test('indexPolishStepsByStage normalizes preprocess alias', () {
    final byStage = indexPolishStepsByStage([
      _step('preprocess', 'running'),
    ]);
    expect(byStage['preprocessing']?.isActive, isTrue);
  });

  test('resolveActivePolishStageKey prefers first active polish step', () {
    final byStage = indexPolishStepsByStage([
      _step('scene_lighting', 'complete'),
      _step('face_relight', 'running'),
    ]);
    expect(resolveActivePolishStageKey(byStage), 'face_relight');
  });

  test('resolveActivePolishStageKey uses storage when finished', () {
    final byStage = indexPolishStepsByStage([
      _step('storage', 'complete'),
    ]);
    expect(resolveActivePolishStageKey(byStage), 'storage');
  });

  test('resolveActivePolishStageKey picks first unfinished step', () {
    final byStage = indexPolishStepsByStage([
      _step('scene_lighting', 'queued'),
    ]);
    expect(resolveActivePolishStageKey(byStage), 'scene_lighting');
  });

  test('polishChipColor and polishChipIcon reflect state', () {
    expect(
      polishChipColor(active: true, finished: false),
      CupertinoColors.activeBlue,
    );
    expect(
      polishChipIcon(active: false, finished: true),
      Icons.check_circle,
    );
    expect(
      polishChipIcon(active: true, finished: false),
      Icons.autorenew,
    );
    expect(
      polishChipIcon(active: false, finished: false),
      Icons.more_horiz,
    );
  });

  testWidgets('empty steps renders nothing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PostRevealPolishingOverlay(steps: []),
        ),
      ),
    );
    expect(find.text('Finishing touches'), findsNothing);
  });

  testWidgets('renders overlay with active and finished chips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostRevealPolishingOverlay(
            steps: [
              _step('scene_lighting', 'complete'),
              _step('face_relight', 'running'),
              _step('upscaling', 'queued'),
              _step('storage', 'queued'),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Finishing touches'), findsOneWidget);
    expect(find.textContaining('Relighting your face'), findsWidgets);
    expect(find.byIcon(Icons.check_circle), findsWidgets);
    expect(find.byIcon(Icons.autorenew), findsWidgets);
  });
}
