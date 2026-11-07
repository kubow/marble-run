#!/usr/bin/env bash
# Builds the Android debug APK (arm64-v8a, non-Gradle export).
#
# Requirements (see BUILD.md):
#   - godot 4.7.x on PATH (or GODOT=/path/to/godot)
#   - export templates for the same version in ~/.local/share/godot/export_templates/<ver>/
#   - ANDROID_HOME pointing at an SDK with build-tools (apksigner) and platform-tools (adb)
#   - a Java runtime (keytool/apksigner); JAVA_HOME optional
#
# Usage: tools/build_android.sh [debug|release] [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

MODE="${1:-debug}"
INSTALL="${2:-}"
GODOT="${GODOT:-godot}"
export ANDROID_HOME="${ANDROID_HOME:-$HOME/Android/Sdk}"
KEYSTORE="${GODOT_ANDROID_KEYSTORE_DEBUG_PATH:-$HOME/.android/debug.keystore}"

if [[ ! -d "$ANDROID_HOME/build-tools" ]]; then
  echo "error: no Android build-tools in $ANDROID_HOME" >&2; exit 1
fi

# Debug keystore (standard Android debug credentials).
if [[ "$MODE" == "debug" && ! -f "$KEYSTORE" ]]; then
  mkdir -p "$(dirname "$KEYSTORE")"
  keytool -genkeypair -v -keystore "$KEYSTORE" -storepass android -alias androiddebugkey \
    -keypass android -keyalg RSA -keysize 2048 -validity 10000 \
    -dname "CN=Android Debug,O=Android,C=US"
fi
export GODOT_ANDROID_KEYSTORE_DEBUG_PATH="$KEYSTORE"
export GODOT_ANDROID_KEYSTORE_DEBUG_USER="${GODOT_ANDROID_KEYSTORE_DEBUG_USER:-androiddebugkey}"
export GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD="${GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD:-android}"

mkdir -p builds
OUT="builds/marble-run-$MODE.apk"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
if [[ "$MODE" == "release" ]]; then
  # Requires GODOT_ANDROID_KEYSTORE_RELEASE_{PATH,USER,PASSWORD}.
  "$GODOT" --headless --path . --export-release "Android" "$OUT"
else
  "$GODOT" --headless --path . --export-debug "Android" "$OUT"
fi
ls -l "$OUT"
"$ANDROID_HOME"/build-tools/*/apksigner verify --print-certs "$OUT" | head -3 || true

if [[ "$INSTALL" == "--install" ]]; then
  ADB="$ANDROID_HOME/platform-tools/adb"
  "$ADB" devices
  "$ADB" install -r "$OUT"
  "$ADB" shell monkey -p io.github.kubow.marblerun -c android.intent.category.LAUNCHER 1
fi
