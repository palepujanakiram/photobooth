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

  /// Receipt / ESC/POS thermal print success.
  static const receiptPrintSuccess = 'Receipt sent to printer';

  /// Receipt printer not configured in admin settings.
  static const receiptPrintNotConfigured =
      'Receipt printer is not configured. Ask staff to set it in Admin → Settings.';

  /// Generic receipt print failure for guests.
  static const receiptPrintFailedGeneric =
      'Failed to print receipt. Check the receipt printer and try again.';

  /// Empty ESC/POS payload from API.
  static const receiptPrintEmptyPayload = 'Receipt print payload is empty';

  /// Web kiosk cannot open raw TCP to LAN printers.
  static const receiptPrintUnsupportedOnWeb =
      'Receipt printing requires the Android/iOS kiosk app on the same Wi‑Fi as the printer.';

  /// Button label on QR share screen.
  static const printReceiptButton = 'Print receipt';

  /// Button busy label.
  static const printingReceiptButton = 'Printing receipt…';

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

  /// INR symbol for guest/staff UI amounts (PDF may still say Rs).
  static const currencyRupee = '₹';

  /// Staff payment mode dropdown hint.
  static const paymentModeLabel = 'Payment mode';

  /// Coupon field label on Pay & Collect.
  static const couponCodeLabel = 'Coupon code';

  /// Apply coupon button.
  static const applyCoupon = 'Apply';

  /// Remove applied coupon.
  static const removeCoupon = 'Remove';

  /// Marketing consent section blurb (DPDP).
  static const marketingConsentBlurb =
      "Optional — marketing under India's DPDP Act. You can opt out anytime.";

  static const marketingWhatsappLabel = 'WhatsApp offers & new themes';
  static const marketingSmsLabel = 'SMS offers & announcements';
  static const marketingEmailLabel = 'Email newsletters & offers';

  static const optionalEmailLabel = 'Email (optional)';


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

  /// Non-blocking status on Terms while cameras are enumerated on entry.
  static const termsDetectingCameras = 'Detecting cameras…';

  /// Terms Continue label while camera detection is still running.
  static const termsContinueWhenReady = 'Continue when ready';

  /// Full-screen overlay while the session API runs after Terms accept.
  static const termsCreatingSession = 'Creating session…';

  /// Terms banner when no camera is available after enumeration.
  static const termsNoCameraDetected =
      'No camera detected. Connect a USB camera and tap Retry.';

  /// Terms banner when camera permission was denied.
  static const termsCameraPermissionDenied =
      'Camera permission is required. Enable it in Settings, then tap Retry.';

  /// Terms banner when camera priming failed unexpectedly.
  static const termsCameraDetectionFailed =
      'Could not detect cameras. Tap Retry.';

  /// Retry action on Terms camera status banner.
  static const termsRetryCameraDetection = 'Retry';

  /// Spoken once at the start of the POSE capture countdown.
  static const captureCountdownIntro = 'Be ready for photo';

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
      'Your portrait will appear step by step. Times vary with AI load.';

  static const generationWaitTimeExpectation = 'Usually takes 1–2 minutes';

  static String generationWaitEtaRemaining(String duration) =>
      '~$duration remaining';

  static String generationWaitEtaAboutTotal(String duration) =>
      'About $duration total';

  static String generationWaitEtaTodayAvg(String duration) =>
      'Today at this booth: ~$duration avg';

  static String generationWaitEtaRecentAvg(String duration) =>
      'Recent portraits here: ~$duration';

  static const generationWaitEtaBusy =
      'A little busier than usual — thanks for your patience';

  static const generationWaitEtaLongWait =
      'Taking a little longer than usual — your portrait is still on the way';

  static const generationWaitEtaAlmostReady =
      'Almost ready — finishing touches';

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
      'Branding and securing your portrait';

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

  static const sessionPhotoSyncNoSession =
      'No active session. Please go back and accept terms again.';

  static const sessionPhotoSyncVerifyFailed =
      'Photo could not be saved on the server. Please capture again.';

  static const sessionPhotoSyncFailed = 'Failed to upload photo';

  static const printProgressTitleActive = 'Printing your photo';

  static const printProgressTitleComplete = 'Print complete';

  static const printProgressTitleFailed = 'Print failed';

  static const printProgressSubtitleActive =
      'Please wait while your photo is sent to the printer…';

  static const printProgressSubtitleComplete =
      'Grab your photo from the tray below.';

  static const printProgressSubtitleFailed =
      'Tap Print again or ask staff for help.';

  static const printProgressFooterPrinting = 'Printing…';

  static const phoneUploadButtonLabel = 'Phone QR';

  static const phoneUploadSheetTitle = 'Upload from your phone';

  static const phoneUploadSheetSubtitle =
      'Scan this QR code, choose a photo on your phone, then look back at the booth.';

  static const phoneUploadWaiting = 'Waiting for phone upload…';

  static const phoneUploadReceived = 'Photo received from phone';

  static const phoneUploadCancelled = 'Phone upload cancelled';

  static const phoneUploadFailed = 'Could not start phone upload';

  static const phoneUploadMintFailed =
      'Could not create upload QR. Check network and try again.';

  static const phoneUploadTimeout =
      'Timed out waiting for phone upload. Try again or use Gallery.';

  static const galleryButtonLabel = 'Gallery';
}
