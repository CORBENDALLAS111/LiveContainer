#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT="$ROOT/build"
mkdir -p "$OUT"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
echo "SDK: $SDK"
xcrun --sdk iphoneos clang \
  -arch arm64 \
  -isysroot "$SDK" \
  -miphoneos-version-min=15.0 \
  -fobjc-arc \
  -std=gnu11 \
  -O2 \
  -fvisibility=hidden \
  -dynamiclib \
  -framework UIKit \
  -framework CoreGraphics \
  -framework Foundation \
  -Wl,-install_name,@rpath/ChatGPTUsage.dylib \
  -o "$OUT/ChatGPTUsage.dylib" \
  "$ROOT/ChatGPTUsage.m"
if command -v codesign >/dev/null 2>&1; then
  codesign --force --sign - --timestamp=none --identifier com.chatgpt.usageoverlay "$OUT/ChatGPTUsage.dylib"
  codesign --verify --verbose=2 "$OUT/ChatGPTUsage.dylib"
fi
file "$OUT/ChatGPTUsage.dylib"
test -s "$OUT/ChatGPTUsage.dylib"
cp "$ROOT/INSTALL.txt" "$OUT/INSTALL.txt"
(cd "$OUT" && zip -q -9 ChatGPTUsage-LiveContainer.zip ChatGPTUsage.dylib INSTALL.txt)
echo "Build OK: $OUT/ChatGPTUsage.dylib"
