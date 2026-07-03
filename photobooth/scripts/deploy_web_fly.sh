#!/usr/bin/env bash
# Build Flutter web and deploy to Fly.io with a single machine (no HA pair).
#
# Usage (from photobooth/ or repo root):
#   ./scripts/deploy_web_fly.sh
#   BASE_URL=https://fotozenai.fly.dev ./scripts/deploy_web_fly.sh
#
# First-time: fly apps create fotozen-web

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Same-origin API via nginx proxy (deploy/nginx.web.conf) — avoids browser CORS.
WEB_PUBLIC_URL="${WEB_PUBLIC_URL:-https://fotozen-web.fly.dev}"
BASE_URL="${BASE_URL:-$WEB_PUBLIC_URL}"
FLY_CONFIG="${FLY_CONFIG:-fly.web.toml}"

dart run tool/sync_build_version.dart
DART_DEFINES=(--dart-define="BASE_URL=${BASE_URL}")
if [ -n "${API_BEARER_TOKEN:-}" ]; then
  DART_DEFINES+=(--dart-define="API_BEARER_TOKEN=${API_BEARER_TOKEN}")
fi
flutter build web --release "${DART_DEFINES[@]}"

# Default fly deploy creates 2 machines for http_service; --ha=false uses one.
fly deploy -c "${FLY_CONFIG}" --ha=false

# Ensure scale stays at 1 if a previous deploy created a spare machine.
fly scale count 1 -y -c "${FLY_CONFIG}"
