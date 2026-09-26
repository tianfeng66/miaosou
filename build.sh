#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/秒搜.app"
BIN="$APP/Contents/MacOS/Miaosou"
SDK="$(xcrun --show-sdk-path)"

if [[ -f "$ROOT/Assets/icon-source.jpg" ]]; then
  swift "$ROOT/make_icon.swift" "$ROOT"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Info.plist" "$APP/Contents/Info.plist"
echo -n "APPL????" > "$APP/Contents/PkgInfo"
if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

swiftc -O -whole-module-optimization \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK" \
  -framework AppKit \
  -framework Foundation \
  -o "$BIN" \
  "$ROOT"/Sources/*.swift

chmod +x "$BIN"
echo "已生成：$APP"
