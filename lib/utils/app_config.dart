/// Application Configuration
///
/// This file contains all configurable URLs and links.
/// Modify these values to change the app's endpoints without code changes.
class AppConfig {
  // API Configuration
  /// Base URL for the API endpoints
  /// 
  /// For development with CORS issues, you can use:
  /// - A CORS proxy: 'https://cors-anywhere.herokuapp.com/https://zenai-labs.replit.app'
  /// - A local proxy server: 'http://localhost:8080/api'
  /// 
  /// For production, ensure the server has proper CORS headers configured.
  /// 
  /// Base URL for the API endpoints
  /// NOTE: For web development, you MUST run Chrome with CORS disabled
  /// See QUICK_CORS_FIX.md or run: ./run_chrome_dev.sh
  static const String baseUrl = 'https://fotozenai.fly.dev';

  // Links
  /// Terms and Conditions page URL
  static const String termsAndConditionsUrl =
      'https://fotozenai.fly.dev/terms';
}
