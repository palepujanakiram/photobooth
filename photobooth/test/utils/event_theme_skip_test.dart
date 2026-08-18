import 'package:flutter_test/flutter_test.dart';
import 'package:photobooth/utils/event_theme_skip.dart';

void main() {
  test('no event photoMode never skips', () {
    expect(
      shouldSkipEventThemePicker(photoMode: null, themeCount: 0),
      isFalse,
    );
    expect(
      shouldSkipEventThemePicker(photoMode: '', themeCount: 1),
      isFalse,
    );
  });

  test('event with 2+ themes shows picker', () {
    expect(
      shouldSkipEventThemePicker(photoMode: 'BOTH', themeCount: 2),
      isFalse,
    );
  });

  test('event with 0 or 1 theme skips picker', () {
    expect(
      shouldSkipEventThemePicker(photoMode: 'AI_TRANSFORM', themeCount: 1),
      isTrue,
    );
    expect(
      shouldSkipEventThemePicker(photoMode: 'BOTH', themeCount: 0),
      isTrue,
    );
  });

  test('FRAME_ONLY with no themes skips the theme step', () {
    expect(
      shouldSkipEventThemeStepForFrameOnly(
        photoMode: 'FRAME_ONLY',
        themeCount: 0,
      ),
      isTrue,
    );
    expect(
      shouldSkipEventThemeStepForFrameOnly(
        photoMode: 'BOTH',
        themeCount: 0,
      ),
      isFalse,
    );
  });

  test('FRAME_ONLY with one theme auto-selects', () {
    expect(
      resolveEventThemeSkipAction(photoMode: 'FRAME_ONLY', themeCount: 1),
      EventThemeSkipAction.autoSelect,
    );
    expect(
      shouldSkipEventThemeStepForFrameOnly(
        photoMode: 'FRAME_ONLY',
        themeCount: 1,
      ),
      isFalse,
    );
  });

  test('resolveEventThemeSkipAction maps counts', () {
    expect(
      resolveEventThemeSkipAction(photoMode: null, themeCount: 0),
      EventThemeSkipAction.showPicker,
    );
    expect(
      resolveEventThemeSkipAction(photoMode: 'BOTH', themeCount: 3),
      EventThemeSkipAction.showPicker,
    );
    expect(
      resolveEventThemeSkipAction(photoMode: 'BOTH', themeCount: 1),
      EventThemeSkipAction.autoSelect,
    );
    expect(
      resolveEventThemeSkipAction(photoMode: 'FRAME_ONLY', themeCount: 0),
      EventThemeSkipAction.skipToFrames,
    );
    expect(
      resolveEventThemeSkipAction(photoMode: 'BOTH', themeCount: 0),
      EventThemeSkipAction.showPicker,
    );
    expect(
      resolveEventThemeSkipAction(photoMode: 'AI_TRANSFORM', themeCount: 1),
      EventThemeSkipAction.autoSelect,
    );
  });

  test('shouldAutoContinueEventTheme requires photo and selected theme', () {
    expect(
      shouldAutoContinueEventTheme(
        action: EventThemeSkipAction.autoSelect,
        hasCapturePhoto: true,
        hasSelectedTheme: true,
      ),
      isTrue,
    );
    expect(
      shouldAutoContinueEventTheme(
        action: EventThemeSkipAction.autoSelect,
        hasCapturePhoto: false,
        hasSelectedTheme: true,
      ),
      isFalse,
    );
    expect(
      shouldAutoContinueEventTheme(
        action: EventThemeSkipAction.showPicker,
        hasCapturePhoto: true,
        hasSelectedTheme: true,
      ),
      isFalse,
    );
    expect(
      shouldAutoContinueEventTheme(
        action: EventThemeSkipAction.skipToFrames,
        hasCapturePhoto: true,
        hasSelectedTheme: false,
      ),
      isFalse,
    );
  });
}
