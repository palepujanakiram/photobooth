/// Centralized user-visible and diagnostic strings.
///
/// Keeps copy consistent across screens and satisfies Sonar rule S1192
/// (duplicated string literals). Do not put secrets here — values are shipped
/// in the client binary.
abstract final class AppStrings {
  /// Shown after a successful silent print to the network printer.
  static const printJobSentSuccess = 'Print job sent successfully!';

  /// Generic print failure when the underlying error must not be shown to guests.
  static const printFailedGeneric =
      'Failed to print. Please check the printer and try again.';

  /// Browser / Dio message when a web request cannot reach the API (CORS, offline).
  static const failedToFetch = 'Failed to fetch';

  /// Fallback when [DioException.message] is empty on network failures.
  static const unknownNetworkError = 'Unknown network error';

  /// Thrown when a captured or downloaded image file has zero bytes.
  static const imageFileEmpty = 'Image file is empty';

  /// Debug log label for USB/external cameras in [CaptureViewModel].
  static const cameraLabelExternal = '[external]';

  /// Debug log label for built-in cameras in [CaptureViewModel].
  static const cameraLabelBuiltIn = '[built-in]';

  /// Stack-frame filter: skip internal frames from [AppLogger] when parsing callers.
  static const loggerFileName = 'logger.dart';

  /// Horizontal rule in API request/response debug logs (mobile + web formatters).
  static const apiLogSeparator = '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━';

  /// FCM / payment push log channel name (Android logcat filter).
  static const fcmLogChannel = 'fotozen.fcm';

  /// Staff API authentication header.
  static const staffTokenHeader = 'X-Staff-Token';

  /// Inline image URL prefix (data URLs, staff QR thumbnails).
  static const dataImagePrefix = 'data:image';

  /// Camera capture timeout reason (logging + recovery).
  static const takePictureTimeout = 'takePicture timeout';

  /// Camera picker screen title.
  static const selectCameraTitle = 'Select Camera';

  /// Camera picker refresh action (app bar tooltip).
  static const refreshCameras = 'Refresh cameras';

  /// USB/UVC camera entry in the camera picker.
  static const cameraPickerUsbCameraTitle = 'USB Camera (UVC)';

  /// Camera picker: shown when no UVC cameras are connected.
  static const cameraPickerUsbNoDevices = 'No USB camera detected.';

  /// Shown on Android tablet/TV when only built-in cameras are enumerated.
  static const cameraPickerBuiltInOnlyHint =
      'Only built-in cameras were detected. Connect a USB camera, then tap '
      'Refresh. If it still does not appear, this tablet may not expose USB '
      'cameras to the system camera API.';

  /// Shown when camera enumeration returns an empty list.
  static const cameraPickerNoCameras =
      'No cameras found. Connect a USB camera and tap Refresh.';

  /// Shown while re-enumerating cameras in the picker.
  static const cameraPickerRefreshing = 'Looking for cameras…';

  /// UVC idle sleep: tap to reopen the live DSLR feed after thermal relief closed it.
  static const uvcTapToWakePreview =
      'Tap when ready\nto start the camera preview';

  static const captureStartingPreview = 'Starting camera…';

  static const openingCameraOverlay = 'Opening camera…';

  static const uvcReconnectingMessage = 'Reconnecting USB camera…';

  static const uvcReconnectFailedMessage =
      'USB camera keeps disconnecting. Check the cable and USB port, then tap '
      'Retry USB camera.';

  /// POSE screen: shown briefly before returning to Terms after idle timeout.
  static const captureScreenIdleResetMessage =
      'Idle activity is detected so going back';

  /// Payment push / poll notification titles and bodies.
  static const paymentConfirmedTitle = 'Payment confirmed';
  static const paymentNotCompletedTitle = 'Payment not completed';
  static const paymentFailedRetryBody =
      'Payment failed. Try again or use another method.';

  /// Theme session update timeout message.
  static const requestTimeoutConnection =
      'Request took too long. Please check your connection and try again.';

  /// Customer privacy: delete capture + generated images (server + local).
  static const deleteMyPhotosLabel = 'Delete my photos';

  static const deleteMyPhotosDialogTitle = 'Delete my photos?';

  static const deleteMyPhotosDialogBody =
      'This will permanently delete your capture and generated images from '
      'this session. This cannot be undone.';

  static const deleteMyPhotosCancel = 'Cancel';

  static const deleteMyPhotosConfirm = 'Delete';

  /// Shown at the start of AI generation (progress + behold wait states).
  static const generationWaitExpectation =
      'This usually takes 30–60 seconds. Your portrait will appear step by step.';

  static const generationWaitTimeExpectation = 'Usually takes 30–60 seconds';

  static const generationWaitMasterpieceTitle = 'Creating your masterpiece';

  static const generationWaitMasterpieceSubtitle =
      'Our AI is crafting something extraordinary for you';

  static const generationWaitStepAnalyzing = 'Analyzing';

  static const generationWaitStepTransforming = 'Transforming';

  static const generationWaitStepFinalizing = 'Finalizing';

  static const generationWaitDidYouKnowTitle = 'Did you know?';

  static const generationWaitPrivacyFooter =
      'Your photos are secure and private';

  static const generationWaitThemeReelTitle =
      'More worlds to explore next time';

  static const generationWaitHeadlineStarting = 'Starting your transformation';

  static const generationWaitHeadlineCaptured = 'Captured';

  static const generationWaitDescCaptured = 'Frozen frame, framing applied';

  static const generationWaitHeadlineIsolate = 'Background removed';

  static const generationWaitDescIsolate = 'Subject isolated, ready to render';

  static const generationWaitHeadlineRendering = 'Rendering';

  static const generationWaitDescRendering = 'AI is applying your style';

  static const generationWaitHeadlineFinishing = 'Finishing touches';

  static const generationWaitDescFinishing =
      'Preparing your print-ready portrait';

  static const generationWaitThemeIntoPrefix = 'Turning you into';

  static const generationWaitBeforeLabel = 'You';

  static const generationWaitAfterLabel = 'Style';

  static const generationWaitElapsedLabel = 'Elapsed';

  static const generationWaitGoBack = 'Go back';

  static const generationWaitStartOver = 'Start over';

  static const generationWaitLiveRevealHeadline = 'Your portrait is taking shape';

  static const generationWaitLiveRevealDesc =
      'Magic is happening — hang tight for the reveal';

  static const generationWaitErrorTitle = 'Generation failed';

  static const generationNoAttemptsRemaining =
      'No generation attempts remaining for this session. Use “Or add one more style” on your results, or start over.';

  static const beholdReadyStepLabel = 'Step 3 of 3';

  static const beholdReadyTitle = 'Your masterpiece is ready!';

  static const beholdReadySubtitle =
      'We hope you love your AI-transformed portrait.';

  static const beholdReadyPrivacyFooter =
      'Your photos are secure and private. We never store your images.';

  static const beholdTransformationDetailsLink = 'View transformation details';

  static const transformationDetailsDisplayTimeLabel =
      'Time to show on screen';

  static const transformationDetailsServerDurationLabel = 'Server duration';

  static const transformationDetailsSessionIdLabel = 'Session ID';

  static const transformationDetailsRunIdLabel = 'Run ID';

  static const transformationDetailsCopyLogIdsLabel = 'Copy for logs';

  static const transformationDetailsCopiedLogIds =
      'Copied session and run IDs for logs';

  static const beholdContinueLabel = 'Continue';

  static const beholdSelectedLabel = 'Selected';

  static const generationProgressTitle = 'CREATE';

  static const generationProgressSubtitle =
      'Please wait while we craft your portrait';
}
