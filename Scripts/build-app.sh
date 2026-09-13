#!/bin/bash
# 组装 dist/DevLauncher.app。
#
# swift build 产出的是命令行可执行文件，不是 .app —— 没有 .app 就没法「真实启动、
# 真实复制内容触发弹窗」，而那是这个项目验收的唯一形式（decisions.md D13）。
#
# 先跑 swift test 再打包：让一个已知越界的构建走到实机验证那一步是在浪费那一步。
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$PWD"
APP="$ROOT/dist/DevLauncher.app"
VERSION="0.1.0"
BUNDLE_ID="io.ianwang.DevLauncher"
ICON_SOURCE="$ROOT/Assets/DevLauncher-AppIcon-1024.png"
ICONSET="$ROOT/.build/DevLauncher.iconset"
ICON_FILE="$ROOT/.build/DevLauncher.icns"

echo "==> swift test"
swift test

echo "==> swift build -c release"
swift build -c release

BIN="$(swift build -c release --show-bin-path)/DevLauncherApp"
[ -x "$BIN" ] || { echo "找不到可执行文件：$BIN" >&2; exit 1; }

echo "==> 组装 $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DevLauncher"

[ -f "$ICON_SOURCE" ] || { echo "找不到应用图标：$ICON_SOURCE" >&2; exit 1; }
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET/icon_512x512.png" >/dev/null
cp "$ICON_SOURCE" "$ICONSET/icon_512x512@2x.png"
iconutil --convert icns "$ICONSET" --output "$ICON_FILE"
cp "$ICON_FILE" "$APP/Contents/Resources/DevLauncher.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>DevLauncher</string>
    <key>CFBundleDisplayName</key>           <string>DevLauncher</string>
    <key>CFBundleIdentifier</key>            <string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key>            <string>DevLauncher</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>CFBundleIconFile</key>              <string>DevLauncher.icns</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>LSMinimumSystemVersion</key>        <string>26.0</string>
    <key>NSHighResolutionCapable</key>       <true/>
    <!-- false：有 Dock 图标和真实窗口。菜单栏常驻形态是将来的事。 -->
    <key>LSUIElement</key>                   <false/>
</dict>
</plist>
PLIST

# 不签名、不公证（自用）。但要打一个 ad-hoc 签名，否则 Gatekeeper 在某些路径下会直接拒绝启动。
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "   （ad-hoc 签名失败，继续）"

echo "==> 完成：$APP"
du -sh "$APP" | awk '{print "    大小 " $1}'
