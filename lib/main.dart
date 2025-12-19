import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/theme_selection/theme_selection_viewmodel.dart';
import 'screens/camera_selection/camera_selection_viewmodel.dart';
import 'screens/terms_and_conditions/terms_and_conditions_view.dart';
import 'screens/theme_selection/theme_selection_view.dart';
import 'screens/camera_selection/camera_selection_view.dart';
import 'screens/photo_capture/photo_capture_view.dart';
import 'screens/photo_review/photo_review_view.dart';
import 'screens/result/result_view.dart';
import 'utils/constants.dart';

void main() {
  runApp(const PhotoBoothApp());
}

class PhotoBoothApp extends StatelessWidget {
  const PhotoBoothApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeViewModel()),
        ChangeNotifierProvider(create: (_) => CameraViewModel()),
      ],
      child: MaterialApp(
        title: 'Photo Booth',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          primarySwatch: Colors.blue,
          useMaterial3: true,
        ),
        initialRoute: AppConstants.kRouteTerms,
        routes: {
          AppConstants.kRouteTerms: (context) =>
              const TermsAndConditionsScreen(),
          AppConstants.kRouteHome: (context) => const ThemeSelectionScreen(),
          AppConstants.kRouteCameraSelection: (context) =>
              const CameraSelectionScreen(),
          AppConstants.kRouteCapture: (context) => const PhotoCaptureScreen(),
          AppConstants.kRouteReview: (context) => const PhotoReviewScreen(),
          AppConstants.kRouteResult: (context) => const ResultScreen(),
        },
      ),
    );
  }
}

