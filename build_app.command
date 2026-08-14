#!/bin/bash
set -e

cd "$(dirname "$0")"

APP_NAME="FCPXMLToResolveImporter"
OUTPUT_APP_NAME="FCPXMLto达芬奇媒体池"
SCHEME="FCPXMLToResolveImporter"
CONFIGURATION="Release"
BUILD_DIR="$(pwd)/build"
DIST_DIR="$(pwd)/dist"

echo "========== 检查 Xcode 命令行工具 =========="
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "错误：没有找到 xcodebuild。请先安装 Xcode，并运行："
  echo "sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  exit 1
fi

echo "========== 清理旧构建 =========="
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$DIST_DIR"

echo "========== 开始构建 macOS App =========="
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="$BUILD_DIR/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [ ! -d "$APP_PATH" ]; then
  echo "错误：没有找到构建产物：$APP_PATH"
  exit 1
fi

echo "========== 拷贝 App 到 dist =========="
cp -R "$APP_PATH" "$DIST_DIR/$OUTPUT_APP_NAME.app"

echo "========== 完成 =========="
echo "App 已生成："
echo "$DIST_DIR/$OUTPUT_APP_NAME.app"
echo ""
echo "如果 macOS 提示无法打开，可在终端执行："
echo "xattr -dr com.apple.quarantine \"$DIST_DIR/$OUTPUT_APP_NAME.app\""
