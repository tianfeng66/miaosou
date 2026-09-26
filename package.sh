#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="1.0.0"
APP="$ROOT/秒搜.app"
BIN="$APP/Contents/MacOS/Miaosou"
DIST="$ROOT/dist"
SDK="$(xcrun --show-sdk-path)"
NAME="秒搜-${VERSION}"

pkill -f '/秒搜.app/Contents/MacOS/Miaosou' 2>/dev/null || true
sleep 0.3

echo "==> 编译应用"
/bin/bash "$ROOT/build.sh"

echo "==> 尝试生成通用二进制（Apple 芯片 + Intel）"
TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

swiftc -O -whole-module-optimization \
  -target arm64-apple-macosx14.0 \
  -sdk "$SDK" \
  -framework AppKit -framework Foundation \
  -o "$TMP/Miaosou-arm64" \
  "$ROOT"/Sources/*.swift

ARCHS="arm64"
if swiftc -O -whole-module-optimization \
  -target x86_64-apple-macosx14.0 \
  -sdk "$SDK" \
  -framework AppKit -framework Foundation \
  -o "$TMP/Miaosou-x86_64" \
  "$ROOT"/Sources/*.swift 2>"$TMP/x86.log"; then
  lipo -create -output "$BIN" "$TMP/Miaosou-arm64" "$TMP/Miaosou-x86_64"
  ARCHS="arm64 x86_64"
  echo "    已合成 arm64 + x86_64"
else
  cp "$TMP/Miaosou-arm64" "$BIN"
  chmod +x "$BIN"
  echo "    Intel 切片编译失败，安装包仅支持 Apple 芯片"
  sed -n '1,20p' "$TMP/x86.log" || true
fi
chmod +x "$BIN"

echo "==> 签名"
codesign --force --deep --sign - --timestamp=none "$APP"

echo "==> 整理 dist"
rm -rf "$DIST"
mkdir -p "$DIST/pkg" "$DIST/dmg"

pkgbuild \
  --component "$APP" \
  --install-location /Applications \
  --identifier local.tian.miaosou \
  --version "$VERSION" \
  --min-os-version 14.0 \
  "$DIST/pkg/秒搜-component.pkg"

productbuild \
  --distribution "$ROOT/installer/Distribution.xml" \
  --resources "$ROOT/installer" \
  --package-path "$DIST/pkg" \
  "$DIST/${NAME}.pkg"

cp "$ROOT/installer/使用说明.txt" "$DIST/dmg/使用说明.txt"
cp -R "$APP" "$DIST/dmg/秒搜.app"
ln -s /Applications "$DIST/dmg/应用程序"

hdiutil create \
  -volname "秒搜 ${VERSION}" \
  -srcfolder "$DIST/dmg" \
  -ov -format UDZO \
  "$DIST/${NAME}.dmg" >/dev/null

ditto -c -k --keepParent --sequesterRsrc "$APP" "$DIST/${NAME}.zip"

rm -rf "$DIST/pkg" "$DIST/dmg"

echo
echo "可以发给别人的安装包："
echo "  安装程序：$DIST/${NAME}.pkg"
echo "  磁盘映像：$DIST/${NAME}.dmg"
echo "  压缩包  ：$DIST/${NAME}.zip"
echo "  架构    ：$ARCHS"
ls -lh "$DIST/${NAME}".pkg "$DIST/${NAME}".dmg "$DIST/${NAME}".zip
file "$BIN"
