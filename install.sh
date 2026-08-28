#!/bin/bash
set -u
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_GRAY="\033[90m"
get_time() {
    local s="" mot="KittyPlayer"
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
    printf "  ${C_BOLD}KittyPlayer Installer${C_RESET}  (native – no Electron, no Xcode)\n"
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

if [[ "$(uname -s)" != "Darwin" ]]; then
    log "${C_RED}This installer only runs on macOS.${C_RESET}"
    exit 1
fi

REPO="${KITTY_REPO:-kittyy1234/player}"
APP_DIR="/Applications/KittyPlayer.app"
TMP="$(mktemp -d /tmp/KittyPlayer-install.XXXXXX)"
DMG="$TMP/KittyPlayer.dmg"

spinner_start "killing past instances..."
pkill -f "/Applications/KittyPlayer.app" 2>/dev/null || true
pkill -f "KittyPlayer123" 2>/dev/null || true
sleep 0.3
spinner_stop ok "killed past instances"

spinner_start "downloading KittyPlayer.dmg..."
DOWNLOAD_URL=""
if command -v curl >/dev/null 2>&1; then
    API="https://api.github.com/repos/${REPO}/releases/latest"
    DOWNLOAD_URL=$(curl -fsSL "$API" 2>/dev/null \
        | grep -o 'https://[^"]*KittyPlayer\.dmg' \
        | head -1 || true)
fi
if [[ -z "$DOWNLOAD_URL" ]]; then
    DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/KittyPlayer.dmg"
fi

if ! curl -fsSL "$DOWNLOAD_URL" -o "$DMG"; then
    spinner_stop fail "download failed"
    echo ""
    log "Could not download KittyPlayer.dmg from GitHub Releases."
    log "Do this once:"
    log "  1. Push KittyPlayer/ + .github/workflows/build-macos.yml to GitHub"
    log "  2. Open Actions tab → run Build KittyPlayer DMG (or push a tag v1.0.0)"
    log "  3. Create a Release and upload the KittyPlayer.dmg artifact"
    log "  4. Re-run this installer"
    echo ""
    log "Releases: https://github.com/${REPO}/releases"
    rm -rf "$TMP"
    exit 1
fi
spinner_stop ok "downloaded DMG"

spinner_start "installing to /Applications..."
MOUNT_OUT=$(hdiutil attach "$DMG" -nobrowse -readonly 2>&1) || {
    spinner_stop fail "could not open DMG"
    rm -rf "$TMP"
    exit 1
}
MOUNT_DIR=$(echo "$MOUNT_OUT" | grep -o '/Volumes/[^ ]*' | tail -1)
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    spinner_stop fail "DMG mount path not found"
    rm -rf "$TMP"
    exit 1
fi

SRC_APP=$(find "$MOUNT_DIR" -maxdepth 2 -name "KittyPlayer.app" -type d | head -1)
if [[ -z "$SRC_APP" ]]; then
    spinner_stop fail "KittyPlayer.app not inside DMG"
    hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true
    rm -rf "$TMP"
    exit 1
fi

rm -rf "$APP_DIR"
cp -R "$SRC_APP" "$APP_DIR"
hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null || true

xattr -cr "$APP_DIR" 2>/dev/null || true
xattr -d com.apple.quarantine "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null || true

if [[ -d "/Applications/KittyPlayer123.app" ]]; then
    rm -rf "/Applications/KittyPlayer123.app"
fi

spinner_stop ok "installed to /Applications/KittyPlayer.app"
rm -rf "$TMP"

log "${C_GREEN}✔  installed to /Applications/KittyPlayer.app${C_RESET}"
open -R "$APP_DIR"
echo ""
printf "${C_GREEN}✔  All done${C_RESET}\n"
echo ""
printf "ᗢ KittyPlayer\n"
echo "  Open: Spotlight → KittyPlayer   or   open -a KittyPlayer"
echo "  Menu bar ᗢ → Connect Spotify / Show / Hide / Quit"
echo ""
