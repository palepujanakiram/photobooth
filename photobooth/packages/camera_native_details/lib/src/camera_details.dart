/// Result of native camera characteristics (Android Camera2; placeholders on iOS/Web).
class CameraDetails {
  const CameraDetails({
    this.activeArrayWidth,
    this.activeArrayHeight,
    this.zoomRatioRangeMin,
    this.zoomRatioRangeMax,
    this.maxDigitalZoom,
    this.supportedPreviewSizes = const [],
    this.supportedCaptureSizes = const [],
    this.lensFacing,
    this.platform = 'unknown',
  });

  /// Sensor active array width (SENSOR_INFO_ACTIVE_ARRAY_SIZE). Null if unavailable.
  final int? activeArrayWidth;

  /// Sensor active array height.
  final int? activeArrayHeight;

  /// Minimum zoom ratio (CONTROL_ZOOM_RATIO_RANGE, API 30+). Null if unavailable.
  final double? zoomRatioRangeMin;

  /// Maximum zoom ratio.
  final double? zoomRatioRangeMax;

  /// SCALER_AVAILABLE_MAX_DIGITAL_ZOOM. Null if unavailable.
  final double? maxDigitalZoom;

  /// List of "widthxheight" preview sizes from stream configuration. Empty if unavailable.
  final List<String> supportedPreviewSizes;

  /// List of "widthxheight" capture (e.g. JPEG) sizes. Empty if unavailable.
  final List<String> supportedCaptureSizes;

  /// LENS_FACING: "back" | "front" | "external". Null if unavailable.
  final String? lensFacing;

  /// Platform that provided the data: "android" | "ios" | "web".
  final String platform;

  /// Creates from the platform channel map (Android).
  factory CameraDetails.fromMap(Map<Object?, Object?> map) {
    return CameraDetails(
      activeArrayWidth: _intFrom(map['activeArrayWidth']),
      activeArrayHeight: _intFrom(map['activeArrayHeight']),
      zoomRatioRangeMin: _doubleFrom(map['zoomRatioRangeMin']),
      zoomRatioRangeMax: _doubleFrom(map['zoomRatioRangeMax']),
      maxDigitalZoom: _doubleFrom(map['maxDigitalZoom']),
      supportedPreviewSizes: _stringListFrom(map['supportedPreviewSizes']),
      supportedCaptureSizes: _stringListFrom(map['supportedCaptureSizes']),
      lensFacing: map['lensFacing'] as String?,
      platform: map['platform'] as String? ?? 'unknown',
    );
  }

  static int? _intFrom(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return null;
  }

  static double? _doubleFrom(Object? v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    return null;
  }

  static List<String> _stringListFrom(Object? v) {
    if (v == null) return const [];
    if (v is List) {
      return v.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  /// Default/placeholder values for iOS and Web (to be implemented later).
  factory CameraDetails.defaultValues({required String platform}) {
    return CameraDetails(
      activeArrayWidth: null,
      activeArrayHeight: null,
      zoomRatioRangeMin: null,
      zoomRatioRangeMax: null,
      maxDigitalZoom: null,
      supportedPreviewSizes: const [],
      supportedCaptureSizes: const [],
      lensFacing: null,
      platform: platform,
    );
  }
}
