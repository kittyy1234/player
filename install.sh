#!/bin/bash
set -u
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_GREEN="\033[32m"
C_RED="\033[31m"
C_YELLOW="\033[33m"
C_CYAN="\033[36m"
C_GRAY="\033[90m"

get_time() {
    local s=""
    local mot="kittyy1234"
    local couleurs=("180;220;255" "150;200;255" "120;180;255" "90;160;255" "70;140;245" "50;120;230" "40;110;220" "30;100;210" "25;90;200" "20;80;190")
    for ((i=0; i<${#mot}; i++)); do
        s+="\033[38;2;${couleurs[$((i % ${#couleurs[@]}))]}m${mot:$i:1}"
    done
    s+="${C_RESET}"
    printf "%b" "${s}${C_GRAY}::${C_RESET}${C_GREEN}[$(date +%H:%M:%S)]${C_RESET}"
}

log() { printf "%b %b\n" "$(get_time)" "$1"; }
die() { spinner_stop "fail" "$1"; exit 1; }

banner() {
    local line="────────────────────────────────────────────"
    echo ""
    printf "${C_GRAY}%s${C_RESET}\n" "$line"
    printf "  %b  ${C_BOLD}Installer${C_RESET}\n" "$(printf "\033[38;2;120;180;255m%s\033[0m" "kitty123")"
    printf "${C_GRAY}%s${C_RESET}\n" "$line"
    echo ""
}

SPIN_FRAMES=("⣾" "⣽" "⣻" "⢿" "⡿" "⣟" "⣯" "⣷")
SPINNER_PID=""
SPINNER_MSG=""

spinner_start() {
    SPINNER_MSG="$1"
    printf "\033[?25l\033[?7l"
    (
        local i=0
        while true; do
            local frame="${SPIN_FRAMES[$((i % ${#SPIN_FRAMES[@]}))]}"
            printf "\r\033[2K%b ${C_CYAN}%s${C_RESET}  %s" "$(get_time)" "$frame" "$SPINNER_MSG"
            i=$((i+1))
            sleep 0.08
        done
    ) &
    SPINNER_PID=$!
    disown "$SPINNER_PID" 2>/dev/null || true
}

spinner_stop() {
    local status="${1:-ok}"
    local msg="${2:-$SPINNER_MSG}"
    if [[ -n "$SPINNER_PID" ]] && kill -0 "$SPINNER_PID" 2>/dev/null; then
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null || true
    fi
    SPINNER_PID=""
    printf "\r\033[2K"
    case "$status" in
        ok)   printf "%b ${C_GREEN}✔${C_RESET}  %b\n" "$(get_time)" "$msg" ;;
        fail) printf "%b ${C_RED}✖${C_RESET}  %b\n"   "$(get_time)" "$msg" ;;
        warn) printf "%b ${C_YELLOW}!${C_RESET}  %b\n" "$(get_time)" "$msg" ;;
        *)    printf "%b    %b\n" "$(get_time)" "$msg" ;;
    esac
    printf "\033[?7h\033[?25h"
}

cleanup() {
    [[ -n "$SPINNER_PID" ]] && kill "$SPINNER_PID" 2>/dev/null
    printf "\033[?7h\033[?25h"
}
trap cleanup EXIT INT TERM

banner

spinner_start "stopping old processes..."
pkill -f "kitty123" 2>/dev/null || true
sleep 0.7
spinner_stop ok "old processes stopped"

REPO_RAW="https://raw.githubusercontent.com/kitty123/player/refs/heads/main"
INSTALL_DIR="$HOME/.kitty123-src"

spinner_start "cleaning previous install..."
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
spinner_stop ok "clean"

spinner_start "downloading app files..."
curl -fsSL "$REPO_RAW/package.json" -o package.json
curl -fsSL "$REPO_RAW/app.js" -o app.js
curl -fsSL "$REPO_RAW/preload.js" -o preload.js
curl -fsSL "$REPO_RAW/overlay.html" -o overlay.html
spinner_stop ok "files downloaded"

mkdir -p "$INSTALL_DIR/build"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x10\x00\x00\x00\x10\x08\x06\x00\x00\x00\x1f\xf3\xffa\x00\x00\x00\x19tEXtSoftware\x00Adobe ImageReadyq\xc9e<\x00\x00\x00\x0eIDATx\xdab\xfa\xcf\xc0\xc0\xc0\xc0\x00\x00\x00\x05\x00\x01\x0d\n-\xdb\x00\x00\x00\x00IEND\xaeB`\x82' > "$INSTALL_DIR/build/icon.png"
cp "$INSTALL_DIR/build/icon.png" "$INSTALL_DIR/icon.png"

spinner_start "installing dependencies..."
npm install --silent > /dev/null 2>&1 || npm install > /dev/null 2>&1
spinner_stop ok "dependencies installed"

spinner_start "building app..."
npx electron-builder --mac --dir > /dev/null 2>&1 || true
spinner_stop ok "build complete"

APP_PATH=$(find "$INSTALL_DIR/dist" -name "*.app" 2>/dev/null | head -1)

if [[ -d "$APP_PATH" ]]; then
    FINAL_APP="/Applications/kitty123.app"
    rm -rf "$FINAL_APP"
    cp -R "$APP_PATH" "$FINAL_APP"
    printf "\n${C_GREEN}✔  Installed to /Applications/kitty123.app${C_RESET}\n\n"
    printf "  ${C_BOLD}First launch only:${C_RESET} macOS will say this app is from an\n"
    printf "  unidentified developer. In Finder, ${C_BOLD}right-click kitty123.app\n"
    printf "  and choose Open${C_RESET}, then click Open again on the dialog.\n"
    printf "  After that first time, it opens normally like any other app.\n\n"
    open -R "$FINAL_APP"
else
    spinner_stop warn "build failed — launching in dev mode instead"
    nohup npm start > "$INSTALL_DIR/overlay.log" 2>&1 &
    disown
fi

echo ""
printf "  ${C_GREEN}✔  All done — kitty123 is ready${C_RESET}\n"
echo ""
log "App: /Applications/kitty123.app"
log "Open it once, close it, it appears/disappears each time you do"
echo ""
