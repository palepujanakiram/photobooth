#!/usr/bin/env bash
# Load KEY=value pairs from .env files into the environment.
# Existing shell variables are not overwritten (.env.local wins over .env for unset keys only).
#
# Usage (from photobooth/):
#   source scripts/load_env.sh
#   source scripts/load_env.sh /path/to/custom.env

load_env_file() {
  local file="$1"
  [[ -f "$file" ]] || return 0

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Skip blank lines and full-line comments.
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" =~ ^[[:space:]]*# ]] && continue

    if [[ "$line" =~ ^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
      local key="${BASH_REMATCH[1]}"
      local val="${BASH_REMATCH[2]}"
      val="${val%"${val##*[![:space:]]}"}"
      val="${val#"${val%%[![:space:]]*}"}"

      if [[ "$val" =~ ^\".*\"$ ]]; then
        val="${val:1:${#val}-2}"
      elif [[ "$val" =~ ^\'.*\'$ ]]; then
        val="${val:1:${#val}-2}"
      fi

      if [[ -z "${!key:-}" ]]; then
        export "${key}=${val}"
      fi
    fi
  done <"$file"
}

load_photobooth_env() {
  local root="${1:-}"
  if [[ -z "$root" ]]; then
    root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  fi
  load_env_file "${root}/.env"
  load_env_file "${root}/.env.local"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  load_photobooth_env "${1:-}"
fi
