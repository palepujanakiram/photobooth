#!/usr/bin/env bash
# Verify 16 KB ELF LOAD alignment for arm64-v8a / x86_64 native libraries.
# Usage:
#   ./scripts/verify_16kb_alignment.sh path/to/app.apk
#   ./scripts/verify_16kb_alignment.sh path/to/app.aab
#
# Exit 0 if all 64-bit .so LOAD segments have p_align >= 16384.
set -euo pipefail

ARTIFACT="${1:-}"
if [[ -z "${ARTIFACT}" || ! -f "${ARTIFACT}" ]]; then
  echo "Usage: $0 <apk-or-aab>" >&2
  exit 2
fi

ANDROID_SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${HOME}/Library/Android/sdk}}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
HOST_TAG="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$(uname -m)" in
  arm64|aarch64) LLVM_HOST="darwin-x86_64" ;; # Apple Silicon NDK still uses darwin-x86_64 prebuilt
  x86_64) LLVM_HOST="${HOST_TAG}-x86_64" ;;
  *) LLVM_HOST="${HOST_TAG}-x86_64" ;;
esac

OBJDUMP="${ANDROID_SDK}/ndk/${NDK_VERSION}/toolchains/llvm/prebuilt/${LLVM_HOST}/bin/llvm-objdump"
if [[ ! -x "${OBJDUMP}" ]]; then
  # Fall back to any installed NDK r28+
  OBJDUMP="$(find "${ANDROID_SDK}/ndk" -path '*/toolchains/llvm/prebuilt/*/bin/llvm-objdump' 2>/dev/null | sort -V | tail -1 || true)"
fi
if [[ -z "${OBJDUMP}" || ! -x "${OBJDUMP}" ]]; then
  echo "ERROR: llvm-objdump not found under ${ANDROID_SDK}/ndk" >&2
  exit 2
fi

WORKDIR="$(mktemp -d -t verify16kb_XXXXXX)"
trap 'rm -rf "${WORKDIR}"' EXIT

case "${ARTIFACT}" in
  *.aab)
    unzip -q "${ARTIFACT}" -d "${WORKDIR}/bundle"
    LIB_ROOT="${WORKDIR}/bundle/base/lib"
    ;;
  *.apk)
    unzip -q "${ARTIFACT}" -d "${WORKDIR}/apk"
    LIB_ROOT="${WORKDIR}/apk/lib"
    ;;
  *)
    echo "ERROR: expected .apk or .aab, got ${ARTIFACT}" >&2
    exit 2
    ;;
esac

if [[ ! -d "${LIB_ROOT}" ]]; then
  echo "OK: no native libraries found in ${ARTIFACT}"
  exit 0
fi

ISSUES=0
CHECKED=0
MIN_ALIGN=16384

for abi in arm64-v8a x86_64; do
  abi_dir="${LIB_ROOT}/${abi}"
  [[ -d "${abi_dir}" ]] || continue
  shopt -s nullglob
  for so in "${abi_dir}"/*.so; do
    CHECKED=$((CHECKED + 1))
    # Lowest PT_LOAD align value only (ignore PHDR/DYNAMIC/etc.), e.g. 2**12 or 2**14
    align_pow="$("${OBJDUMP}" -p "${so}" | awk '/^[[:space:]]*LOAD / { gsub(/2\*\*/, "", $NF); print $NF }' | sort -n | head -1)"
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
