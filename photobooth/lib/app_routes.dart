// Named-route table for MaterialApp (extracted from main for Sonar complexity).
import 'package:flutter/material.dart';

import 'screens/frame_select/frame_select_view.dart';
import 'screens/pre_payment/pre_payment_view.dart';
import 'screens/photo_capture/photo_capture_view.dart';
import 'screens/photo_generate/photo_generate_progress_view.dart';
import 'screens/photo_generate/photo_generate_view.dart';
import 'screens/photo_review/photo_review_view.dart';
import 'screens/qr_share/qr_share_view.dart';
import 'screens/result/result_view.dart';
import 'screens/splash/app_splash_screen.dart';
import 'screens/splash/bootstrap_route_args.dart';
import 'screens/staff/staff_dashboard_view.dart';
import 'screens/staff/staff_login_view.dart';
import 'screens/staff/staff_payments_view.dart';
import 'screens/terms_and_conditions/terms_and_conditions_view.dart';
import 'screens/theme_selection/theme_selection_view.dart';
import 'screens/theme_slideshow/theme_slideshow_view.dart';
import 'screens/thank_you/thank_you_view.dart';
import 'screens/webview/webview_screen.dart';
import 'utils/constants.dart';

/// Returns all [AppConstants] route names → screen builders, including typed args.
Map<String, WidgetBuilder> buildAppRoutes() {
  return {
    AppConstants.kRouteSlideshow: (context) => const ThemeSlideshowScreen(),
    AppConstants.kRouteSplash: (context) {
      final raw = ModalRoute.of(context)?.settings.arguments;
      final args = raw is SplashRouteArgs ? raw : const SplashRouteArgs();
      return AppSplashScreen(args: args);
    },
    AppConstants.kRouteTerms: (context) {
      final raw = ModalRoute.of(context)?.settings.arguments;
      final urls = raw is TermsRouteArgs ? raw.backgroundImageUrls : null;
      final bg = (urls != null && urls.isNotEmpty) ? urls : null;
      return TermsAndConditionsScreen(backgroundImageUrls: bg);
    },
    AppConstants.kRouteHome: (context) => const ThemeSelectionScreen(),
    AppConstants.kRouteCapture: (context) => const PhotoCaptureScreen(),
    AppConstants.kRouteFrameSelect: (context) => const FrameSelectScreen(),
    AppConstants.kRouteGenerate: (context) => const PhotoGenerateScreen(),
    AppConstants.kRouteGenerateProgress: (context) =>
        const PhotoGenerateProgressScreen(),
    AppConstants.kRoutePrePayment: (context) => const PrePaymentScreen(),
    AppConstants.kRouteReview: (context) => const PhotoReviewScreen(),
    AppConstants.kRouteResult: (context) => const ResultScreen(),
    AppConstants.kRouteQrShare: (context) => const QrShareScreen(),
    AppConstants.kRouteThankYou: (context) => const ThankYouScreen(),
    AppConstants.kRouteStaffLogin: (context) => const StaffLoginScreen(),
    AppConstants.kRouteStaffDashboard: (context) => const StaffDashboardScreen(),
    AppConstants.kRouteStaffPayments: (context) => const StaffPaymentsScreen(),
    AppConstants.kRouteWebView: (context) => WebViewScreen.fromRouteSettings(
          ModalRoute.of(context)?.settings,
        ),
  };
}
