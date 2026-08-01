#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${CONFIG:-release}"
APP_DIR="$ROOT/.build/MeetBar.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

cd "$ROOT"
mkdir -p "$ROOT/.build/cache/clang" "$ROOT/.build/cache/swiftpm"
export CLANG_MODULE_CACHE_PATH="$ROOT/.build/cache/clang"
export SWIFTPM_HOME="$ROOT/.build/cache/swiftpm"
export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"
mkdir -p "$ROOT/.build/$CONFIG"
swiftc \
  -sdk "$SDKROOT" \
  -target arm64-apple-macosx13.0 \
  -framework AppKit \
  -framework Foundation \
  "$ROOT/Sources/MeetBar/main.swift" \
  -o "$ROOT/.build/$CONFIG/MeetBar"

rm -rf "$APP_DIR"
mkdir -p "$MACOS"
cp "$ROOT/.build/$CONFIG/MeetBar" "$MACOS/MeetBar"
cp "$ROOT/Info.plist" "$CONTENTS/Info.plist"

echo "$APP_DIR"
