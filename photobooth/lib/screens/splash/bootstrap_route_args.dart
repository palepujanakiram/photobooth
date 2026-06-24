/// Arguments for the app splash route (`AppConstants.kRouteSplash`).
class SplashRouteArgs {
  const SplashRouteArgs({this.manageKiosk = false});

  /// When true, full-screen kiosk management (change / disconnect) instead of
  /// auto-advancing to terms.
  final bool manageKiosk;
}

/// Arguments for the terms route when pushing by name (`AppConstants.kRouteTerms`).
class TermsRouteArgs {
  const TermsRouteArgs({
    this.backgroundImageUrls,
    this.capturePhoto,
  });

  /// Sample image URLs from kiosk themes for the animated background grid.
  /// Null or empty falls back to default asset slideshow.
  final List<String>? backgroundImageUrls;

  /// Optional photo to prefill on the capture route after terms acceptance.
  /// Typed as Object? to avoid importing capture models into the splash module.
  final Object? capturePhoto;
}
