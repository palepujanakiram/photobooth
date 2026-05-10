#!/usr/bin/env bash
# Run from repo root or anywhere: forwards to flutter after syncing pubspec on `flutter build …`.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "${1:-}" == "build" ]]; then
  dart run tool/sync_build_version.dart
fi
exec flutter "$@"
