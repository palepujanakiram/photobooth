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

  /// POSE and Select Camera when no built-in or external camera is attached.
  static const noCameraConnected = 'No Camera Connected';

  /// Web-only empty enumeration (browser permission / Gallery fallback).
  static const noCameraDetectedWeb =
      'No camera detected. Allow camera access in the browser, or use Gallery if enabled.';

  /// Shown while re-enumerating cameras in the picker.
  static const cameraPickerRefreshing = 'Looking for cameras…';

  /// Non-blocking status on Terms while cameras are enumerated on entry.
  static const termsDetectingCameras = 'Getting the camera ready…';

  /// Terms Continue label while camera detection is still running.
  static const termsContinueWhenReady = 'Continue when ready';

  /// Full-screen overlay while the session API runs after Terms accept.
  static const termsCreatingSession = 'Creating session…';

  /// Overlay on Terms Start while `/api/settings` and kiosk flags refresh.
  static const termsRefreshingSettings = 'Updating booth settings…';

  /// Log when splash / Start settings fetch exceeds [kKioskSettingsRefreshTimeout].
  static const kioskSettingsRefreshTimedOut =
      'Kiosk settings refresh timed out; using cache';

  /// Log when splash / Start settings fetch throws; guest continues on cache.
  static const kioskSettingsRefreshFailed =
      'Kiosk settings refresh failed; using cache';

  /// Terms banner when camera is missing, permission was denied, or detection failed.
  static const termsCameraUnavailable =
      'Camera is not available. Tap Retry.';

  /// Same as [termsCameraUnavailable] when Gallery / Phone QR upload is enabled.
  static const termsCameraUnavailableUploadOk =
      'Camera is not available. You can continue and upload a photo instead, '
      'or tap Retry.';

  /// Retry action on Terms camera status banner.
  static const termsRetryCameraDetection = 'Retry';

  /// Spoken once at the start of the POSE capture countdown.
  static const captureCountdownIntro = 'Be ready for photo';

  /// UVC idle sleep: tap to reopen the live DSLR feed after thermal relief closed it.
  static const uvcTapToWakePreview =
      'Tap when ready\nto start the camera preview';

  static const captureStartingPreview = 'Starting camera…';

  /// HDMI/UVC still in flight — hides Canon status LCD on the capture card.
  static const captureCapturingPhoto = 'Capturing…';

  /// Sidecar prepare (LV/movie exit clicks) before the real shutter.
  static const captureSettingUpCamera = 'Setting up camera…';

  /// Guest prompt while Pi tears down live view during countdown (HDMI may flicker).
  static const captureHoldStillFocusing = 'Hold still — camera focusing…';

  /// Real shutter / download — guest-facing prompt.
  static const captureSayCheese = 'Say cheese!';

  /// Legacy generic still-in-progress copy.
  static const captureHoldStillForPhoto = 'Hold still…';

  /// Pi DSLR miss — keep preview; guest taps Capture (not USB reopen).
  static const captureDslrMissRetry =
      'Camera was busy. Tap Capture to try again.';

  static const captureDslrMissRetryButton = 'Retry photo';

  static const captureDslrMissRetryUsbFallback =
      'Camera capture failed. Check the DSLR USB cable to the Pi, then tap Retry.';

  /// Pose UI while waiting for the first Pi DSLR live-view frame.
  static const sidecarLivePreviewConnecting = 'Connecting to DSLR…';

  /// Pose UI when EDSDK sidecar live preview cannot load.
  static const sidecarLivePreviewUnavailable =
      'DSLR live preview unavailable.';

  /// Pose UI when a captured still cannot be decoded for review.
  static const captureStillDisplayFailed =
      'Photo saved, but it could not be shown. Retake the shot.';

  /// Shown on POSE when direct Canon USB permission is still pending.
  static const captureWaitingCanonUsbPermission =
      'Allow USB access for the Canon camera when prompted, then tap Retry camera.';

  /// Shown on POSE when no camera is available but Gallery / Phone QR is enabled.
  static const captureNoCameraUploadHint =
      'No camera detected. Upload a photo from Gallery or Phone QR, or retry '
      'after connecting a camera.';

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

  static const qrShareStartAgain = 'Start again';

  static String qrShareResettingIn(int seconds) =>
      'Starting fresh in ${seconds}s';

  static const generationWaitLiveRevealHeadline = 'Your portrait is taking shape';

  static const generationWaitLiveRevealDesc =
      'Magic is happening — hang tight for the reveal';

  static const generationWaitErrorTitle = 'Generation failed';

  static const generationNoAttemptsRemaining =
      'No AI generation attempts remaining for this session. '
      'Use “Explore more AI photos” / “Add another style” on your results, or start over.';

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

  static const phoneUploadFailed = 'Could not start phone upload';

  static const phoneUploadMintFailed =
      'Could not create upload QR. Check network and try again.';

  static const phoneUploadTimeout =
      'Timed out waiting for phone upload. Try again or use Gallery.';

  static const galleryButtonLabel = 'Gallery';

  static const cancel = 'Cancel';

  static const experienceChoiceTitle = 'How do you want to play?';
  static const experienceChoiceSubtitle =
      'Pick one experience for this session.';
  static const experienceAiTitle = 'FotoZen';
  static const experienceAiSubtitle = 'AI Photo Experiences';
  static const experienceFotoFlashTitle = 'Classic';
  static const experienceFotoFlashSubtitle =
      'As-is photos with glitter — choose 1-shot or 4-shot below';
  static const experienceFotoFlashUnavailable =
      'Classic isn’t available on this booth yet.';
  static const experienceFotoFlashStartFailed =
      'Couldn’t start Classic. Please try again.';
  static const experienceClassicShotModeLabel = 'Start Classic';
  static const experienceClassicFourShot = '4-shot strip';
  static const experienceClassicOneShot = '1-shot';
  static const experienceClassicStartOneShot = 'Start 1-shot';
  static const experienceClassicStartFourShot = 'Start 4-shot';
  static const experienceClassicOrientationLabel = 'Print orientation';
  static const experienceClassicLandscape = 'Landscape 6×4';
  static const experienceClassicPortrait = 'Portrait 4×6';
  static const experienceBackToTerms = 'Back to terms';

  /// Bundled preview art for the experience-choice cards.
  /// FotoZen uses a 2×2 collage of AI theme samples (people + themes).
  static const List<String> experienceAiPreviewAssets = [
    'lib/images/experience/fotozen_ai_preview.jpg',
    'lib/images/experience/fotozen_ai_preview_b.jpg',
    'lib/images/experience/fotozen_ai_preview_c.jpg',
    'lib/images/experience/fotozen_ai_preview_d.jpg',
  ];
  static const experienceClassicPreviewAsset =
      'lib/images/experience/classic_4shot_preview.png';
  static const experienceAiPreviewBadge = 'AI themes';
  static const experienceClassicPreviewBadge = '4-shot strip';
  static const experienceClassicOneShotPreviewBadge = '1-shot';
  static const flashbackBrand = 'FotoFlashback';
  static const flashbackCaptureTitle = 'FotoFlashback';
  /// POSE bar title, shared by the Flutter capture scaffold and the direct-PTP
  /// native screen so switching between them is invisible to a guest.
  static const posePageTitle = 'POSE';

  /// Default POSE subtitle. Shared by the Flutter capture scaffold and the
  /// direct-PTP native screen so the two look identical to a guest.
  static const poseSubtitleDefault =
      'Step in front of the camera and strike your best look';

  /// Shown while the native DSLR capture screen is coming up.
  static const directPtpStartingCamera = 'Starting the camera…';

  /// Shown after the shot lands, while it is prepared and uploaded.
  static const directPtpProcessing = 'Processing your photo…';

  /// The photo is safely on disk but the booth could not move on.
  static const directPtpContinueFailed =
      'Your photo was taken, but the booth could not continue. '
      'Tap Continue to try again.';

  /// Retry action on the direct-PTP capture error state.
  static const directPtpRetry = 'Try again';

  /// Retries the upload / hand-off without making the guest pose again.
  static const directPtpContinue = 'Continue';

  /// Discards the captured still and reopens the camera.
  static const directPtpRetake = 'Retake';

  /// Body label recorded on stills that came from the tethered DSLR.
  static const directPtpCameraLabel = 'EOS';
  static const flashbackCaptureSubtitle =
      '4 shots · 10s to pose · 8s between shots to rearrange';
  static const flashbackCaptureSubtitleSingle =
      'One shot · 10s pose countdown';
  static String flashbackShotProgress(int current, int total) =>
      'Shot $current of $total';
  static String flashbackPoseProgress(int current, int total) =>
      'Pose now — Shot $current of $total';
  static const flashbackPoseProgressSingle = 'Pose now — 10 second countdown';
  static const flashbackSingle6x4Title = 'Classic print';
  static String flashbackSinglePrintTitle(bool portrait) =>
      portrait ? 'Classic 4×6' : 'Classic 6×4';
  static const flashbackComposingSingle = 'Building your print…';
  static const flashbackNeedOneShot = 'Take a photo to continue.';
  static const flashbackTakeShot = 'Take shot';
  static const flashbackNextShot = 'Next shot';
  static const flashbackRetakeLast = 'Retake last';
  static const flashbackContinueLooks = 'Pick a look';

  /// Theme selection primary CTA.
  static const themeSelectionContinue = 'Continue';

  /// Theme selection CTA while session/theme sync runs before the next route.
  static const themeSelectionContinuing = 'Continuing…';

  /// Shown during the inter-shot hold while the guest reviews / rearranges.
  static const flashbackGettingReadyNextShot =
      'Rearrange for the next pose…';

  /// Mid-strip while LV / HDMI warmup settles before the next countdown.
  static String flashbackGetReadyForShot(int current, int total) =>
      'Get ready — Shot $current of $total';

  static String flashbackRearrangeForShot(int current, int total) =>
      'Rearrange for shot $current of $total';

  /// HDMI mask armed but shutter never began — soft-fail snackbar.
  static const captureMaskStallRetry =
      'Camera took too long. Tap Capture to try again.';

  /// Inter-shot hold on the final Classic still before looks.
  static const flashbackReviewLastShot = 'Looking good! Continuing soon…';

  static String flashbackReviewHoldStatus({
    required bool isLastShot,
    required int secondsLeft,
    int? nextShot,
    int? total,
  }) {
    final String base;
    if (isLastShot) {
      base = flashbackReviewLastShot;
    } else if (nextShot != null && total != null && total > 0) {
      base = flashbackRearrangeForShot(nextShot, total);
    } else {
      base = flashbackGettingReadyNextShot;
    }
    if (secondsLeft <= 0) return base;
    if (isLastShot) {
      return 'Looking good! Continuing in ${secondsLeft}s…';
    }
    return '$base — ${secondsLeft}s';
  }

  static const flashbackFilterTitle = 'Pick your look';
  static const flashbackFilterSubtitle =
      'Pick a look & frame. Add stickers, or Scribble to write on your strip';
  static const flashbackLookLabel = 'Look';
  static const flashbackFrameLabel = 'Frame';
  static const flashbackStickerLabel = 'Stickers';
  static const flashbackScribbleLabel = 'Scribble';
  static const flashbackScribbleOn = 'Drawing on';
  static const flashbackScribbleOff = 'Draw';
  static const flashbackScribbleUndo = 'Undo';
  static const flashbackScribbleClear = 'Clear';
  static const flashbackComposeCta = 'Continue';
  static const flashbackComposePayCta = 'Continue to pay';
  static const flashbackComposing = 'Building your strip…';
  static const flashbackPreparingPreview = 'Polishing photos…';
  static const flashbackFiltersLoadTimeout =
      'Looks took too long to load. You can still continue with the default look.';
  static const flashbackMissingArgs =
      'Photo session data was lost. Go back and retake, or restart the booth.';
  static const flashbackGradingPreview = 'Refreshing preview…';
  static const flashbackWarmingPrintPreview = 'Preparing print match…';
  static const flashbackFinishEncodeFailed =
      'Couldn’t prepare your photo. Tap Continue to looks to try again.';
  static const flashbackRetryScrub = 'Refresh polish';
  static const flashbackRetryScrubHint =
      'Some photos still show camera overlays. Tap Refresh polish to re-scrub.';
  static const flashbackComposeFailed = 'Couldn’t build strip. Please try again.';
  static const flashbackNeedFourShots = 'Take all 4 shots to continue.';
  static const surpriseMeUpsellTitle = 'Surprise AI look';
  static const surpriseMeUpsellSubtitle =
      'We made a bonus AI photo from your first shot.';
  static String surpriseMeUpsellPrice(int amount) =>
      'Add a print for ₹$amount?';
  static const surpriseMeUpsellYes = 'Yes, add a copy';
  static const surpriseMeUpsellExploreMore = 'Explore more AI photos';
  static const surpriseMeUpsellNo = 'No thanks';

  static const printSelectionTitle = 'Your prints';
  static const printSelectionSubtitle =
      'Choose which photos to print. Your strip stays available.';
  static const printSelectionStripLabel = 'Photo strip';
  static const printSelectionClassicLabel = 'Classic print';
  static const printSelectionAiLabel = 'AI photo';
  static const printSelectionEditLook = 'Edit look';
  static String printSelectionTotal(int amount) => 'Total ₹$amount';
  static String printSelectionContinue(int count) =>
      count <= 0 ? 'Select a photo' : 'Continue ($count)';

  static const staffDashboardTitle = 'Staff dashboard';
  static const staffTabOverview = 'Overview';
  static const staffTabPayments = 'Payments';
  static const staffRefreshTooltip = 'Refresh';
  static const staffLogoutTooltip = 'Logout';
  static const staffThemeSwitchToLight = 'Switch to light mode';
  static const staffThemeSwitchToDark = 'Switch to dark mode';
  static const staffThemeLightLabel = 'Light';
  static const staffThemeDarkLabel = 'Dark';
  static const staffBackToStartTooltip = 'Back to start';
  static const staffOnShift = 'On Shift';
  static const staffOffShift = 'Off Shift';
  static const staffDayDetailsLabel = 'Day details';
  static const staffTodayButton = 'Today';
  static String staffShowingDay(String label) => 'Showing $label';
  static const staffKpiSessions = 'Sessions';
  static const staffKpiSessionsHint = 'Booth sessions that day';
  static const staffKpiPrints = 'Prints';
  static const staffKpiPrintsHint = 'Print jobs that day';
  static const staffKpiPayments = 'Payments';
  static const staffKpiPaymentsHint = 'Approved payments';
  static const staffKpiRevenue = 'Revenue';
  static const staffKpiRevenueHint = 'Approved total';
  static const staffModeUpi = 'UPI';
  static const staffModeCash = 'Cash';
  static const staffModeComplimentary = 'Complimentary';
  static String staffPaymentCount(int count) =>
      '$count payment${count == 1 ? '' : 's'}';
  /// Guest used Delete My Data; print photo may still be available same day.
  static const staffGuestDataDeletedBadge = 'Guest deleted';
  static const staffPrintPhotosTitle = 'Print photos';
  static const staffPrintPhotoLabel = 'Photo';
  static String staffPrintPhotoN(int n) => 'Photo $n';
  static const staffPreviewPreviousPhoto = 'Previous photo';
  static const staffPreviewNextPhoto = 'Next photo';
  static const staffPrintAll = 'Print all';
  static const staffPrintSelected = 'Print selected';
  static const staffPrintSelectHint =
      'Select photos to print for this session.';
  static const staffStatusLabel = 'Status';
  static const staffCheckedIn = 'Checked In';
  static String staffElapsedLine(String elapsed) => '$elapsed elapsed';
  static const staffRegisterLabel = 'Register';
  static const staffRegisterOpen = 'Open';
  static const staffRegisterClosed = 'Closed';
  static String staffRegisterSince(String time) => 'Since $time';
  static const staffAttendanceTitle = 'Attendance';
  static const staffAttendanceSubtitle = 'Check in or out of your shift';
  static const staffCheckIn = 'Check In';
  static const staffCheckOut = 'Check Out';
  static const staffCheckingIn = 'Checking in…';
  static const staffCheckingOut = 'Checking out…';
  static const staffCloseRegisterBeforeCheckout =
      'Close the register before checking out';
  static const staffCashRegisterTitle = 'Cash register';
  static const staffCashRegisterSubtitle =
      'Open with float; close with actual cash count';
  static const staffOpenRegister = 'Open register';
  static const staffCloseRegister = 'Close register';
  static const staffNoKioskForRegister =
      'This staff member is not assigned to a kiosk. Assign a kiosk in admin before opening the register.';
  static const staffCheckInBeforeRegister =
      'Check in before opening the register';
  static const staffOpenRegisterTitle = 'Open cash register';
  static const staffCloseRegisterTitle = 'Close cash register';
  static const staffOpeningFloatLabel = 'Opening float (₹)';
  static const staffClosingFloatLabel = 'Closing float (₹)';
  static const staffActualAmountLabel = 'Actual amount (₹)';
  static const staffClosingNotesLabel = 'Notes (optional)';
  static const staffOpenRegisterConfirm = 'Open';
  static const staffCloseRegisterConfirm = 'Close';
  static String staffRegisterExpectedLine(String amount) =>
      'Expected: $amount';
  static String staffRegisterReceiptsLine(int n) => 'Receipts: $n';
  static String staffRegisterPrintsLine(int n) => 'Prints: $n';
  static const staffPerformanceTitle = 'Your performance';
  static const staffPerfReceipts = 'Receipts';
  static const staffPerfPrints = 'Prints';
  static const staffPerfRevenue = 'Revenue';
  static const staffPerfHours = 'Hours';

  static const resultPrintCopiesLabel = 'Print copies';
  static String resultPrintCopiesEach(int copies) =>
      copies == 1 ? '1 copy each' : '$copies copies each';
  static String resultPrintSheetsLine(int sheets) =>
      sheets == 1 ? '1 print total' : '$sheets prints total';

  static const kioskDeviceDnpPrinter = 'DNP Printer';
  static const kioskDeviceSelphyPrinter = 'Canon Selphy';
  static const kioskDeviceReceiptPrinter = 'Receipt Printer';
  static const kioskDeviceUsbCamera = 'USB Camera';
  static const kioskDeviceDslrSidecar = 'DSLR Camera';
  static const kioskDeviceConnected = 'Connected';
  static const kioskDeviceNotConnected = 'Not connected';
  static const kioskDeviceNotConfigured = 'Not configured';
  static const kioskDeviceCrashed = 'Crashed — restart app';
  static const kioskDeviceTransportUsb = 'USB';
  static const kioskDeviceTransportWifi = 'WiFi';
  static const kioskDeviceTransportLan = 'LAN';
  static const kioskDeviceTransportUnknown = '—';
  static const kioskDeviceStatusHeading = 'Device status';
  static const kioskDeviceStatusRefresh = 'Refresh';
  static const noPhotoPrinterConnected =
      'No photo printer connected (DNP or Canon Selphy)';

  static const eventStationTitle = 'Event station';
  static const eventStationCapture = 'Capture';
  static const eventStationTheme = 'Theme';
  static const eventStationPrint = 'Print';
  static const eventStationCaptureHint =
      'Photographer: take guest photos. Theme and print happen on other tablets.';
  static const eventStationThemeHint =
      'Guest: pick a look for the photo that is waiting.';
  static const eventStationPrintHint =
      'Printer: claim transformed photos and print.';
  static const eventStationChangeRole = 'Change station';
  static const eventStationNextGuest = 'Capture next guest';
  static const eventStationWaitingTheme = 'Waiting for a photo to style…';
  static const eventStationWaitingPrint = 'Waiting for a photo to print…';
  static const eventStationAssignTheme = 'Use this look';
  static const eventStationNoThemes = 'No themes available for this event.';
  static const eventStationPrintNow = 'Print';
  static const eventStationReprint = 'Print another copy';
  static const eventStationJobClaimed = 'This job was taken by another station.';
  static const eventStationStatusPending = 'PENDING';
  static const eventStationStatusClaimed = 'CLAIMED';
  static const eventStationStatusDone = 'DONE';
  static const eventStationStyleNext = 'Style next guest';
  static const eventStationEmptyCaptures = 'No captured photos yet.';
  static const eventStationEmptyTheme = 'No photos in this status.';
  static const eventStationEmptyPrint = 'No print jobs in this status.';
  static const eventStationStatsCaptures = 'Captured';
  static const eventStationStatsTheme = 'Theme';
  static const eventStationStatsPrint = 'Print';
  static const eventStationStatsLegend = 'PENDING / CLAIMED / DONE';
}
