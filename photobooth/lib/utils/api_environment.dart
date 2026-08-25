/// Which Fly.io API host the booth talks to.
enum ApiEnvironment {
  /// Production: `https://fotozenai.fly.dev`
  live,

  /// Staging: `https://zenai.fly.dev`
  stage,
}

extension ApiEnvironmentX on ApiEnvironment {
  String get baseUrl {
    switch (this) {
      case ApiEnvironment.live:
        return 'https://fotozenai.fly.dev';
      case ApiEnvironment.stage:
        return 'https://zenai.fly.dev';
    }
  }

  /// Short label for splash / staff UI.
  String get label {
    switch (this) {
      case ApiEnvironment.live:
        return 'Live';
      case ApiEnvironment.stage:
        return 'Stage';
    }
  }

  /// Host-only hint under the Stage/Live control.
  String get hostHint {
    switch (this) {
      case ApiEnvironment.live:
        return 'fotozenai.fly.dev';
      case ApiEnvironment.stage:
        return 'zenai.fly.dev';
    }
  }
}

/// Parses prefs / query values. Unknown → null (caller uses branch default).
ApiEnvironment? apiEnvironmentFromStorage(String? raw) {
  final v = raw?.trim().toLowerCase();
  if (v == null || v.isEmpty) return null;
  if (v == 'live' || v == 'prod' || v == 'production') {
    return ApiEnvironment.live;
  }
  if (v == 'stage' || v == 'staging' || v == 'zenai') {
    return ApiEnvironment.stage;
  }
  // Allow storing a full base URL.
  if (v.contains('fotozenai.fly.dev')) return ApiEnvironment.live;
  if (v.contains('zenai.fly.dev')) return ApiEnvironment.stage;
  return null;
}

String apiEnvironmentStorageValue(ApiEnvironment env) {
  switch (env) {
    case ApiEnvironment.live:
      return 'live';
    case ApiEnvironment.stage:
      return 'stage';
  }
}
