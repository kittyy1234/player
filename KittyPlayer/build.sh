#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP_NAME="KittyPlayer"
APP="$BUILD/$APP_NAME.app"
DMG="$BUILD/$APP_NAME.dmg"
SOURCES="$ROOT/Sources/KittyPlayer"
RESOURCES="$ROOT/Resources"

echo "Building $APP_NAME (universal)…"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

SRC=( "$SOURCES"/*.swift )

for ARCH in arm64 x86_64; do
  echo "  → compiling $ARCH"
  OUT="$BUILD/KittyPlayer-$ARCH"
  swiftc -O -target "${ARCH}-apple-macos12" \
    -framework AppKit -framework WebKit -framework Foundation \
    -import-objc-header /dev/null \
    "${SRC[@]}" \
    -o "$OUT" 2>/dev/null || \
  swiftc -O -target "${ARCH}-apple-macos12" \
    -framework AppKit -framework WebKit -framework Foundation \
    "${SRC[@]}" \
    -o "$OUT"
done

lipo -create "$BUILD/KittyPlayer-arm64" "$BUILD/KittyPlayer-x86_64" \
  -output "$APP/Contents/MacOS/KittyPlayer"
chmod +x "$APP/Contents/MacOS/KittyPlayer"

cp "$RESOURCES/overlay.html" "$APP/Contents/Resources/overlay.html"

if [[ -f "$RESOURCES/AppIcon.icns" ]]; then
  cp "$RESOURCES/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
  ICON_KEY=$'\n  <key>CFBundleIconFile</key>\n  <string>AppIcon</string>'
else
  ICON_KEY=""
fi

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>KittyPlayer</string>
  <key>CFBundleDisplayName</key>
  <string>KittyPlayer</string>
  <key>CFBundleIdentifier</key>
  <string>com.kittyy1234.KittyPlayer</string>
  <key>CFBundleVersion</key>
  <string>2.0.0</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0.0</string>
  <key>CFBundleExecutable</key>
  <string>KittyPlayer</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>12.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
  </dict>${ICON_KEY}
</dict>
</plist>
PLIST

echo -n "APPL????" > "$APP/Contents/PkgInfo"

codesign --force --deep --sign - "$APP" 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true

echo "✔  App: $APP"

echo "Creating DMG…"
STAGE="$BUILD/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create -volname "KittyPlayer" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

echo "✔  DMG: $DMG"
echo ""
echo "Install: open \"$DMG\" then drag KittyPlayer → Applications"
echo "Or:     cp -R \"$APP\" /Applications/"
