#!/bin/bash
# Build KittyPlayer.app (universal arm64 + x86_64) and KittyPlayer.dmg
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$ROOT/.." && pwd)"
BUILD="$ROOT/build"
APP_NAME="KittyPlayer"
APP="$BUILD/$APP_NAME.app"
DMG="$BUILD/$APP_NAME.dmg"
SOURCES="$ROOT/Sources/KittyPlayer"
RESOURCES="$ROOT/Resources"
ICON_REPO="${KITTY_REPO:-kittyy1234/player}"
ICON_URL="https://raw.githubusercontent.com/${ICON_REPO}/main/Icon.png"

echo "Building $APP_NAME (universal)…"
rm -rf "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
SRC=( "$SOURCES"/*.swift )
for ARCH in arm64 x86_64; do
  echo "  compiling $ARCH"
  OUT="$BUILD/KittyPlayer-$ARCH"
  swiftc -O -target "${ARCH}-apple-macos12" \
    -framework AppKit -framework WebKit -framework Foundation \
    "${SRC[@]}" \
    -o "$OUT"
done
lipo -create "$BUILD/KittyPlayer-arm64" "$BUILD/KittyPlayer-x86_64" \
  -output "$APP/Contents/MacOS/KittyPlayer"
chmod +x "$APP/Contents/MacOS/KittyPlayer"
cp "$RESOURCES/overlay.html" "$APP/Contents/Resources/overlay.html"

# App icon: look locally first, then fall back to downloading it from GitHub
ICON_SRC=""
for candidate in \
  "$REPO_ROOT/Icon.png" \
  "$ROOT/Icon.png" \
  "$RESOURCES/Icon.png" \
  "$RESOURCES/AppIcon.icns"
do
  if [[ -f "$candidate" ]]; then
    ICON_SRC="$candidate"
    break
  fi
done

if [[ -z "$ICON_SRC" ]]; then
  echo "  Icon.png not found locally — downloading from $ICON_URL"
  ICON_CACHE_DIR="$BUILD/icon-download"
  mkdir -p "$ICON_CACHE_DIR"
  ICON_DOWNLOAD="$ICON_CACHE_DIR/Icon.png"
  if curl -fsSL "$ICON_URL" -o "$ICON_DOWNLOAD" && [[ -s "$ICON_DOWNLOAD" ]]; then
    ICON_SRC="$ICON_DOWNLOAD"
    echo "  downloaded icon → $ICON_SRC"
  else
    echo "  could not download icon (check KITTY_REPO / network) — using default app icon"
    rm -f "$ICON_DOWNLOAD"
  fi
fi

ICON_KEY=""
if [[ -n "$ICON_SRC" ]]; then
  if [[ "$ICON_SRC" == *.icns ]]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY=$'\n  <key>CFBundleIconFile</key>\n  <string>AppIcon</string>'
    echo "  icon: $ICON_SRC"
  else
    # Convert PNG → ICNS via iconutil
    ICONSET="$BUILD/AppIcon.iconset"
    mkdir -p "$ICONSET"
    sips -z 16 16     "$ICON_SRC" --out "$ICONSET/icon_16x16.png" >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_16x16@2x.png" >/dev/null
    sips -z 32 32     "$ICON_SRC" --out "$ICONSET/icon_32x32.png" >/dev/null
    sips -z 64 64     "$ICON_SRC" --out "$ICONSET/icon_32x32@2x.png" >/dev/null
    sips -z 128 128   "$ICON_SRC" --out "$ICONSET/icon_128x128.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_128x128@2x.png" >/dev/null
    sips -z 256 256   "$ICON_SRC" --out "$ICONSET/icon_256x256.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_256x256@2x.png" >/dev/null
    sips -z 512 512   "$ICON_SRC" --out "$ICONSET/icon_512x512.png" >/dev/null
    sips -z 1024 1024 "$ICON_SRC" --out "$ICONSET/icon_512x512@2x.png" >/dev/null
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    ICON_KEY=$'\n  <key>CFBundleIconFile</key>\n  <string>AppIcon</string>'
    echo "  icon: $ICON_SRC → AppIcon.icns"
  fi
else
  echo "  (no icon available – default app icon)"
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
  <string>2.0.1</string>
  <key>CFBundleShortVersionString</key>
  <string>2.0.1</string>
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
  <key>NSAppleEventsUsageDescription</key>
  <string>KittyPlayer needs to control Spotify to show track info and playback controls.</string>
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
echo "App: $APP"
echo "Creating DMG…"
STAGE="$BUILD/dmg-stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "KittyPlayer" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
echo "DMG: $DMG"
echo "Done."
