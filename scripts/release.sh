#!/usr/bin/env bash
#
# release.sh -- build a slim release Android APK for any Flutter project.
#
# Runs: pub get -> analyze -> test -> build apk (release, obfuscated) and
# copies the APK (plus Dart symbols) into an output directory.
#
# Usage:
#   scripts/release.sh [options]
#
# Options:
#   -o, --output DIR    Output directory for artifacts (default: dist)
#   -p, --proxy URL     Proxy for pub/gradle, e.g. socks5://127.0.0.1:19998.
#                       Defaults to $ALL_PROXY/$HTTPS_PROXY, else the SOCKS
#                       proxy in android/gradle.properties (if any).
#       --abi ABI       Target ABI: arm64-v8a | armeabi-v7a | x86_64
#                       (default: arm64-v8a)
#       --build-name V  Override the version name (e.g. 1.2.3)
#       --build-number N Override the version code (integer)
#       --debug         Build a debug APK instead of release
#       --no-obfuscate  Disable Dart obfuscation + symbol split
#       --no-analyze    Skip `flutter analyze`
#       --no-test       Skip `flutter test`
#   -h, --help          Show this help
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# ------------------------------------------------------------------ pretty
if [ -t 1 ]; then
  BOLD="$(tput bold 2>/dev/null || true)"
  DIM="$(tput dim 2>/dev/null || true)"
  GREEN="$(tput setaf 2 2>/dev/null || true)"
  RED="$(tput setaf 1 2>/dev/null || true)"
  RESET="$(tput sgr0 2>/dev/null || true)"
else
  BOLD=""; DIM=""; GREEN=""; RED=""; RESET=""
fi
step() { printf '\n%s==> %s%s\n' "$BOLD$GREEN" "$*" "$RESET"; }
info() { printf '%s%s%s\n' "$DIM" "$*" "$RESET"; }
die()  { printf '%serror: %s%s\n' "$RED" "$*" "$RESET" >&2; exit 1; }

# ------------------------------------------------------------------ defaults
OUT_DIR="dist"
PROXY=""
ABI="arm64-v8a"
BUILD_NAME=""
BUILD_NUMBER=""
OBFUSCATE=1
ANALYZE=1
TEST=1
MODE="release"

usage() {
  awk 'NR>1 { if ($0 ~ /^#/) { sub(/^# ?/, ""); print; next } else { exit } }' \
    "${BASH_SOURCE[0]}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    -o|--output)    OUT_DIR="${2:?missing dir}"; shift 2 ;;
    -p|--proxy)     PROXY="${2:?missing url}"; shift 2 ;;
    --abi)          ABI="${2:?missing abi}"; shift 2 ;;
    --build-name)   BUILD_NAME="${2:?missing version}"; shift 2 ;;
    --build-number) BUILD_NUMBER="${2:?missing code}"; shift 2 ;;
    --debug)        MODE="debug"; shift ;;
    --no-obfuscate) OBFUSCATE=0; shift ;;
    --no-analyze)   ANALYZE=0; shift ;;
    --no-test)      TEST=0; shift ;;
    -h|--help)      usage; exit 0 ;;
    *)              die "unknown option: $1 (try --help)" ;;
  esac
done

case "$ABI" in
  arm64-v8a)   TARGET_PLATFORM="android-arm64" ;;
  armeabi-v7a) TARGET_PLATFORM="android-arm" ;;
  x86_64)      TARGET_PLATFORM="android-x64" ;;
  *)           die "unsupported --abi: $ABI" ;;
esac

[ -f pubspec.yaml ] || die "pubspec.yaml not found; run from the project"

# ------------------------------------------------------------------ metadata
APP_NAME="$(awk -F': *' '/^name:/{print $2; exit}' pubspec.yaml)"
VERSION="$(awk -F': *' '/^version:/{print $2; exit}' pubspec.yaml)"
APP_NAME="${APP_NAME:-app}"
VERSION="${VERSION:-0.0.0}"
SAFE_VERSION="${VERSION//+/_}"
info "project : $APP_NAME"
info "version : $VERSION"
info "abi     : $ABI"

# ------------------------------------------------------------------ proxy
detect_proxy() {
  [ -n "${ALL_PROXY:-}" ]   && { printf '%s' "$ALL_PROXY"; return; }
  [ -n "${HTTPS_PROXY:-}" ] && { printf '%s' "$HTTPS_PROXY"; return; }
  local gp="$ROOT/android/gradle.properties" h p
  if [ -f "$gp" ]; then
    h="$(awk -F= '/systemProp\.socksProxyHost/{print $2; exit}' "$gp" | tr -d ' ')"
    p="$(awk -F= '/systemProp\.socksProxyPort/{print $2; exit}' "$gp" | tr -d ' ')"
    [ -n "$h" ] && [ -n "$p" ] && printf 'socks5://%s:%s' "$h" "$p"
  fi
}
[ -z "$PROXY" ] && PROXY="$(detect_proxy)"
if [ -n "$PROXY" ]; then
  export ALL_PROXY="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
  # The flutter tool talks to the test runner over a localhost WebSocket; make
  # sure that never goes through the proxy.
  export NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1"
  info "proxy   : $PROXY (no_proxy: localhost)"
fi

# ------------------------------------------------------------------ toolchain
command -v flutter >/dev/null 2>&1 || die "flutter not found on PATH"
step "flutter pub get"
flutter pub get

if [ "$ANALYZE" -eq 1 ]; then
  step "flutter analyze"
  flutter analyze
fi

if [ "$TEST" -eq 1 ]; then
  step "flutter test"
  flutter test
fi

# ------------------------------------------------------------------ build
SYMBOLS_DIR="build/symbols"
BUILD_ARGS=(build apk "--$MODE" --target-platform "$TARGET_PLATFORM")
if [ "$MODE" = "release" ] && [ "$OBFUSCATE" -eq 1 ]; then
  BUILD_ARGS+=(--obfuscate --split-debug-info="$SYMBOLS_DIR")
fi
[ -n "$BUILD_NAME" ]   && BUILD_ARGS+=(--build-name "$BUILD_NAME")
[ -n "$BUILD_NUMBER" ] && BUILD_ARGS+=(--build-number "$BUILD_NUMBER")

step "flutter ${BUILD_ARGS[*]}"
flutter "${BUILD_ARGS[@]}"

# ------------------------------------------------------------------ collect
SRC_APK="build/app/outputs/flutter-apk/app-$MODE.apk"
[ -f "$SRC_APK" ] || die "expected APK not found: $SRC_APK"

mkdir -p "$OUT_DIR"
DEST_APK="$OUT_DIR/${APP_NAME}-${SAFE_VERSION}-${ABI}.apk"
cp -f "$SRC_APK" "$DEST_APK"

DEST_SYMBOLS=""
if [ "$MODE" = "release" ] && [ "$OBFUSCATE" -eq 1 ] && [ -d "$SYMBOLS_DIR" ]; then
  DEST_SYMBOLS="$OUT_DIR/${APP_NAME}-${SAFE_VERSION}-symbols.zip"
  rm -f "$DEST_SYMBOLS"
  ( cd "$(dirname "$SYMBOLS_DIR")" && zip -qr "$ROOT/$DEST_SYMBOLS" "$(basename "$SYMBOLS_DIR")" )
fi

# ------------------------------------------------------------------ report
step "artifacts"
ls -lh "$DEST_APK" | awk '{print "  APK    : "$9"  ("$5")"}'
[ -n "$DEST_SYMBOLS" ] && ls -lh "$DEST_SYMBOLS" | awk '{print "  symbols: "$9"  ("$5")"}'
if command -v shasum >/dev/null 2>&1; then
  printf '  sha256 : %s\n' "$(shasum -a 256 "$DEST_APK" | awk '{print $1}')"
fi
printf '\n%sDone.%s\n' "$GREEN$BOLD" "$RESET"
