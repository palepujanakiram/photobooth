#!/bin/bash
# Flutter web dev: local API proxy + optional CORS-disabled Chrome.
set -euo pipefail
cd "$(dirname "$0")"

PROXY_PORT="${PROXY_PORT:-8787}"
PROXY_UPSTREAM="${PROXY_UPSTREAM:-https://fotozenai.fly.dev}"
PROXY_PID=""

cleanup() {
  if [[ -n "$PROXY_PID" ]]; then
    kill "$PROXY_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT INT TERM

echo "Starting dev API proxy on http://127.0.0.1:${PROXY_PORT} → ${PROXY_UPSTREAM}"
dart run tool/dev_api_proxy.dart --port="$PROXY_PORT" --upstream="$PROXY_UPSTREAM" &
PROXY_PID=$!
sleep 1

echo ""
echo "Starting Flutter web (BASE_URL=http://127.0.0.1:${PROXY_PORT})"
echo "Photo PATCH uploads go through the proxy to avoid browser XHR hangs."
echo ""

flutter run -d chrome \
  --dart-define="BASE_URL=http://127.0.0.1:${PROXY_PORT}" \
  --web-browser-flag "--disable-web-security" \
  --web-browser-flag "--disable-site-isolation-trials" \
  --web-browser-flag "--user-data-dir=/tmp/flutter_chrome_dev_cors"
