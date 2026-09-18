#!/usr/bin/env bash
# Verify 16 KB ELF LOAD alignment for arm64-v8a / x86_64 native libraries.
# Usage:
#   ./scripts/verify_16kb_alignment.sh path/to/app.apk
#   ./scripts/verify_16kb_alignment.sh path/to/app.aab
#
# Exit 0 if all 64-bit .so LOAD segments have p_align >= 16384.
set -euo pipefail

log() {
  echo "verify_16kb: $*" >&2
}

ARTIFACT="${1:-}"
if [[ -z "${ARTIFACT}" || ! -f "${ARTIFACT}" ]]; then
  echo "Usage: $0 <apk-or-aab>" >&2
  exit 2
fi

ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${HOME}/Library/Android/sdk}}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"

resolve_objdump() {
  local sdk="$1"
  local preferred_ver="$2"
  local hosts=(darwin-arm64 darwin-x86_64 linux-x86_64)
  local ndk_root="${sdk}/ndk"
  local versions=()
  local ver host candidate

  [[ -d "${ndk_root}" ]] || return 1
  versions=("${preferred_ver}")
  # Directory names only — never walk the NDK tree (that can look hung for minutes).
  while IFS= read -r ver; do
    [[ "${ver}" == "${preferred_ver}" ]] && continue
    versions+=("${ver}")
  done < <(ls -1 "${ndk_root}" 2>/dev/null | sort -V -r)

  for ver in "${versions[@]}"; do
    for host in "${hosts[@]}"; do
      candidate="${ndk_root}/${ver}/toolchains/llvm/prebuilt/${host}/bin/llvm-objdump"
      if [[ -x "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return 0
      fi
    done
  done
  return 1
}

log "checking $(basename "${ARTIFACT}")"
OBJDUMP="$(resolve_objdump "${ANDROID_SDK}" "${NDK_VERSION}" || true)"
if [[ -z "${OBJDUMP}" || ! -x "${OBJDUMP}" ]]; then
  echo "ERROR: llvm-objdump not found under ${ANDROID_SDK}/ndk" >&2
  exit 2
fi
log "using ${OBJDUMP}"

WORKDIR="$(mktemp -d -t verify16kb_XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

list_64bit_sos() {
  zipinfo -1 "$1" | grep -E '(^|/)lib/(arm64-v8a|x86_64)/[^/]+\.so$' || true
}

SOS="$(list_64bit_sos "${ARTIFACT}")"
if [[ -z "${SOS}" ]]; then
  echo "OK: no arm64-v8a/x86_64 native libraries to check"
  exit 0
fi

SO_COUNT="$(printf '%s\n' "${SOS}" | grep -c .)"
log "extracting ${SO_COUNT} native libraries (not the full archive)"
SO_FILES=()
while IFS= read -r so_path; do
  [[ -n "${so_path}" ]] && SO_FILES+=("${so_path}")
done <<<"${SOS}"
unzip -q -o "${ARTIFACT}" "${SO_FILES[@]}" -d "${WORKDIR}"

if [[ -d "${WORKDIR}/base/lib" ]]; then
  LIB_ROOT="${WORKDIR}/base/lib"
else
  LIB_ROOT="${WORKDIR}/lib"
fi

ISSUES=0
CHECKED=0
MIN_ALIGN=16384

load_align_pow() {
  # Avoid `head` in a pipefail pipeline (SIGPIPE can abort the script).
  "$1" -p "$2" | awk '
    /^[[:space:]]*LOAD / {
      gsub(/2\*\*/, "", $NF)
      if (n == 0 || $NF + 0 < n) n = $NF + 0
    }
    END { if (n != "") print n }
  '
}

for abi in arm64-v8a x86_64; do
  abi_dir="${LIB_ROOT}/${abi}"
  [[ -d "${abi_dir}" ]] || continue
  shopt -s nullglob
  for so in "${abi_dir}"/*.so; do
    CHECKED=$((CHECKED + 1))
    log "objdump ${CHECKED}/${SO_COUNT} ${abi}/$(basename "${so}")"
    align_pow="$(load_align_pow "${OBJDUMP}" "${so}")"
    if [[ -z "${align_pow}" ]]; then
      echo "FAIL: ${abi}/$(basename "${so}") — no LOAD segments found"
      ISSUES=$((ISSUES + 1))
      continue
    fi
    align=$((2 ** align_pow))
    rel="${abi}/$(basename "${so}")"
    if (( align < MIN_ALIGN )); then
      echo "FAIL: ${rel} LOAD align=${align} (need >= ${MIN_ALIGN})"
      ISSUES=$((ISSUES + 1))
    else
      echo "OK:   ${rel} LOAD align=${align}"
    fi
  done
  shopt -u nullglob
done

if (( CHECKED == 0 )); then
  echo "OK: no arm64-v8a/x86_64 native libraries to check"
  exit 0
fi

echo "----"
if (( ISSUES == 0 )); then
  echo "RESULT: PASS (${CHECKED} libraries, 16 KB ELF aligned)"
  exit 0
fi

echo "RESULT: FAIL (${ISSUES}/${CHECKED} libraries not 16 KB aligned)"
exit 1
