#!/usr/bin/env bash
# Run from photobooth/ (or anywhere): forwards to flutter after syncing pubspec on `flutter build …`.
# Loads photobooth/.env (+ .env.local) and injects BUGSNAG_API_KEY for release/profile mobile builds.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# shellcheck source=scripts/load_env.sh
source "${ROOT}/scripts/load_env.sh"
load_photobooth_env "$ROOT"

is_release_or_profile() {
  for arg in "$@"; do
    case "$arg" in
      --release | --profile) return 0 ;;
    esac
  done
  return 1
}

is_web_target() {
  for arg in "$@"; do
    [[ "$arg" == "web" || "$arg" == "chrome" ]] && return 0
  done
  return 1
}

needs_bugsnag_key() {
  local cmd="${1:-}"
  [[ "$cmd" == "build" || "$cmd" == "run" ]] || return 1
  is_web_target "${@:2}" && return 1
  is_release_or_profile "${@:2}"
}

append_bugsnag_dart_define() {
  if [[ -z "${BUGSNAG_API_KEY:-}" ]]; then
    echo "BUGSNAG_API_KEY is required for release/profile mobile builds." >&2
    echo "Add it to photobooth/.env (copy from .env.example) or export BUGSNAG_API_KEY." >&2
    exit 1
  fi
  FLUTTER_ARGS+=(--dart-define="BUGSNAG_API_KEY=${BUGSNAG_API_KEY}")
}

FLUTTER_ARGS=("$@")

if [[ "${1:-}" == "build" ]]; then
  dart run tool/sync_build_version.dart
fi

if [[ $# -gt 0 ]] && needs_bugsnag_key "$@"; then
  append_bugsnag_dart_define
fi

exec flutter "${FLUTTER_ARGS[@]}"
