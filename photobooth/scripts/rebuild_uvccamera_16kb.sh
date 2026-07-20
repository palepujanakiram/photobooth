#!/usr/bin/env bash
# Rebuild org.uvccamera:lib at tag 0.0.13 with 16 KB ELF alignment (NDK r28+)
# and vendor into packages/uvccamera (jniLibs + classes.jar + proguard).
#
# Requires: git, Android SDK, NDK 28.2.13676358 (or set NDK_VERSION).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_ANDROID="${ROOT}/packages/uvccamera/android"
LIBS_DIR="${PLUGIN_ANDROID}/libs"
JNI_DIR="${PLUGIN_ANDROID}/src/main/jniLibs"
WORK_DIR="${ROOT}/.tmp-uvccamera-16kb"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-${HOME}/Library/Android/sdk}}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
UVCCAMERA_TAG="${UVCCAMERA_TAG:-0.0.13}"

if [[ ! -d "${SDK}/ndk/${NDK_VERSION}" ]]; then
  echo "ERROR: NDK ${NDK_VERSION} not found under ${SDK}/ndk" >&2
  exit 1
fi

rm -rf "${WORK_DIR}"
git clone --depth 1 --branch "${UVCCAMERA_TAG}" \
  https://github.com/alexey-pelykh/UVCCamera.git "${WORK_DIR}"

cat >> "${WORK_DIR}/lib/src/main/jni/Application.mk" <<'EOF'

# 16 KB page size alignment for Android 15+ / Google Play
# https://developer.android.com/guide/practices/page-sizes
APP_SUPPORT_FLEXIBLE_PAGE_SIZES := true
APP_LDFLAGS := -Wl,-z,max-page-size=16384
EOF

python3 - <<PY
from pathlib import Path
p = Path("${WORK_DIR}/lib/build.gradle.kts")
text = p.read_text()
needle = 'android {\n    namespace = "org.uvccamera.lib"\n    compileSdk = 34\n'
insert = needle + '    ndkVersion = "${NDK_VERSION}"\n'
if "ndkVersion" not in text:
    if needle not in text:
        raise SystemExit("Unexpected lib/build.gradle.kts layout; cannot pin ndkVersion")
    p.write_text(text.replace(needle, insert, 1))
PY

printf 'sdk.dir=%s\n' "${SDK}" > "${WORK_DIR}/local.properties"

(
  cd "${WORK_DIR}"
  ./gradlew :lib:assembleRelease --no-daemon
)

BUILT_AAR="$(find "${WORK_DIR}/lib/build/outputs/aar" -name '*.aar' | head -1)"
if [[ -z "${BUILT_AAR}" || ! -f "${BUILT_AAR}" ]]; then
  echo "ERROR: release AAR not produced" >&2
  exit 1
fi

EXTRACT="$(mktemp -d)"
unzip -q "${BUILT_AAR}" -d "${EXTRACT}"

mkdir -p "${LIBS_DIR}" "${JNI_DIR}" "${PLUGIN_ANDROID}/src/main/res/xml"
rm -rf "${JNI_DIR:?}/"*
cp -R "${EXTRACT}/jni/"* "${JNI_DIR}/"
cp "${EXTRACT}/classes.jar" "${LIBS_DIR}/uvccamera-lib-classes.jar"
cp "${EXTRACT}/proguard.txt" "${LIBS_DIR}/uvccamera-lib-proguard.txt"
if [[ -f "${EXTRACT}/res/xml/device_filter.xml" ]]; then
  cp "${EXTRACT}/res/xml/device_filter.xml" "${PLUGIN_ANDROID}/src/main/res/xml/device_filter.xml"
fi

OBJDUMP="$(find "${SDK}/ndk/${NDK_VERSION}" -path '*/bin/llvm-objdump' | head -1)"
FAIL=0
for so in "${JNI_DIR}"/arm64-v8a/*.so; do
  align_pow="$("${OBJDUMP}" -p "${so}" | awk '/^[[:space:]]*LOAD / { gsub(/2\*\*/, "", $NF); print $NF }' | sort -n | head -1)"
  align=$((2 ** align_pow))
  if (( align < 16384 )); then
    echo "FAIL: $(basename "${so}") LOAD align=${align}"
    FAIL=1
  else
    echo "OK:   $(basename "${so}") LOAD align=${align}"
  fi
done

rm -rf "${EXTRACT}" "${WORK_DIR}"
if (( FAIL != 0 )); then
  echo "ERROR: rebuilt native libs are not 16 KB aligned" >&2
  exit 1
fi
echo "Done. Vendored 16 KB-aligned UVCCamera into ${PLUGIN_ANDROID}"
