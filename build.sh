#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="CodexHelper"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/dist/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

echo ">> 编译 $APP_NAME ..."
cd "$ROOT"
swift build -c release

echo ">> 打包 .app ..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"

cp "$BUILD_DIR/$APP_NAME" "$MACOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"

chmod +x "$MACOS/$APP_NAME"

echo ">> 完成: $APP_DIR"
echo "   运行: open \"$APP_DIR\""
