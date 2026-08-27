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
    local mot="kitty123"
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
    printf "  ${C_BOLD}Installer${C_RESET}\n"
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
            printf "\r\033[2K%b %s  %s" "$(get_time)" "$frame" "$SPINNER_MSG"
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
        warn) printf "%b ${C_RED}❣${C_RESET}  %b\n"   "$(get_time)" "$msg" ;;
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

spinner_start "killing past overlays..."
pkill -f "kitty123" 2>/dev/null || true
sleep 0.7
spinner_stop ok "killed past overlays"

REPO_RAW="https://githubusercontent.com"
INSTALL_DIR="$HOME/.kitty123-src"

spinner_start "cleaned"
rm -rf "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
sleep 0.5
spinner_stop ok "cleaned"

spinner_start "downloading app..."
curl -fsSL "$REPO_RAW/package.json" -o package.json || { spinner_stop warn "build failed"; echo ""; printf "${C_RED}✖  Build Failed${C_RESET}\n"; exit 1; }
curl -fsSL "$REPO_RAW/app.js" -o app.js || { spinner_stop warn "build failed"; echo ""; printf "${C_RED}✖  Build Failed${C_RESET}\n"; exit 1; }
curl -fsSL "$REPO_RAW/overlay.html" -o overlay.html || { spinner_stop warn "build failed"; echo ""; printf "${C_RED}✖  Build Failed${C_RESET}\n"; exit 1; }
curl -fsSL "$REPO_RAW/icon.png" -o icon.png || { spinner_stop warn "build failed"; echo ""; printf "${C_RED}✖  Build Failed${C_RESET}\n"; exit 1; }
spinner_stop ok "app downloaded..."

spinner_start "finalizing"
npm install --silent > /dev/null 2>&1 || npm install > /dev/null 2>&1
spinner_stop ok "finalizing"

npx electron-builder --mac --dir > /dev/null 2>&1 || true
APP_PATH=$(find "$INSTALL_DIR/dist" -name "*.app" 2>/dev/null | head -1)

if [[ -d "$APP_PATH" ]]; then
    log "✔  build complete"
    FINAL_APP="/Applications/kitty123.app"
    rm -rf "$FINAL_APP"
    cp -R "$APP_PATH" "$FINAL_APP"
    open -R "$FINAL_APP"
    echo ""
    printf "${C_GREEN}✔  All done${C_RESET}\n"
    echo ""
    printf "ᗢ developed by kittyy123 :3\n"
    echo ""
else
    if [[ -n "$SPINNER_PID" ]]; then kill "$SPINNER_PID" 2>/dev/null; fi
    printf "\r\033[2K"
    printf "%b ${C_RED}❣${C_RESET}  build failed\n" "$(get_time)"
    echo ""
    printf "${C_RED}✖  Build Failed${C_RESET}\n"
    nohup npm start > "$INSTALL_DIR/overlay.log" 2>&1 &
    disown
fi

#mogx2
