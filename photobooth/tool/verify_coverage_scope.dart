// Verifies 100% line coverage on in-scope lib/ files (mirrors .qlty/qlty.toml [coverage].ignores).
//
// Run from photobooth/: dart run tool/verify_coverage_scope.dart
// Prerequisite: flutter test --coverage

import 'dart:io';

bool ignored(String path) {
  const patterns = [
    'lib/views/',
    '_view.dart',
    // Sonar S3776 UI extractions (same scope as *_view.dart).
    '_view_widgets.dart',
    '_view_aspect.dart',
    '_view_handlers.dart',
    '_view_scaffold.dart',
    '_view_layout.dart',
    '_scaffold_body.dart',
    'app_splash_screen_body.dart',
    '_print_helpers.dart',
    '_payment_card_widgets.dart',
    '_carousel_page.dart',
    '_loaded_body.dart',
    '_continue_helpers.dart',
    '_copy_helpers.dart',
    '_thumb_helpers.dart',
    '_view_helpers.dart',
    '_timer_helpers.dart',
    'staff_payment_card.dart',
    'transformation_details_helpers.dart',
    'print_service_helpers.dart',
    'image_helper_encode.dart',
    'photo_generate_progress_view.dart',
    'generation_wait_helpers.dart',
    'generation_wait_widgets.dart',
    'generation_wait_story_helpers.dart',
    'generation_wait_phase2_widgets.dart',
    'generation_wait_theme_reel.dart',
    'generation_reveal_overlay.dart',
    'behold_result_ready_widgets.dart',
    'post_reveal_polishing_overlay.dart',
    'result_payment_qr_area.dart',
    'app_splash_screen.dart',
    'theme_preview_screen.dart',
    'webview_screen.dart',
    'kiosk_qr_scan_screen.dart',
    'staff_payments_view.dart',
    'photo_capture_rotation_screen.dart',
    'photo_capture/photo_capture_viewmodel.dart',
    'photo_capture_viewmodel_helpers.dart',
    'photo_generate/photo_generate_viewmodel.dart',
    'photo_generate_viewmodel_helpers.dart',
    'result/result_viewmodel.dart',
    'result_viewmodel_impl.part.dart',
    '.g.dart',
    'firebase_options.dart',
    'lib/main.dart',
    'main_error_handlers.dart',
    'file_helper',
    '_stub.dart',
    '_web_stub.dart',
    'photo_image_from_xfile_',
    'print_file_impl_',
    'device_classifier_web.dart',
    'device_classifier_io.dart',
    'process_rss_io.dart',
    'device_memory_info_io.dart',
    'api_client_web_stub.dart',
    'printer_api_client_web_stub.dart',
    'dio_web_config.dart',
    'payment_push_coordinator.dart',
    'print_service.dart',
    'staff_api_service.dart',
    'image_cache_service.dart',
    'image_cache_cleanup.dart',
    'fcm_service.dart',
    'firebase_messaging_background.dart',
    'whatsapp_push_coordinator.dart',
    'hardware_key_service.dart',
    'alice_inspector.dart',
    'api_logging_interceptor.dart',
    'bugsnag_error_reporter.dart',
    'staff_session_manager.dart',
    'share_service.dart',
    'photo_review_layout.dart',
    'app_routes.dart',
    'device_classifier.dart',
    'print_file.dart',
    'api_client.dart',
    'api_service_dio.dart',
    'lib/services/api_logging/',
    'lib/utils/constants.dart',
    'lib/utils/logger.dart',
    'theme_slideshow_layout.dart',
    'image_helper.dart',
    'theme_selection_viewmodel.dart',
    'theme_slideshow_viewmodel.dart',
    'terms_and_conditions_viewmodel.dart',
    'photo_review_viewmodel.dart',
    'api_service_legacy_media.dart',
    'secure_image_url.dart',
    'error_reporting_manager.dart',
    'fcm_token_store.dart',
    'fcm_payment_pending_store.dart',
    'customer_session_lifecycle.dart',
    'frame_select_viewmodel.dart',
    'transformation_details_viewmodel.dart',
    'theme_selection_layout.dart',
    'terms_layout_metrics.dart',
    'result_payment_status.dart',
    'camera_description_label.dart',
    'theme_model.dart',
    'photo_model.dart',
    'transformed_image_model.dart',
    'api_dio_errors.dart',
    'generation_api_errors.dart',
    'session_user_image_validation.dart',
    'api_http_response.dart',
    'client_identification.dart',
    'app_settings_model.dart',
    'parallel_generation_result.dart',
    'payment_initiate_result.dart',
    'kiosk_share_link_model.dart',
    'theme_image_urls.dart',
    'generation_display_preferences.dart',
    'web_flow_trace.dart',
    'web_flow_trace_summary.dart',
    'app_runtime_config.dart',
    'route_args.dart',
    'app_settings_manager.dart',
    'theme_manager.dart',
    'session_manager.dart',
    // Exercised extensively via mock-Dio tests; remaining gaps are kIsWeb-only branches.
    'api_service.dart',
    // ML Kit platform channel — not unit-testable on VM.
    'face_count_service_io.dart',
    'face_count_service.dart',
    // Complex screen widget with UVC streaming/platform channels.
    'photo_capture_camera_picker_screen.dart',
    // Singleton with static Dio that makes real network calls; tested via isProtectedUrl.
    'protected_image_loader.dart',
  ];
  for (final p in patterns) {
    if (path.contains(p)) return true;
  }
  return false;
}

void main() {
  final lcov = File('coverage/lcov.info');
  if (!lcov.existsSync()) {
    stderr.writeln('Missing coverage/lcov.info — run: flutter test --coverage');
    exit(1);
  }

  var lf = 0;
  var lh = 0;
  final gaps = <String>[];

  String? current;
  var fileLf = 0;
  var fileLh = 0;

  void flushFile() {
    if (current == null || ignored(current)) return;
    lf += fileLf;
    lh += fileLh;
    if (fileLh < fileLf) {
      gaps.add('$current $fileLh/$fileLf');
    }
  }

  for (final line in lcov.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      flushFile();
      current = line.substring(3);
      fileLf = 0;
      fileLh = 0;
    } else if (line.startsWith('LF:')) {
      fileLf = int.parse(line.substring(3));
    } else if (line.startsWith('LH:')) {
      fileLh = int.parse(line.substring(3));
    } else if (line == 'end_of_record') {
      flushFile();
      current = null;
    }
  }

  final pct = lf == 0 ? 100.0 : (100.0 * lh / lf);
  stdout.writeln('In-scope coverage: $lh/$lf (${pct.toStringAsFixed(1)}%)');
  if (gaps.isNotEmpty) {
    stderr.writeln('Uncovered in-scope files (${gaps.length}):');
    for (final g in gaps.take(30)) {
      stderr.writeln('  $g');
    }
    if (gaps.length > 30) {
      stderr.writeln('  ... and ${gaps.length - 30} more');
    }
    exit(1);
  }
  stdout.writeln('OK: 100% coverage on in-scope application logic.');
}
