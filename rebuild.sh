#!/bin/bash
set -e

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MasterConfig"
SCHEME="MasterConfig"
BUILD_DIR="$PROJECT_DIR/.build"
BUILD_APP="$BUILD_DIR/Build/Products/Debug/$APP_NAME.app"

echo "🔒 Fixing entitlements (sandbox off)..."
cat > "$PROJECT_DIR/MasterConfig/Resources/MasterConfig.entitlements" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <false/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

echo "🔨 Building $APP_NAME..."
BUILD_LOG=$(mktemp)

xcodebuild \
  -project "$PROJECT_DIR/$APP_NAME.xcodeproj" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -derivedDataPath "$BUILD_DIR" \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES \
  build 2>&1 | tee "$BUILD_LOG" | grep -E "(Compiling|Linking|BUILD SUCCEEDED|BUILD FAILED)" || true

if grep -q "BUILD FAILED" "$BUILD_LOG"; then
  echo "❌ Build failed"
  grep "error:" "$BUILD_LOG" | grep -v "entitlements" | head -20
  rm "$BUILD_LOG"
  exit 1
fi

rm "$BUILD_LOG"

if [ ! -d "$BUILD_APP" ]; then
  echo "❌ Build output not found: $BUILD_APP"
  exit 1
fi

echo "📦 Installing to /Applications..."
pkill -x "$APP_NAME" 2>/dev/null && sleep 0.5 || true
rm -rf "/Applications/$APP_NAME.app"
cp -R "$BUILD_APP" "/Applications/$APP_NAME.app"

echo "🚀 Launching $APP_NAME..."
open "/Applications/$APP_NAME.app"

echo "✅ Done"
