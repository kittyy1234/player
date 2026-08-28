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

REPO="kittyy1234/player"
APP_DIR="/Applications/KittyPlayer.app"
TMP="$(mktemp -d /tmp/KittyPlayer-build.XXXXXX)"

spinner_start "killing past instances..."
pkill -f "/Applications/KittyPlayer.app" 2>/dev/null || true
pkill -f "KittyPlayer123" 2>/dev/null || true
sleep 0.3
spinner_stop ok "killed past instances"

spinner_start "cloning repository source code..."
if ! git clone --depth 1 "https://github.com{REPO}.git" "$TMP/repo" >/dev/null 2>&1; then
    spinner_stop fail "failed to clone repository"
    rm -rf "$TMP"
    exit 1
fi
spinner_stop ok "cloned source code successfully"

spinner_start "compiling KittyPlayer locally..."
cd "$TMP/repo/KittyPlayer" || {
    spinner_stop fail "project directory structure error"
    rm -rf "$TMP"
    exit 1
}

chmod +x build.sh
if ! ./build.sh >/dev/null 2>&1; then
    spinner_stop fail "local compilation failed via build.sh"
    rm -rf "$TMP"
    exit 1
fi
spinner_stop ok "compiled local application successfully"

SRC_APP=""
if [[ -d "./KittyPlayer.app" ]]; then
    SRC_APP="./KittyPlayer.app"
elif [[ -d "./.build/release/KittyPlayer.app" ]]; then
    SRC_APP="./.build/release/KittyPlayer.app"
elif [[ -d "./.build/debug/KittyPlayer.app" ]]; then
    SRC_APP="./.build/debug/KittyPlayer.app"
fi

if [[ -z "$SRC_APP" ]]; then
    spinner_stop fail "could not find compiled KittyPlayer.app target bundle"
    rm -rf "$TMP"
    exit 1
fi

spinner_start "installing to /Applications..."
rm -rf "$APP_DIR"
cp -R "$SRC_APP" "$APP_DIR"

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
