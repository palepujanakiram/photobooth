/// 5×4 row-major color matrices matching Flutter [ColorFilter.matrix] looks
/// in the Classic look picker. Used for on-screen preview and for baking the
/// same grade into compose / print uploads (server Sharp grades wash looks).
List<double> stripLookColorMatrixValues(String filterId) {
  switch (filterId) {
    case 'classic_warm':
      return const <double>[
        1.05, 0.05, 0, 0, 8,
        0.02, 0.95, 0, 0, 4,
        0, 0.02, 0.88, 0, 0,
        0, 0, 0, 1, 0,
      ];
    case 'peach_glow':
      return const <double>[
        1.1, 0.08, 0.04, 0, 14,
        0.06, 0.98, 0.04, 0, 8,
        0.04, 0.06, 0.9, 0, 6,
        0, 0, 0, 1, 0,
      ];
    case 'soft_film':
      return const <double>[
        0.95, 0.05, 0, 0, 10,
        0.05, 0.95, 0, 0, 10,
        0, 0.05, 0.95, 0, 10,
        0, 0, 0, 1, 0,
      ];
    case 'candy_pop':
      return const <double>[
        1.15, 0.05, 0, 0, 0,
        0, 1.05, 0.05, 0, 0,
        0.05, 0, 1.2, 0, 0,
        0, 0, 0, 1, 0,
      ];
    case 'golden_hour':
      return const <double>[
        1.14, 0.1, 0.02, 0, 12,
        0.06, 0.96, 0.02, 0, 6,
        0, 0.04, 0.78, 0, 0,
        0, 0, 0, 1, 0,
      ];
    case 'cool_mint':
      return const <double>[
        0.88, 0.04, 0.06, 0, 2,
        0.04, 1.06, 0.08, 0, 6,
        0.06, 0.1, 1.12, 0, 8,
        0, 0, 0, 1, 0,
      ];
    case 'gloss_pop':
      return const <double>[
        1.2, 0.02, 0.06, 0, -6,
        0, 1.12, 0.08, 0, -4,
        0.08, 0, 1.24, 0, -2,
        0, 0, 0, 1, 0,
      ];
    case 'mono':
      return const <double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ];
    case 'clean':
    default:
      return const <double>[
        1, 0, 0, 0, 0,
        0, 1, 0, 0, 0,
        0, 0, 1, 0, 0,
        0, 0, 0, 1, 0,
      ];
  }
}

/// Whether baking is a no-op for this look id (identity / clean).
bool stripLookNeedsMatrixBake(String filterId) {
  final id = filterId.trim();
  if (id.isEmpty || id == 'clean') return false;
  final m = stripLookColorMatrixValues(id);
  const identity = <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ];
  if (m.length != identity.length) return true;
  for (var i = 0; i < m.length; i++) {
    if (m[i] != identity[i]) return true;
  }
  return false;
}

/// Server filter id when the look grade was already baked client-side.
const String kStripComposePreBakedFilterId = 'clean';
