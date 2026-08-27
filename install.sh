#!/bin/bash
set -u
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_GRAY="\033[90m"
get_time() {
    local s="" mot="KittyPlayer123"
    local couleurs=("180;220;255" "150;200;255" "120;180;255" "90;160;255" "70;140;245" "50;120;230" "40;110;220" "30;100;210")
    for ((i=0; i<${#mot}; i++)); do
        s+="\033[38;2;${couleurs[$((i % ${#couleurs[@]}))]}m${mot:$i:1}"
    done
    s+="${C_RESET}"
    printf "%b" "${s}${C_GRAY}::${C_RESET}${C_GREEN}[$(date +%H:%M:%S)]${C_RESET}"
}
log() { printf "%b %b\n" "$(get_time)" "$1"; }
banner() {
    echo ""
    printf "  ${C_BOLD}KittyPlayer123 Installer${C_RESET}\n"
    printf "${C_GRAY}────────────────────────────────────────────${C_RESET}\n"
    echo ""
}
SPIN_FRAMES=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")
SPINNER_PID=""
SPINNER_MSG=""
spinner_start() {
    SPINNER_MSG="$1"
    printf "\033[?25l\033[?7l"
    ( local i=0; while true; do
        printf "\r\033[2K%b %s  %s" "$(get_time)" "${SPIN_FRAMES[$((i % ${#SPIN_FRAMES[@]}))]}" "$SPINNER_MSG"
        i=$((i+1)); sleep 0.08
    done ) &
    SPINNER_PID=$!; disown "$SPINNER_PID" 2>/dev/null || true
}
spinner_stop() {
    local status="${1:-ok}" msg="${2:-$SPINNER_MSG}"
    if [[ -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
    printf "\r\033[2K"
    case "$status" in
        ok)   printf "%b ${C_GREEN}✔${C_RESET}  %b\n" "$(get_time)" "$msg" ;;
        fail) printf "%b ${C_RED}✖${C_RESET}  %b\n" "$(get_time)" "$msg" ;;
        *)    printf "%b    %b\n" "$(get_time)" "$msg" ;;
    esac
    printf "\033[?7h\033[?25h"
}
cleanup() { [[ -n "$SPINNER_PID" ]] && kill "$SPINNER_PID" 2>/dev/null; printf "\033[?7h\033[?25h"; }
trap cleanup EXIT INT TERM

banner
spinner_start "killing past instances..."
pkill -f "KittyPlayer123" 2>/dev/null || true
sleep 0.5
spinner_stop ok "killed past instances"

ARCH=$(uname -m)
if [[ "$ARCH" == "arm64" ]]; then
    NODE_ARCH="arm64"
else
    NODE_ARCH="x64"
fi

INSTALL_DIR="$HOME/.KittyPlayer123"
APP_DIR="/Applications/KittyPlayer123.app"
REPO_RAW="https://raw.githubusercontent.com/kittyy1234/player/main"
NODE_VERSION="20.17.0"
NODE_DIST="node-v${NODE_VERSION}-darwin-${NODE_ARCH}"
NODE_URL="https://nodejs.org{NODE_VERSION}/${NODE_DIST}.tar.gz"

spinner_start "cleaning..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
spinner_stop ok "cleaned"

spinner_start "downloading app files..."
curl -fsSL "$REPO_RAW/package.json" -o package.json || { spinner_stop fail "download failed"; exit 1; }
curl -fsSL "$REPO_RAW/app.js" -o app.js || { spinner_stop fail "download failed"; exit 1; }
curl -fsSL "$REPO_RAW/overlay.html" -o overlay.html || { spinner_stop fail "download failed"; exit 1; }
curl -fsSL "$REPO_RAW/preload.js" -o preload.js || { spinner_stop fail "download failed"; exit 1; }
curl -fsSL "$REPO_RAW/Icon.png" -o Icon.png || curl -fsSL "$REPO_RAW/icon.png" -o Icon.png || true
spinner_stop ok "app files ready"

spinner_start "setting up Node..."
if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    NODE_BIN=$(command -v node)
    NPM_BIN=$(command -v npm)
else
    curl -fsSL "$NODE_URL" -o node.tar.gz || { spinner_stop fail "Node download failed"; exit 1; }
    tar -xzf node.tar.gz
    rm node.tar.gz
    NODE_BIN="$INSTALL_DIR/$NODE_DIST/bin/node"
    NPM_BIN="$INSTALL_DIR/$NODE_DIST/bin/npm"
    export PATH="$INSTALL_DIR/$NODE_DIST/bin:$PATH"
fi
spinner_stop ok "Node ready"

spinner_start "installing dependencies..."
"$NPM_BIN" install --silent > /dev/null 2>&1 || "$NPM_BIN" install > /dev/null 2>&1
spinner_stop ok "dependencies installed"

spinner_start "creating KittyPlayer123.app..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp Icon.png "$APP_DIR/Contents/Resources/AppIcon.png" 2>/dev/null || true

cat > "$APP_DIR/Contents/MacOS/KittyPlayer123" << EOF
#!/bin/bash
cd "$INSTALL_DIR"
export PATH="$(dirname "$NODE_BIN"):\$PATH"
"$NODE_BIN" app.js &
if [ -d "/Applications/Google Chrome.app" ]; then
    exec "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --app="file://$INSTALL_DIR/overlay.html"
elif [ -d "/Applications/Microsoft Edge.app" ]; then
    exec "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge" --app="file://$INSTALL_DIR/overlay.html"
else
    open "file://$INSTALL_DIR/overlay.html"
fi
EOF
chmod +x "$APP_DIR/Contents/MacOS/KittyPlayer123"

cat > "$APP_DIR/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://apple.com">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>KittyPlayer123</string>
    <key>CFBundleDisplayName</key><string>KittyPlayer123</string>
    <key>CFBundleIdentifier</key><string>com.kittyy1234.KittyPlayer123</string>
    <key>CFBundleVersion</key><string>1.0.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>KittyPlayer123</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>LSUIElement</key><true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>KittyPlayer123 needs to control Spotify.</string>
</dict>
</plist>
EOF

if [[ -f Icon.png ]]; then
    mkdir -p /tmp/KittyIcon.iconset
    sips -z 16 16     Icon.png --out /tmp/KittyIcon.iconset/icon_16x16.png >/dev/null 2>&1
    sips -z 32 32     Icon.png --out /tmp/KittyIcon.iconset/icon_16x16@2x.png >/dev/null 2>&1
    sips -z 32 32     Icon.png --out /tmp/KittyIcon.iconset/icon_32x32.png >/dev/null 2>&1
    sips -z 64 64     Icon.png --out /tmp/KittyIcon.iconset/icon_32x32@2x.png >/dev/null 2>&1
    sips -z 128 128   Icon.png --out /tmp/KittyIcon.iconset/icon_128x128.png >/dev/null 2>&1
    sips -z 256 256   Icon.png --out /tmp/KittyIcon.iconset/icon_128x128@2x.png >/dev/null 2>&1
    sips -z 256 256   Icon.png --out /tmp/KittyIcon.iconset/icon_256x256.png >/dev/null 2>&1
    sips -z 512 512   Icon.png --out /tmp/KittyIcon.iconset/icon_256x256@2x.png >/dev/null 2>&1
    sips -z 512 512   Icon.png --out /tmp/KittyIcon.iconset/icon_512x512.png >/dev/null 2>&1
    sips -z 1024 1024 Icon.png --out /tmp/KittyIcon.iconset/icon_512x512@2x.png >/dev/null 2>&1
    iconutil -c icns /tmp/KittyIcon.iconset -o "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null || true
    rm -rf /tmp/KittyIcon.iconset
fi

spinner_stop ok "KittyPlayer123.app created"

log "✔  installed to /Applications/KittyPlayer123.app"
open -R "$APP_DIR"
echo ""
printf "${C_GREEN}✔  All done${C_RESET}\n"
echo ""
printf "ᗢ KittyPlayer123\n"
echo ""

#moggg
